#!/bin/bash
# resign.sh - Resign WebDriverAgent IPA with proper entitlements
#
# Usage:
#   ./resign.sh <input.ipa> <signing_identity> <provisioning_profile> <entitlements.plist> <output.ipa>
#
# Example:
#   ./resign.sh WebDriverAgentRunner-Runner.zip \
#     "iPhone Distribution: Your Name (TEAMID)" \
#     embedded.mobileprovision \
#     WebDriverAgentRunner/WebDriverAgentRunner.entitlements \
#     tj-easyclick-agent.ipa

set -euo pipefail

if [ $# -lt 5 ]; then
    echo "Usage: $0 <input.ipa> <signing_identity> <provisioning_profile> <entitlements.plist> <output.ipa>"
    exit 1
fi

IPA="$1"
IDENTITY="$2"
PROVISION="$3"
ENTITLEMENTS="$4"
OUT="$5"

WORKDIR="/tmp/wda_resign_$$"

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "=== WebDriverAgent IPA Resign Tool ==="
echo "Input:         $IPA"
echo "Identity:      $IDENTITY"
echo "Provision:     $PROVISION"
echo "Entitlements:  $ENTITLEMENTS"
echo "Output:        $OUT"
echo ""

# Step 1: Unzip IPA
echo "[1/5] Unzipping IPA..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"
unzip -q "$IPA"

# Find the .app bundle
APP=$(find Payload -maxdepth 1 -name "*.app" -type d | head -1)
if [ -z "$APP" ]; then
    echo "ERROR: No .app bundle found in Payload/"
    exit 1
fi
echo "  Found app bundle: $APP"

# Step 2: Remove old code signatures
echo "[2/5] Removing old code signatures..."
find "$APP" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true

# Step 3: Embed provisioning profile
echo "[3/5] Embedding provisioning profile..."
cp "$PROVISION" "$APP/embedded.mobileprovision"

# Extract entitlements from provisioning profile if not provided
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "  WARNING: Entitlements file not found at $ENTITLEMENTS"
    echo "  Extracting entitlements from provisioning profile..."
    ENTITLEMENTS="$WORKDIR/extracted_entitlements.plist"
    security cms -D -i "$PROVISION" | \
        plutil -extract Entitlements xml1 -o "$ENTITLEMENTS" - || {
        echo "ERROR: Failed to extract entitlements from provisioning profile"
        exit 1
    }
fi

# Step 4: Resign all embedded frameworks (CRITICAL!)
echo "[4/5] Resigning embedded frameworks..."
FRAMEWORKS_DIR="$APP/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
    # Sign frameworks in reverse dependency order (deepest first)
    find "$FRAMEWORKS_DIR" -name "*.framework" -type d | sort -r | while read -r framework; do
        echo "  Resigning: $(basename "$framework")"
        # Remove extended attributes and old signature
        find "$framework" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
        # Sign the framework
        codesign --force --sign "$IDENTITY" --timestamp=none --deep "$framework"
    done

    # Also sign any dylibs
    find "$FRAMEWORKS_DIR" -name "*.dylib" -type f | while read -r dylib; do
        echo "  Resigning: $(basename "$dylib")"
        codesign --force --sign "$IDENTITY" --timestamp=none "$dylib"
    done
else
    echo "  WARNING: No Frameworks/ directory found"
fi

# Step 5: Resign the main app bundle with entitlements
echo "[5/5] Resigning main app with entitlements..."
codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    --deep \
    "$APP"

echo ""
echo "=== Verifying signature ==="
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|Authority|Entitlements" || true

# Repackage
echo ""
echo "=== Packaging output IPA ==="
cd "$WORKDIR"
zip -qr "$OUT" Payload

echo ""
echo "=== Done! Output: $OUT ==="
ls -lh "$OUT"
