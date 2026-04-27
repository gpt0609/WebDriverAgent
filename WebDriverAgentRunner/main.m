#import <UIKit/UIKit.h>

@interface WDAApplication : UIApplication
@end

@implementation WDAApplication
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, NSStringFromClass([WDAApplication class]), @"WDADelegate");
    }
}
