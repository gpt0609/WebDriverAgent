# Build and re-sign WebDriverAgent for real iOS devices

This repository can build an unsigned iOS `WebDriverAgentRunner-Runner` package in
GitHub Actions, then re-sign it on macOS for devices included in your provisioning
profile.

The package is still an XCTest runner. Installing it is not enough to start the
WDA HTTP server; Appium/XCUITest or an equivalent launcher must start the test
runner process.

## 1. Build unsigned artifacts in GitHub Actions

Run the workflow:

```text
Actions -> Build unsigned iOS WDA package -> Run workflow
```

The workflow uses:

```text
macos-15
Xcode 16.4
generic/platform=iOS
CODE_SIGNING_ALLOWED=NO
```

It uploads two artifacts:

```text
WebDriverAgentRunner-Runner.app.zip
WebDriverAgentRunner-Runner.unsigned.ipa
```

Both artifacts remove embedded XCTest runtime files that are unsafe for reuse
across iOS versions:

```text
Frameworks/XC*.framework
Frameworks/Testing.framework
Frameworks/libXCTestSwiftSupport.dylib
```

## 2. Re-sign on macOS

Prerequisites:

- A signing certificate available in the macOS keychain.
- A provisioning profile whose device list includes the target device UDID.
- A final bundle id that matches the provisioning profile.

Example:

```bash
Scripts/resign-wda.sh \
  --input WebDriverAgentRunner-Runner.unsigned.ipa \
  --bundle-id com.example.WebDriverAgentRunner.xctrunner \
  --certificate "Apple Development: Your Name (TEAMID)" \
  --mobileprovision ./profiles/WDA.mobileprovision \
  --output-dir ./dist
```

The script writes:

```text
dist/WebDriverAgentRunner-Runner.signed.ipa
dist/WebDriverAgentRunner-Runner.signed.app.zip
```

The `--bundle-id` value is the exact `CFBundleIdentifier` written into the
Runner app. For Appium's default launch behavior, use a final id ending in
`.xctrunner`, for example:

```text
Final app bundle id:        com.example.WebDriverAgentRunner.xctrunner
Appium updatedWDABundleId:  com.example.WebDriverAgentRunner
```

If you intentionally sign the app without the `.xctrunner` suffix, set
`appium:updatedWDABundleIdSuffix` to an empty string when starting Appium.

## 3. Verify the signed package

After re-signing, the script runs:

```bash
codesign --verify --deep --strict --verbose=2 Payload/WebDriverAgentRunner-Runner.app
security cms -D -i Payload/WebDriverAgentRunner-Runner.app/embedded.mobileprovision
```

You can also inspect the IPA manually:

```bash
unzip -q dist/WebDriverAgentRunner-Runner.signed.ipa -d /tmp/wda-signed
codesign --verify --deep --strict --verbose=2 /tmp/wda-signed/Payload/WebDriverAgentRunner-Runner.app
security cms -D -i /tmp/wda-signed/Payload/WebDriverAgentRunner-Runner.app/embedded.mobileprovision >/dev/null
```

## 4. Install and start WDA

Install with any tool that can install signed iOS packages, such as `tidevice`,
`ios-deploy`, or Appium's `appium:prebuiltWDAPath` flow.

Example Appium capabilities when the final app bundle id ends in `.xctrunner`:

```json
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:udid": "<device-udid>",
  "appium:usePreinstalledWDA": true,
  "appium:updatedWDABundleId": "com.example.WebDriverAgentRunner"
}
```

Example Appium capabilities when Appium should install the re-signed app bundle
for the session:

```json
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:udid": "<device-udid>",
  "appium:usePreinstalledWDA": true,
  "appium:prebuiltWDAPath": "/absolute/path/to/WebDriverAgentRunner-Runner.app"
}
```

If you used a final app bundle id without `.xctrunner`:

```json
{
  "platformName": "iOS",
  "appium:automationName": "XCUITest",
  "appium:udid": "<device-udid>",
  "appium:usePreinstalledWDA": true,
  "appium:updatedWDABundleId": "com.example.WebDriverAgentRunner",
  "appium:updatedWDABundleIdSuffix": ""
}
```

Once Appium starts WDA, verify the HTTP server:

```bash
curl http://<device-ip>:8100/status
```

With USB port forwarding:

```bash
tidevice -u <device-udid> relay 8100 8100
curl http://127.0.0.1:8100/status
```

## Important constraints

- The provisioning profile must include every device UDID that should run the
  re-signed package.
- Free Apple Developer accounts usually cannot create wildcard profiles for this
  workflow; use a paid account if you need broad device coverage.
- Do not commit certificates, private keys, `.p12` files, or provisioning
  profiles to this repository.
