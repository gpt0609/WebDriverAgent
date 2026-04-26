#import <UIKit/UIKit.h>
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <WebDriverAgentLib/FBLogger.h>

@interface FBWDAAppDelegate : NSObject <UIApplicationDelegate, FBWebServerDelegate>
@property (nonatomic, strong) FBWebServer *webServer;
@property (nonatomic, strong) UIWindow *statusWindow;
@end

@implementation FBWDAAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [FBDebugLogDelegateDecorator decorateXCTestLogger];
  [FBConfiguration disableRemoteQueryEvaluation];
  [FBConfiguration configureDefaultKeyboardPreferences];
  [FBConfiguration disableApplicationUIInterruptionsHandling];
  [FBConfiguration disableScreenRecordings];
  [FBConfiguration disableScreenshots];

  self.webServer = [[FBWebServer alloc] init];
  self.webServer.delegate = self;

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self.webServer startServing];
  });

  [FBLogger logFmt:@"WDA started via app icon tap. HTTP server should be running on port 8100."];

  [self showAutomationRunningAlert];

  return YES;
}

- (void)showAutomationRunningAlert {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;

    self.statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, screenWidth, screenHeight)];
    self.statusWindow.windowLevel = UIWindowLevelStatusBar + 1;
    self.statusWindow.backgroundColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:0.5];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    self.statusWindow.rootViewController = vc;

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

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissAlert)];
    [alertBox addGestureRecognizer:tapGesture];

    [vc.view addSubview:alertBox];
    [self.statusWindow makeKeyAndVisible];
  });
}

- (void)dismissAlert {
  [UIView animateWithDuration:0.3 animations:^{
    self.statusWindow.alpha = 0;
  } completion:^(BOOL finished) {
    [self.statusWindow resignKeyWindow];
    self.statusWindow.hidden = YES;
    self.statusWindow = nil;
  }];
}

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer {
  [webServer stopServing];
}

@end
