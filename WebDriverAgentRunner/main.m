#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static Class loadClassFromXCTestBundle(NSString *className) {
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"WebDriverAgentRunner" ofType:@"xctest" inDirectory:nil];
    if (bundlePath) {
        NSBundle *xctestBundle = [NSBundle bundleWithPath:bundlePath];
        if (xctestBundle && [xctestBundle load]) {
            Class cls = NSClassFromString(className);
            if (cls) {
                return cls;
            }
        }
    }
    return nil;
}

int main(int argc, char * argv[]) {
    @autoreleasepool {
        Class appDelegateClass = loadClassFromXCTestBundle(@"FBWDAAppDelegate");
        if (appDelegateClass) {
            return UIApplicationMain(argc, argv, nil, NSStringFromClass(appDelegateClass));
        }
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
