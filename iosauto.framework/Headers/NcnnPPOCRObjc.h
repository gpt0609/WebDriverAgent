//
// Created by wangbx on 2025/10/9.
//




#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface NcnnPPOCRObjc : NSObject {

}

- (void)setNumThread:(int)num_thread;
- (void)setPadding:(int)padding;
- (void)setMaxSideLen:(int)maxSideLen;
- (void)setConfig:(float)threshold1 :(float)box_thresh1;

- (NSString *)detectMat:(NSString *)imageId;
- (NSString *)detect:(UIImage *)image;
- (bool)loadModels:(NSString *)detParamPath :(NSString *)detBinPath :(NSString *)recParamPath :(NSString *)recBinPath :(NSString *)keysPath :(int)numThread :(int)imgSize :(int)useFp16 :(int)useGpu :(int)targetHeight;
@end
