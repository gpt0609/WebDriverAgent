import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import path from 'node:path';

const root = process.cwd();

function read(relativePath) {
  return readFileSync(path.join(root, relativePath), 'utf8');
}

for (const relativePath of [
  'LobsterWDAHost/AppDelegate.h',
  'LobsterWDAHost/AppDelegate.m',
  'LobsterWDAHost/ViewController.h',
  'LobsterWDAHost/ViewController.m',
  'LobsterWDAHost/Info.plist',
  'LobsterWDAHost/main.m',
  'Scripts/ci/build-native-ios-host.sh',
  'Scripts/continue-native-wda-goal.ps1',
  'Scripts/resign-native-wda.ps1',
  '.github/workflows/native-wda-host.yml',
  'WebDriverAgent.xcodeproj/xcshareddata/xcschemes/LobsterWDAHost.xcscheme',
]) {
  assert.ok(existsSync(path.join(root, relativePath)), `${relativePath} should exist`);
}

const project = read('WebDriverAgent.xcodeproj/project.pbxproj');
assert.match(project, /LobsterWDAHost \*\/ = \{\s*isa = PBXNativeTarget;/s);
assert.match(project, /productReference = [A-F0-9]+ \/\* LobsterWDAHost\.app \*\//);
assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER = app\.honey4212\.crystal5671;/);
assert.match(project, /WebDriverAgentLib\.framework in Frameworks/);
assert.match(project, /WebDriverAgentLib\.framework in Copy frameworks/);

const appDelegate = read('LobsterWDAHost/AppDelegate.m');
assert.match(appDelegate, /#import <WebDriverAgentLib\/FBWebServer\.h>/);
assert.match(appDelegate, /\[self\.webServer startServing\]/);
assert.match(appDelegate, /\[FBConfiguration disableRemoteQueryEvaluation\]/);
assert.match(appDelegate, /\[FBConfiguration setShouldUseBackgroundRouteQueue:YES\]/);

const fbConfigurationHeader = read('WebDriverAgentLib/Utilities/FBConfiguration.h');
assert.match(fbConfigurationHeader, /setShouldUseBackgroundRouteQueue/);
assert.match(fbConfigurationHeader, /shouldUseBackgroundRouteQueue/);

const fbWebServer = read('WebDriverAgentLib/Routing/FBWebServer.m');
assert.match(fbWebServer, /FBConfiguration\.shouldUseBackgroundRouteQueue/);
assert.match(fbWebServer, /dispatch_queue_create\("com\.facebook\.WebDriverAgent\.RouteQueue"/);
assert.match(fbWebServer, /NSNetService/);
assert.match(fbWebServer, /NSNetServiceBrowser/);
assert.match(fbWebServer, /_wda\._tcp\./);
assert.match(fbWebServer, /\[self\.bonjourService publish\]/);
assert.match(fbWebServer, /\[self\.bonjourBrowser searchForServicesOfType:FBBonjourServiceType inDomain:@""\]/);
assert.match(fbWebServer, /netService:.*didNotPublish/s);
assert.match(fbWebServer, /netServiceBrowser:.*didNotSearch/s);
assert.match(fbWebServer, /stopBonjourService/);

const infoPlist = read('LobsterWDAHost/Info.plist');
assert.match(infoPlist, /NSLocalNetworkUsageDescription/);
assert.match(infoPlist, /NSBonjourServices/);
assert.match(infoPlist, /_wda\._tcp/);
assert.match(infoPlist, /_wda\._tcp\./);
assert.match(infoPlist, /UIApplicationExitsOnSuspend/);
assert.match(infoPlist, /<false\/>/);

const runnerInfoPlist = read('WebDriverAgentRunner/Info.plist');
assert.match(runnerInfoPlist, /NSLocalNetworkUsageDescription/);
assert.match(runnerInfoPlist, /NSBonjourServices/);
assert.match(runnerInfoPlist, /_wda\._tcp/);
assert.match(runnerInfoPlist, /_wda\._tcp\./);

const buildScript = read('Scripts/ci/build-native-ios-host.sh');
assert.match(buildScript, /SCHEME="\$\{SCHEME:-LobsterWDAHost\}"/);
assert.match(buildScript, /CODE_SIGNING_ALLOWED=NO ARCHS=arm64/);
assert.match(buildScript, /LobsterWDAHost\.unsigned\.ipa/);

const runnerBuildScript = read('Scripts/ci/build-real-ios-unsigned.sh');
assert.match(runnerBuildScript, /Ensure-Runner-Local-Network-Plist/);
assert.match(runnerBuildScript, /RUNNER_APP_BUNDLE_ID="\$\{RUNNER_APP_BUNDLE_ID:-\}"/);
assert.match(runnerBuildScript, /RUNNER_XCTEST_BUNDLE_ID="\$\{RUNNER_XCTEST_BUNDLE_ID:-\}"/);
assert.match(runnerBuildScript, /Apply-Runner-Bundle-Identifiers/);
assert.match(runnerBuildScript, /NSBonjourServices/);
assert.match(runnerBuildScript, /_wda\._tcp/);
assert.match(runnerBuildScript, /_wda\._tcp\./);

const runnerWorkflow = read('.github/workflows/wda-ios-unsigned-package.yml');
assert.match(runnerWorkflow, /RUNNER_APP_BUNDLE_ID: app\.honey4212\.crystal5671\.xctrunner/);
assert.match(runnerWorkflow, /RUNNER_XCTEST_BUNDLE_ID: app\.honey4212\.crystal5671/);

const resignScript = read('Scripts/resign-native-wda.ps1');
assert.match(resignScript, /app\.honey4212\.crystal5671/);
assert.match(resignScript, /zsign\.exe/);
assert.match(resignScript, /password\.txt/);
assert.match(resignScript, /Read-CertificatePassword/);
assert.match(resignScript, /withoutNonAsciiLabel/);
assert.doesNotMatch(resignScript, /ConvertTo-SecureString/);

const continueScript = read('Scripts/continue-native-wda-goal.ps1');
assert.match(continueScript, /LobsterWDAHost-unsigned-ipa/);
assert.match(continueScript, /\$RunId/);
assert.match(continueScript, /\$InputIpa/);
assert.match(continueScript, /Using local unsigned IPA/);
assert.match(continueScript, /Test-NativeHostIpa/);
assert.match(continueScript, /Payload\/LobsterWDAHost\.app\/Info\.plist/);
assert.match(continueScript, /WebDriverAgentLib\.framework/);
assert.match(continueScript, /00008030-0001598021E2802E/);
assert.match(continueScript, /app\.honey4212\.crystal5671/);
assert.match(continueScript, /native-wda-host\.yml/);
assert.match(continueScript, /actions\/workflows\/\$Workflow\/dispatches/);
assert.match(continueScript, /resign-native-wda\.ps1/);
assert.match(continueScript, /tidevice -u \$DeviceUdid launch \$BundleId/);
assert.match(continueScript, /\/status/);
assert.match(continueScript, /\/screenshot/);
assert.match(continueScript, /\/source/);
assert.doesNotMatch(continueScript, /gh[pousr]_[A-Za-z0-9_]+/);

console.log('native WDA host smoke checks passed');
