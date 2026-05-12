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
WebDriverAgentRunner-Runner.full.app.zip
WebDriverAgentRunner-Runner.full.unsigned.ipa
```

The default `WebDriverAgentRunner-Runner.app.zip` and
`WebDriverAgentRunner-Runner.unsigned.ipa` artifacts follow Appium's upstream
real-device packaging strategy. They remove embedded XCTest runtime files that
are unsafe for reuse across iOS versions when Appium launches WDA as a
preinstalled/prebuilt package:

```text
Frameworks/XC*.framework
Frameworks/Testing.framework
Frameworks/libXCTestSwiftSupport.dylib
```

The `full` artifacts keep those frameworks. Use the `full` package when your
goal is to keep the Xcode-style larger runner package, for example when you
want to test manual tapping of the icon and the classic `Automation Running`
behavior. The stripped artifacts are smaller, but this is expected and matches
Appium's official real-device release package size.

## 2. Re-sign on macOS

Prerequisites:

- A signing certificate available in the macOS keychain.
- A provisioning profile whose device list includes the target device UDID.
- A final bundle id that matches the provisioning profile.

Example:

```bash
Scripts/resign-wda.sh \
  --input WebDriverAgentRunner-Runner.full.unsigned.ipa \
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

The `--bundle-id` value is the exact final identifier used for all WDA-owned
bundles inside the package:

- `WebDriverAgentRunner-Runner.app`
- `PlugIns/WebDriverAgentRunner.xctest`
- `PlugIns/WebDriverAgentRunner.xctest/Frameworks/WebDriverAgentLib.framework`

For Appium's default launch behavior, use a final id ending in `.xctrunner`,
for example:

```text
Final app bundle id:        com.example.WebDriverAgentRunner.xctrunner
Appium updatedWDABundleId:  com.example.WebDriverAgentRunner
```

If you intentionally sign the app without the `.xctrunner` suffix, set
`appium:updatedWDABundleIdSuffix` to an empty string when starting Appium.

The script preserves the input package type:

- Input `WebDriverAgentRunner-Runner.full.unsigned.ipa` -> output remains a full package
- Input `WebDriverAgentRunner-Runner.unsigned.ipa` -> output remains a stripped package

Choose the input package based on the launch model you need:

- Manual icon launch / `Automation Running` check -> use the `full` package
- Appium `usePreinstalledWDA` / `prebuiltWDAPath` on iOS 17+ -> use the stripped package

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

Important: `WebDriverAgentRunner-Runner` is still an XCTest runner, not a
normal app. If you want to test manual tapping of the icon, use the signed
`full` package. If you want Appium to launch WDA on iOS 17+, use the signed
stripped package instead.

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

Do not pass `com.example.WebDriverAgentRunner.xctrunner` as
`appium:updatedWDABundleId` in the default case. Appium appends `.xctrunner`
automatically unless `appium:updatedWDABundleIdSuffix` is set to `""`.

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
- The target device must trust the signing profile, have Developer Mode enabled,
  and have the developer disk image mounted before XCTest can launch WDA.
- Do not commit certificates, private keys, `.p12` files, or provisioning
  profiles to this repository.
