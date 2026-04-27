#import "WDADelegate.h"
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

@interface WDADelegate () <FBWebServerDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) FBWebServer *webServer;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@end

@implementation WDADelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [FBDebugLogDelegateDecorator decorateXCTestLogger];
    [FBConfiguration disableRemoteQueryEvaluation];
    [FBConfiguration configureDefaultKeyboardPreferences];
    [FBConfiguration disableApplicationUIInterruptionsHandling];
    [FBConfiguration disableScreenRecordings];
    [FBConfiguration disableScreenshots];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor blackColor];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, self.window.bounds.size.width, 40)];
    self.statusLabel.text = @"WebDriverAgent Starting...";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    [vc.view addSubview:self.statusLabel];

    UILabel *portLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 160, self.window.bounds.size.width, 30)];
    portLabel.text = @"HTTP: 8100 | MJPEG: 9100";
    portLabel.textColor = [UIColor grayColor];
    portLabel.textAlignment = NSTextAlignmentCenter;
    [vc.view addSubview:portLabel];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.webServer = [[FBWebServer alloc] init];
        self.webServer.delegate = self;
        [self.webServer startServing];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSRange serverPortRange = FBConfiguration.bindingPortRange;
            NSInteger port = serverPortRange.location;
            NSString *ip = [XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"127.0.0.1";
            self.statusLabel.text = [NSString stringWithFormat:@"WDA Running: %@:%ld", ip, (long)port];
            self.statusLabel.textColor = [UIColor greenColor];
        });
    });

    [self startSilentAudio];
    [self startLocationUpdates];

    return YES;
}

- (void)startSilentAudio
{
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if (error) {
        NSLog(@"Failed to set audio session category: %@", error);
        return;
    }
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"Failed to activate audio session: %@", error);
        return;
    }

    NSString *silentPath = [[NSBundle mainBundle] pathForResource:@"silent" ofType:@"wav"];
    if (silentPath) {
        NSURL *silentURL = [NSURL fileURLWithPath:silentPath];
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:silentURL error:&error];
        if (error) {
            NSLog(@"Failed to init audio player: %@", error);
            return;
        }
        self.audioPlayer.numberOfLoops = -1;
        self.audioPlayer.volume = 0.0;
        [self.audioPlayer play];
    }
}

- (void)startLocationUpdates
{
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.allowsBackgroundLocationUpdates = YES;
    self.locationManager.pausesLocationUpdatesAutomatically = NO;
    [self.locationManager requestAlwaysAuthorization];
    [self.locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    self.backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
}

#pragma mark - FBWebServerDelegate

- (void)webServerDidRequestShutdown:(FBWebServer *)webServer
{
    [webServer stopServing];
}

@end
