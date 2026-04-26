#import <UIKit/UIKit.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBLogger.h>
#import <XCTest/XCTest.h>

static FBWebServer *_sharedWebServer = nil;
static UIWindow *_statusWindow = nil;

@interface FBWDAAppDelegate : NSObject <UIApplicationDelegate, FBWebServerDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FBWDAAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  self.window.backgroundColor = [UIColor whiteColor];
  UIViewController *rootVC = [[UIViewController alloc] init];
  rootVC.view.backgroundColor = [UIColor whiteColor];
  self.window.rootViewController = rootVC;
  [self.window makeKeyAndVisible];

  @try {
    [FBDebugLogDelegateDecorator decorateXCTestLogger];
  } @catch (NSException *e) {
    NSLog(@"[WDA] decorateXCTestLogger exception: %@", e);
  }

  [FBConfiguration disableRemoteQueryEvaluation];
  [FBConfiguration configureDefaultKeyboardPreferences];
  [FBConfiguration disableApplicationUIInterruptionsHandling];
  [FBConfiguration disableScreenRecordings];
  [FBConfiguration disableScreenshots];

  _sharedWebServer = [[FBWebServer alloc] init];
  _sharedWebServer.delegate = self;

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [_sharedWebServer startServing];
  });

  [FBLogger logFmt:@"WDA started via app icon tap. HTTP server should be running on port 8100."];
  NSLog(@"[WDA] WebDriverAgent server starting... HTTP on port 8100");

  [self showAutomationRunningAlert];

  return YES;
}

- (void)showAutomationRunningAlert {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (_statusWindow != nil) {
      return;
    }

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    _statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenWidth, screenHeight)];
    _statusWindow.windowLevel = UIWindowLevelStatusBar + 100;
    _statusWindow.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.4];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    _statusWindow.rootViewController = vc;

    CGFloat boxW = screenWidth > 320 ? 300 : 280;
    CGFloat boxH = 160;
    CGFloat boxX = (screenWidth - boxW) / 2;
    CGFloat boxY = (screenHeight - boxH) / 2;

    UIView *alertBox = [[UIView alloc] initWithFrame:CGRectMake(boxX, boxY, boxW, boxH)];
    alertBox.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.98];
    alertBox.layer.cornerRadius = 16;
    alertBox.clipsToBounds = YES;
    alertBox.layer.shadowColor = [UIColor blackColor].CGColor;
    alertBox.layer.shadowOffset = CGSizeMake(0, 4);
    alertBox.layer.shadowOpacity = 0.3;
    alertBox.layer.shadowRadius = 12;

    UIView *greenDot = [[UIView alloc] initWithFrame:CGRectMake(20, 20, 12, 12)];
    greenDot.backgroundColor = [UIColor systemGreenColor];
    greenDot.layer.cornerRadius = 6;
    [alertBox addSubview:greenDot];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 14, boxW - 62, 28)];
    titleLabel.text = @"Automation Running";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.textColor = [UIColor blackColor];
    [alertBox addSubview:titleLabel];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(0, 50, boxW, 0.5)];
    divider.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [alertBox addSubview:divider];

    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, boxW - 40, 80)];
    detailLabel.text = @"WebDriverAgent service is active.\nHTTP: http://127.0.0.1:8100/status\nTap anywhere to dismiss.";
    detailLabel.font = [UIFont systemFontOfSize:14];
    detailLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    detailLabel.textAlignment = NSTextAlignmentLeft;
    detailLabel.numberOfLines = 0;
    [alertBox addSubview:detailLabel];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissAlert)];
    [_statusWindow addGestureRecognizer:tapGesture];

    [vc.view addSubview:alertBox];
    [_statusWindow makeKeyAndVisible];

    NSLog(@"[WDA] Automation Running alert displayed");
  });
}

- (void)dismissAlert {
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

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer {
  [webServer stopServing];
}

@end
