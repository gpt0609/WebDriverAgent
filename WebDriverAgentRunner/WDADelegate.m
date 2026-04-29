#import "WDADelegate.h"
#import <WebDriverAgentLib/FBWebServer.h>
#import <WebDriverAgentLib/FBConfiguration.h>
#import <WebDriverAgentLib/FBDebugLogDelegateDecorator.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>
#import <BackgroundTasks/BackgroundTasks.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>

static NSString *const kBGTaskIdentifier = @"com.apple.WebDriverAgent.background";
static UIWindow *_statusWindow = nil;

@interface WDADelegate () <FBWebServerDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) FBWebServer *webServer;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@property (nonatomic, strong) AVAudioPlayerNode *audioPlayerNode;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, assign) NSInteger backgroundTaskRenewCount;
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
            NSInteger port = FBConfiguration.bindingPortRange.location;
            NSString *ip = [self getWiFiIPAddress] ?: @"127.0.0.1";
            self.statusLabel.text = [NSString stringWithFormat:@"WDA Running: %@:%ld", ip, (long)port];
            self.statusLabel.textColor = [UIColor greenColor];

            // Show "Automation Running" floating alert
            [self showAutomationRunningAlert:ip port:port];
        });
    });

    [self startSilentAudio];
    [self startLocationUpdates];
    [self registerBackgroundTask];
    [self startHeartbeat];

    if (@available(iOS 13.0, *)) {
        [self registerBGTaskScheduler];
    }

    return YES;
}

- (void)startSilentAudio
{
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if (error) {
        NSLog(@"[WDA KeepAlive] Failed to set audio session category: %@", error);
        return;
    }
    [session setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        NSLog(@"[WDA KeepAlive] Failed to activate audio session: %@", error);
        return;
    }

    NSString *silentPath = [[NSBundle mainBundle] pathForResource:@"silent" ofType:@"wav"];
    if (silentPath) {
        NSURL *silentURL = [NSURL fileURLWithPath:silentPath];
        self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:silentURL error:&error];
        if (self.audioPlayer) {
            self.audioPlayer.numberOfLoops = -1;
            self.audioPlayer.volume = 0.0;
            [self.audioPlayer play];
            NSLog(@"[WDA KeepAlive] Silent audio player started (file-based)");
            return;
        }
    }

    NSLog(@"[WDA KeepAlive] No silent.wav found, using AVAudioEngine generator");
    [self startAudioEngineSilent];
}

- (void)startAudioEngineSilent
{
    if (@available(iOS 13.0, *)) {
        self.audioEngine = [[AVAudioEngine alloc] init];
        self.audioPlayerNode = [[AVAudioPlayerNode alloc] init];
        [self.audioEngine attachNode:self.audioPlayerNode];

        AVAudioMixerNode *mainMixer = self.audioEngine.mainMixerNode;
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
        [self.audioEngine connect:self.audioPlayerNode to:mainMixer format:format];

        NSError *error = nil;
        [self.audioEngine startAndReturnError:&error];
        if (error) {
            NSLog(@"[WDA KeepAlive] AVAudioEngine start failed: %@", error);
            return;
        }

        AVAudioFrameCount frameCount = 44100;
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frameCount];
        memset(buffer.floatChannelData[0], 0, frameCount * sizeof(float));
        buffer.frameLength = frameCount;

        [self.audioPlayerNode scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
        [self.audioPlayerNode play];
        NSLog(@"[WDA KeepAlive] AVAudioEngine silent generator started");
    }
}

- (void)startLocationUpdates
{
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    self.locationManager.allowsBackgroundLocationUpdates = YES;
    self.locationManager.pausesLocationUpdatesAutomatically = NO;
    self.locationManager.showsBackgroundLocationIndicator = NO;
    [self.locationManager requestAlwaysAuthorization];
    [self.locationManager startUpdatingLocation];
    [self.locationManager startMonitoringSignificantLocationChanges];
    NSLog(@"[WDA KeepAlive] Location updates started");
}

- (void)registerBackgroundTask
{
    self.backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"[WDA KeepAlive] Background task expiring, attempting renewal...");
        [self endBackgroundTask];
        [self registerBackgroundTask];
    }];
    self.backgroundTaskRenewCount = 0;
    NSLog(@"[WDA KeepAlive] Background task registered: %lu", (unsigned long)self.backgroundTask);
}

- (void)endBackgroundTask
{
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
}

- (void)registerBGTaskScheduler
{
    if (@available(iOS 13.0, *)) {
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBGTaskIdentifier
                                                              usingQueue:nil
                                                           launchHandler:^(__kindof BGTask * _Nonnull task) {
            [self handleBGTask:task];
        }];
        NSLog(@"[WDA KeepAlive] BGTaskScheduler registered");
    }
}

- (void)handleBGTask:(BGTask *)task API_AVAILABLE(ios(13.0))
{
    NSLog(@"[WDA KeepAlive] BGTask triggered: %@", task.identifier);

    if ([task.identifier isEqualToString:kBGTaskIdentifier]) {
        BGProcessingTask *processingTask = (BGProcessingTask *)task;
        processingTask.expirationHandler = ^{
            NSLog(@"[WDA KeepAlive] BGProcessingTask expiring");
            [task setTaskCompletedWithSuccess:NO];
        };

        [self scheduleNextBGTask];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [processingTask setTaskCompletedWithSuccess:YES];
        });
    }
}

- (void)scheduleNextBGTask
{
    if (@available(iOS 13.0, *)) {
        BGProcessingTaskRequest *request = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBGTaskIdentifier];
        request.requiresNetworkConnectivity = NO;
        request.requiresExternalPower = NO;
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:300];

        NSError *error = nil;
        [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
        if (error) {
            NSLog(@"[WDA KeepAlive] BGTaskScheduler submit failed: %@", error);
        } else {
            NSLog(@"[WDA KeepAlive] Next BGTask scheduled in 5 min");
        }
    }
}

- (void)startHeartbeat
{
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                          target:self
                                                        selector:@selector(heartbeatTick)
                                                        userInfo:nil
                                                         repeats:YES];
    NSLog(@"[WDA KeepAlive] Heartbeat timer started (30s interval)");
}

- (void)heartbeatTick
{
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    NSTimeInterval remaining = [[UIApplication sharedApplication] backgroundTimeRemaining];

    if (state == UIApplicationStateBackground) {
        self.backgroundTaskRenewCount++;

        if (self.backgroundTaskRenewCount % 60 == 0) {
            [self endBackgroundTask];
            [self registerBackgroundTask];
            NSLog(@"[WDA KeepAlive] Background task renewed (count: %ld)", (long)self.backgroundTaskRenewCount);
        }

        if (self.audioPlayer && !self.audioPlayer.playing) {
            [self.audioPlayer play];
            NSLog(@"[WDA KeepAlive] Audio player restarted");
        }

        if (@available(iOS 13.0, *)) {
            if (self.audioEngine && !self.audioEngine.isRunning) {
                NSError *error = nil;
                [self.audioEngine startAndReturnError:&error];
                if (!error) {
                    [self.audioPlayerNode play];
                    NSLog(@"[WDA KeepAlive] Audio engine restarted");
                }
            }
        }
    }

    NSLog(@"[WDA KeepAlive] Heartbeat: state=%ld, bgRemaining=%.0fs, renewCount=%ld",
          (long)state, remaining, (long)self.backgroundTaskRenewCount);
}

- (NSString *)getWiFiIPAddress
{
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"[WDA KeepAlive] Location error: %@", error);
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [self registerBackgroundTask];
    [self scheduleNextBGTask];

    if (self.audioPlayer && !self.audioPlayer.playing) {
        [self.audioPlayer play];
    }

    NSLog(@"[WDA KeepAlive] Entered background - keepalive active");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    NSLog(@"[WDA KeepAlive] Entering foreground");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [self endBackgroundTask];
    [self.heartbeatTimer invalidate];
    [self.locationManager stopUpdatingLocation];
    [self.audioPlayer stop];
    if (@available(iOS 13.0, *)) {
        [self.audioEngine stop];
    }
    NSLog(@"[WDA KeepAlive] App terminating");
}

#pragma mark - Automation Running Alert

- (void)showAutomationRunningAlert:(NSString *)ip port:(NSInteger)port
{
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
        alertBox.layer.shadowOpacity = 0.3f;
        alertBox.layer.shadowRadius = 12;

        // Green dot indicator
        UIView *greenDot = [[UIView alloc] initWithFrame:CGRectMake(20, 20, 12, 12)];
        greenDot.backgroundColor = [UIColor systemGreenColor];
        greenDot.layer.cornerRadius = 6;
        [alertBox addSubview:greenDot];

        // Title label
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 14, boxW - 62, 28)];
        titleLabel.text = @"Automation Running";
        titleLabel.font = [UIFont boldSystemFontOfSize:18];
        titleLabel.textAlignment = NSTextAlignmentLeft;
        titleLabel.textColor = [UIColor blackColor];
        [alertBox addSubview:titleLabel];

        // Divider line
        UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(0, 50, boxW, 0.5f)];
        divider.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        [alertBox addSubview:divider];

        // Detail label with connection info
        UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, boxW - 40, 80)];
        NSString *detailText = [NSString stringWithFormat:@"WebDriverAgent service is active.\nHTTP: http://%@:%ld/status\nTap anywhere to dismiss.", ip ?: @"127.0.0.1", (long)port];
        detailLabel.text = detailText;
        detailLabel.font = [UIFont systemFontOfSize:14];
        detailLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
        detailLabel.textAlignment = NSTextAlignmentLeft;
        detailLabel.numberOfLines = 0;
        [alertBox addSubview:detailLabel];

        // Tap gesture to dismiss
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissStatusAlert)];
        [_statusWindow addGestureRecognizer:tapGesture];

        [vc.view addSubview:alertBox];
        [_statusWindow makeKeyAndVisible];

        NSLog(@"[WDA] Automation Running alert displayed");
    });
}

- (void)dismissStatusAlert
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
