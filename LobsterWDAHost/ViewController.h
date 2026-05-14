#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ViewController : UIViewController

@property (nonatomic, copy, nullable) dispatch_block_t restartHandler;

- (void)updateServiceRunning:(BOOL)running message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
