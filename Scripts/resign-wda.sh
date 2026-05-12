#!/bin/bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  Scripts/resign-wda.sh \
    --input WebDriverAgentRunner-Runner.unsigned.ipa \
    --bundle-id com.example.WebDriverAgentRunner.xctrunner \
    --certificate "Apple Development: Your Name (TEAMID)" \
    --mobileprovision path/to/profile.mobileprovision \
    [--output-dir dist]

Inputs may be an unsigned .ipa, a .app bundle, or an .app.zip artifact.
The bundle id is the final CFBundleIdentifier written into the Runner app.
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

set_plist_string() {
  local plist_path="$1"
  local key_path="$2"
  local value="$3"
  "$PLISTBUDDY" -c "Set :$key_path $value" "$plist_path" 2>/dev/null \
    || "$PLISTBUDDY" -c "Add :$key_path string $value" "$plist_path"
}

absolute_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
    return
  fi
  printf '%s/%s\n' "$(pwd)" "$path"
}

INPUT=""
BUNDLE_ID=""
CERTIFICATE=""
MOBILEPROVISION=""
OUTPUT_DIR="dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --certificate)
      CERTIFICATE="${2:-}"
      shift 2
      ;;
    --mobileprovision)
      MOBILEPROVISION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$INPUT" ]] || fail "--input is required"
[[ -n "$BUNDLE_ID" ]] || fail "--bundle-id is required"
[[ -n "$CERTIFICATE" ]] || fail "--certificate is required"
[[ -n "$MOBILEPROVISION" ]] || fail "--mobileprovision is required"

require_command codesign
require_command security
require_command unzip
require_command zip
[[ -x /usr/libexec/PlistBuddy ]] || fail "Missing required command: /usr/libexec/PlistBuddy"
PLISTBUDDY="/usr/libexec/PlistBuddy"

INPUT="$(absolute_path "$INPUT")"
MOBILEPROVISION="$(absolute_path "$MOBILEPROVISION")"
OUTPUT_DIR="$(absolute_path "$OUTPUT_DIR")"

[[ -e "$INPUT" ]] || fail "Input does not exist: $INPUT"
[[ -f "$MOBILEPROVISION" ]] || fail "Provisioning profile does not exist: $MOBILEPROVISION"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PAYLOAD_DIR="$WORK_DIR/Payload"
mkdir -p "$PAYLOAD_DIR" "$OUTPUT_DIR"

case "$INPUT" in
  *.ipa)
    unzip -q "$INPUT" -d "$WORK_DIR"
    ;;
  *.zip)
    UNZIP_DIR="$WORK_DIR/unzipped"
    mkdir -p "$UNZIP_DIR"
    unzip -q "$INPUT" -d "$UNZIP_DIR"
    if compgen -G "$UNZIP_DIR/Payload/*.app" >/dev/null; then
      cp -R "$UNZIP_DIR/Payload/"*.app "$PAYLOAD_DIR/"
    else
      APP_FROM_ZIP="$(find "$UNZIP_DIR" -maxdepth 2 -type d -name "*.app" -print -quit)"
      [[ -n "$APP_FROM_ZIP" ]] || fail "No .app bundle found in zip: $INPUT"
      cp -R "$APP_FROM_ZIP" "$PAYLOAD_DIR/"
    fi
    ;;
  *.app)
    [[ -d "$INPUT" ]] || fail ".app input is not a directory: $INPUT"
    cp -R "$INPUT" "$PAYLOAD_DIR/"
    ;;
  *)
    fail "Input must be .ipa, .app, or .zip"
    ;;
esac

APP_PATH="$(find "$PAYLOAD_DIR" -maxdepth 1 -type d -name "*.app" -print -quit)"
[[ -n "$APP_PATH" ]] || fail "No app bundle found under Payload"

INFO_PLIST="$APP_PATH/Info.plist"
[[ -f "$INFO_PLIST" ]] || fail "Missing Info.plist in app bundle"
TEST_BUNDLE_PLIST="$APP_PATH/PlugIns/WebDriverAgentRunner.xctest/Info.plist"
LIB_FRAMEWORK_PLIST="$APP_PATH/PlugIns/WebDriverAgentRunner.xctest/Frameworks/WebDriverAgentLib.framework/Info.plist"

FRAMEWORKS_DIR="$APP_PATH/Frameworks"
if [[ -d "$FRAMEWORKS_DIR" ]]; then
  find "$FRAMEWORKS_DIR" -maxdepth 1 -name "XC*.framework" -exec rm -rf {} +
  rm -rf \
    "$FRAMEWORKS_DIR/Testing.framework" \
    "$FRAMEWORKS_DIR/libXCTestSwiftSupport.dylib"
fi

find "$APP_PATH" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
find "$APP_PATH" -name "embedded.mobileprovision" -type f -delete

set_plist_string "$INFO_PLIST" "CFBundleIdentifier" "$BUNDLE_ID"
if [[ -f "$TEST_BUNDLE_PLIST" ]]; then
  set_plist_string "$TEST_BUNDLE_PLIST" "CFBundleIdentifier" "$BUNDLE_ID"
fi
if [[ -f "$LIB_FRAMEWORK_PLIST" ]]; then
  set_plist_string "$LIB_FRAMEWORK_PLIST" "CFBundleIdentifier" "$BUNDLE_ID"
fi

cp "$MOBILEPROVISION" "$APP_PATH/embedded.mobileprovision"

PROFILE_PLIST="$WORK_DIR/profile.plist"
ENTITLEMENTS_PLIST="$WORK_DIR/entitlements.plist"
security cms -D -i "$MOBILEPROVISION" > "$PROFILE_PLIST"
"$PLISTBUDDY" -x -c "Print :Entitlements" "$PROFILE_PLIST" > "$ENTITLEMENTS_PLIST"

TEAM_ID="$("$PLISTBUDDY" -c "Print :TeamIdentifier:0" "$PROFILE_PLIST" 2>/dev/null || true)"
[[ -n "$TEAM_ID" ]] || fail "Could not read TeamIdentifier from provisioning profile"

if "$PLISTBUDDY" -c "Print :application-identifier" "$ENTITLEMENTS_PLIST" >/dev/null 2>&1; then
  "$PLISTBUDDY" -c "Set :application-identifier $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS_PLIST"
fi

if "$PLISTBUDDY" -c "Print :keychain-access-groups" "$ENTITLEMENTS_PLIST" >/dev/null 2>&1; then
  "$PLISTBUDDY" -c "Delete :keychain-access-groups" "$ENTITLEMENTS_PLIST"
  "$PLISTBUDDY" -c "Add :keychain-access-groups array" "$ENTITLEMENTS_PLIST"
  "$PLISTBUDDY" -c "Add :keychain-access-groups:0 string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS_PLIST"
fi

SIGN_OPTIONS=(--force --sign "$CERTIFICATE" --timestamp=none)

while IFS= read -r nested_item; do
  if [[ "$nested_item" == *.xctest ]]; then
    codesign "${SIGN_OPTIONS[@]}" --entitlements "$ENTITLEMENTS_PLIST" "$nested_item"
  else
    codesign "${SIGN_OPTIONS[@]}" "$nested_item"
  fi
done < <(
  find "$APP_PATH" \( -name "*.framework" -o -name "*.dylib" -o -name "*.xctest" \) -print \
    | awk '{ print length, $0 }' \
    | sort -rn \
    | cut -d' ' -f2-
)

codesign "${SIGN_OPTIONS[@]}" --entitlements "$ENTITLEMENTS_PLIST" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
security cms -D -i "$APP_PATH/embedded.mobileprovision" >/dev/null

echo "Runner app bundle id: $("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$INFO_PLIST")"
if [[ -f "$TEST_BUNDLE_PLIST" ]]; then
  echo "Test bundle id: $("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$TEST_BUNDLE_PLIST")"
fi
if [[ -f "$LIB_FRAMEWORK_PLIST" ]]; then
  echo "Framework bundle id: $("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$LIB_FRAMEWORK_PLIST")"
fi

SIGNED_APP_ZIP="$OUTPUT_DIR/WebDriverAgentRunner-Runner.signed.app.zip"
SIGNED_IPA="$OUTPUT_DIR/WebDriverAgentRunner-Runner.signed.ipa"
rm -f "$SIGNED_APP_ZIP" "$SIGNED_IPA"

(
  cd "$PAYLOAD_DIR"
  zip -qry "$SIGNED_APP_ZIP" "$(basename "$APP_PATH")"
)

(
  cd "$WORK_DIR"
  zip -qry "$SIGNED_IPA" Payload
)

echo "Signed app zip: $SIGNED_APP_ZIP"
echo "Signed IPA: $SIGNED_IPA"
