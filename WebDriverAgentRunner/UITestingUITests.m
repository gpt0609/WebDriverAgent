/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBFailureProofTestCase.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/XCTestCase.h>

@interface UITestingUITests : FBFailureProofTestCase <FBWebServerDelegate>
@end

@implementation UITestingUITests

static FBWebServer *FBSharedWebServer = nil;

static void FBStartWebServerOnce(id<FBWebServerDelegate> delegate)
{
  if (FBSharedWebServer != nil) {
    return;
  }
  NSLog(@"LobsterWDA: starting FBWebServer");
  FBSharedWebServer = [[FBWebServer alloc] init];
  FBSharedWebServer.delegate = delegate;
  [FBSharedWebServer startServing];
}

+ (void)setUp
{
  [FBDebugLogDelegateDecorator decorateXCTestLogger];
  [FBConfiguration disableRemoteQueryEvaluation];
  [FBConfiguration configureDefaultKeyboardPreferences];
  [FBConfiguration disableApplicationUIInterruptionsHandling];
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREEN_RECORDINGS"]) {
    [FBConfiguration enableScreenRecordings];
  } else {
    [FBConfiguration disableScreenRecordings];
  }
  if (NSProcessInfo.processInfo.environment[@"ENABLE_AUTOMATIC_SCREENSHOTS"]) {
    [FBConfiguration enableScreenshots];
  } else {
    [FBConfiguration disableScreenshots];
  }
  [super setUp];
  if (NSProcessInfo.processInfo.environment[@"WDA_START_IN_CLASS_SETUP"]) {
    NSLog(@"LobsterWDA: WDA_START_IN_CLASS_SETUP requested");
    FBStartWebServerOnce(nil);
  }
}

/**
 Never ending test used to start WebDriverAgent
 */
- (void)testRunner
{
  NSLog(@"LobsterWDA: testRunner entered");
  FBStartWebServerOnce(self);
}

#pragma mark - FBWebServerDelegate

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer
{
  [webServer stopServing];
  FBSharedWebServer = nil;
}

@end
