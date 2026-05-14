#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-lobster_wda_host_ios}"
SCHEME="${SCHEME:-LobsterWDAHost}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCTS_DIR="${PRODUCTS_DIR:-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos}"
APP_NAME="${APP_NAME:-LobsterWDAHost.app}"
ZIP_PKG_NAME="${ZIP_PKG_NAME:-LobsterWDAHost.app.zip}"
IPA_PKG_NAME="${IPA_PKG_NAME:-LobsterWDAHost.unsigned.ipa}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR}"

APP_PATH="$PRODUCTS_DIR/$APP_NAME"
IPA_WORK_DIR=""

cleanup() {
  if [[ -n "$IPA_WORK_DIR" && -d "$IPA_WORK_DIR" ]]; then
    rm -rf "$IPA_WORK_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

xcodebuild clean build \
  -project WebDriverAgent.xcodeproj \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected native host app was not found at: $APP_PATH" >&2
  exit 1
fi

rm -f "$OUTPUT_DIR/$ZIP_PKG_NAME" "$OUTPUT_DIR/$IPA_PKG_NAME"

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
  echo "Unsigned IPA does not contain Payload/$APP_NAME" >&2
  exit 1
fi

if ! unzip -l "$OUTPUT_DIR/$IPA_PKG_NAME" | grep -q "Payload/$APP_NAME/Frameworks/WebDriverAgentLib.framework/"; then
  echo "Unsigned IPA does not contain WebDriverAgentLib.framework" >&2
  exit 1
fi

echo "Created $OUTPUT_DIR/$ZIP_PKG_NAME"
echo "Created $OUTPUT_DIR/$IPA_PKG_NAME"
