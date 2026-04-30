/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBFailureProofTestCase.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/XCTestCase.h>
#import <UIKit/UIKit.h>

static FBWebServer *_sharedWebServer = nil;
static UIWindow *_statusWindow = nil;
static BOOL _webServerStarted = NO;

@interface UITestingUITests : FBFailureProofTestCase <FBWebServerDelegate>
@end

@implementation UITestingUITests

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-load-method"
+ (void)load
{
  [super load];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (_sharedWebServer == nil && !_webServerStarted) {
      _webServerStarted = YES;
      [FBConfiguration disableRemoteQueryEvaluation];
      [FBConfiguration configureDefaultKeyboardPreferences];
      [FBConfiguration disableApplicationUIInterruptionsHandling];
      [FBConfiguration disableScreenRecordings];
      [FBConfiguration disableScreenshots];

      _sharedWebServer = [[FBWebServer alloc] init];
      UITestingUITests *delegateInstance = [[UITestingUITests alloc] init];
      _sharedWebServer.delegate = delegateInstance;
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [_sharedWebServer startServing];
      });
      [UITestingUITests showAutomationRunningAlert];
    }
  });
}
#pragma clang diagnostic pop

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

  if (_sharedWebServer == nil && !_webServerStarted) {
    _webServerStarted = YES;
    _sharedWebServer = [[FBWebServer alloc] init];
    UITestingUITests *setUpDelegate = [[UITestingUITests alloc] init];
    _sharedWebServer.delegate = setUpDelegate;
    [_sharedWebServer startServing];
  }
}

- (void)testRunner
{
  NSLog(@"WebDriverAgent testRunner started");

  if (_sharedWebServer == nil && !_webServerStarted) {
    _webServerStarted = YES;
    _sharedWebServer = [[FBWebServer alloc] init];
    _sharedWebServer.delegate = self;
    [_sharedWebServer startServing];
  } else {
    NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
    while (_sharedWebServer && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
  }
}

+ (void)showAutomationRunningAlert
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (_statusWindow != nil) {
      return;
    }

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    _statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenWidth, screenHeight)];
    _statusWindow.windowLevel = UIWindowLevelStatusBar + 1;
    _statusWindow.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.5];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    _statusWindow.rootViewController = vc;

    UIView *alertBox = [[UIView alloc] initWithFrame:CGRectMake((screenWidth - 280) / 2, (screenHeight - 130) / 2, 280, 130)];
    alertBox.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.97];
    alertBox.layer.cornerRadius = 14;
    alertBox.clipsToBounds = YES;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, 240, 28)];
    titleLabel.text = @"Automation Running";
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor blackColor];
    [alertBox addSubview:titleLabel];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(0, 50, 280, 0.5)];
    divider.backgroundColor = [UIColor lightGrayColor];
    [alertBox addSubview:divider];

    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 58, 240, 56)];
    detailLabel.text = @"WebDriverAgent service is active.\nHTTP: http://127.0.0.1:8100/status\nTap to dismiss.";
    detailLabel.font = [UIFont systemFontOfSize:13];
    detailLabel.textColor = [UIColor grayColor];
    detailLabel.textAlignment = NSTextAlignmentCenter;
    detailLabel.numberOfLines = 3;
    [alertBox addSubview:detailLabel];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissStatusAlert)];
    [alertBox addGestureRecognizer:tapGesture];

    [vc.view addSubview:alertBox];
    [_statusWindow makeKeyAndVisible];
  });
}

+ (void)dismissStatusAlert
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIView animateWithDuration:0.3 animations:^{
      _statusWindow.alpha = 0;
    } completion:^(BOOL finished) {
      [_statusWindow resignKeyWindow];
      _statusWindow.hidden = YES;
      _statusWindow = nil;
    }];
  });
}

#pragma mark - FBWebServerDelegate

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer
{
  [webServer stopServing];
}

@end
