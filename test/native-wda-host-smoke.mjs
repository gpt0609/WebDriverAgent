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

const infoPlist = read('LobsterWDAHost/Info.plist');
assert.match(infoPlist, /NSLocalNetworkUsageDescription/);
assert.match(infoPlist, /UIApplicationExitsOnSuspend/);
assert.match(infoPlist, /<false\/>/);

const buildScript = read('Scripts/ci/build-native-ios-host.sh');
assert.match(buildScript, /SCHEME="\$\{SCHEME:-LobsterWDAHost\}"/);
assert.match(buildScript, /CODE_SIGNING_ALLOWED=NO ARCHS=arm64/);
assert.match(buildScript, /LobsterWDAHost\.unsigned\.ipa/);

const resignScript = read('Scripts/resign-native-wda.ps1');
assert.match(resignScript, /app\.honey4212\.crystal5671/);
assert.match(resignScript, /zsign\.exe/);
assert.match(resignScript, /password\.txt/);
assert.match(resignScript, /Read-CertificatePassword/);
assert.match(resignScript, /withoutNonAsciiLabel/);
assert.doesNotMatch(resignScript, /ConvertTo-SecureString/);

const continueScript = read('Scripts/continue-native-wda-goal.ps1');
assert.match(continueScript, /LobsterWDAHost-unsigned-ipa/);
assert.match(continueScript, /00008030-0001598021E2802E/);
assert.match(continueScript, /native-wda-host\.yml/);
assert.match(continueScript, /actions\/workflows\/\$Workflow\/dispatches/);
assert.match(continueScript, /resign-native-wda\.ps1/);
assert.match(continueScript, /\/status/);
assert.match(continueScript, /\/screenshot/);
assert.match(continueScript, /\/source/);
assert.doesNotMatch(continueScript, /gh[pousr]_[A-Za-z0-9_]+/);

console.log('native WDA host smoke checks passed');
