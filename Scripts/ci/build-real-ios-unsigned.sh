#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-appium_wda_ios}"
SCHEME="${SCHEME:-WebDriverAgentRunner}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCTS_DIR="${PRODUCTS_DIR:-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos}"
APP_NAME="${APP_NAME:-${SCHEME}-Runner.app}"
ZIP_PKG_NAME="${ZIP_PKG_NAME:-WebDriverAgentRunner-Runner.app.zip}"
IPA_PKG_NAME="${IPA_PKG_NAME:-WebDriverAgentRunner-Runner.unsigned.ipa}"
FULL_ZIP_PKG_NAME="${FULL_ZIP_PKG_NAME:-WebDriverAgentRunner-Runner.full.app.zip}"
FULL_IPA_PKG_NAME="${FULL_IPA_PKG_NAME:-WebDriverAgentRunner-Runner.full.unsigned.ipa}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR}"
PLIST_BUDDY="${PLIST_BUDDY:-/usr/libexec/PlistBuddy}"
LOCAL_NETWORK_USAGE_DESCRIPTION="Allows WebDriverAgent to advertise its automation HTTP service on the local network."

APP_PATH="$PRODUCTS_DIR/$APP_NAME"
IPA_WORK_DIR=""

cleanup() {
  if [[ -n "$IPA_WORK_DIR" && -d "$IPA_WORK_DIR" ]]; then
    rm -rf "$IPA_WORK_DIR"
  fi
}
trap cleanup EXIT

ensure_plist_string() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if "$PLIST_BUDDY" -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
    "$PLIST_BUDDY" -c "Set :$key $value" "$plist_path"
  else
    "$PLIST_BUDDY" -c "Add :$key string $value" "$plist_path"
  fi
}

ensure_runner_local_network_plist() {
  local plist_path="$1"

  if [[ ! -f "$plist_path" ]]; then
    return
  fi

  ensure_plist_string "$plist_path" NSLocalNetworkUsageDescription "$LOCAL_NETWORK_USAGE_DESCRIPTION"
  "$PLIST_BUDDY" -c "Delete :NSBonjourServices" "$plist_path" >/dev/null 2>&1 || true
  "$PLIST_BUDDY" -c "Add :NSBonjourServices array" "$plist_path"
  "$PLIST_BUDDY" -c "Add :NSBonjourServices:0 string _wda._tcp" "$plist_path"
  "$PLIST_BUDDY" -c "Add :NSBonjourServices:1 string _wda._tcp." "$plist_path"
}

mkdir -p "$OUTPUT_DIR"

xcodebuild clean build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected WDA app was not found at: $APP_PATH" >&2
  exit 1
fi

# Ensure-Runner-Local-Network-Plist
ensure_runner_local_network_plist "$APP_PATH/Info.plist"
if [[ -d "$APP_PATH/PlugIns" ]]; then
  while IFS= read -r -d '' plist_path; do
    ensure_runner_local_network_plist "$plist_path"
  done < <(find "$APP_PATH/PlugIns" -maxdepth 2 -name Info.plist -print0)
fi

rm -f \
  "$OUTPUT_DIR/$ZIP_PKG_NAME" \
  "$OUTPUT_DIR/$IPA_PKG_NAME" \
  "$OUTPUT_DIR/$FULL_ZIP_PKG_NAME" \
  "$OUTPUT_DIR/$FULL_IPA_PKG_NAME"

(
  cd "$PRODUCTS_DIR"
  zip -qry "$OUTPUT_DIR/$FULL_ZIP_PKG_NAME" "$APP_NAME"
)

IPA_WORK_DIR="$(mktemp -d)"
mkdir -p "$IPA_WORK_DIR/Payload"
cp -R "$APP_PATH" "$IPA_WORK_DIR/Payload/"
(
  cd "$IPA_WORK_DIR"
  zip -qry "$OUTPUT_DIR/$FULL_IPA_PKG_NAME" Payload
)

cleanup
IPA_WORK_DIR=""

if ! unzip -l "$OUTPUT_DIR/$FULL_IPA_PKG_NAME" | grep -q "Payload/$APP_NAME/"; then
  echo "Full unsigned IPA does not contain Payload/$APP_NAME" >&2
  exit 1
fi

FRAMEWORKS_DIR="$APP_PATH/Frameworks"
if [[ -d "$FRAMEWORKS_DIR" ]]; then
  find "$FRAMEWORKS_DIR" -maxdepth 1 -name "XC*.framework" -exec rm -rf {} +
  rm -rf \
    "$FRAMEWORKS_DIR/Testing.framework" \
    "$FRAMEWORKS_DIR/libXCTestSwiftSupport.dylib"
fi

(
  cd "$PRODUCTS_DIR"
  zip -qry "$OUTPUT_DIR/$ZIP_PKG_NAME" "$APP_NAME"
)

IPA_WORK_DIR="$(mktemp -d)"
mkdir -p "$IPA_WORK_DIR/Payload"
cp -R "$APP_PATH" "$IPA_WORK_DIR/Payload/"
(
  cd "$IPA_WORK_DIR"
  zip -qry "$OUTPUT_DIR/$IPA_PKG_NAME" Payload
)

if ! unzip -l "$OUTPUT_DIR/$IPA_PKG_NAME" | grep -q "Payload/$APP_NAME/"; then
  echo "Stripped unsigned IPA does not contain Payload/$APP_NAME" >&2
  exit 1
fi

if unzip -l "$OUTPUT_DIR/$IPA_PKG_NAME" | grep -E "Payload/$APP_NAME/Frameworks/(XC.*\.framework|Testing\.framework|libXCTestSwiftSupport\.dylib)" >/dev/null; then
  echo "Stripped unsigned IPA still contains XCTest frameworks that should be removed" >&2
  exit 1
fi

if unzip -l "$OUTPUT_DIR/$ZIP_PKG_NAME" | grep -E "$APP_NAME/Frameworks/(XC.*\.framework|Testing\.framework|libXCTestSwiftSupport\.dylib)" >/dev/null; then
  echo "Stripped unsigned app zip still contains XCTest frameworks that should be removed" >&2
  exit 1
fi

echo "Created $OUTPUT_DIR/$FULL_ZIP_PKG_NAME"
echo "Created $OUTPUT_DIR/$FULL_IPA_PKG_NAME"
echo "Created $OUTPUT_DIR/$ZIP_PKG_NAME"
echo "Created $OUTPUT_DIR/$IPA_PKG_NAME"
