//
// Created by wangbx on 2024/9/5.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface OcrLiteObjc : NSObject {

}

- (void)setNumThread:(int)num_thread;

//  int padding, int maxSideLen, float boxScoreThresh, float boxThresh,
//        float unClipRatio, bool doAngle, bool mostAngle
- (NSMutableArray *)detect:(UIImage *)image :(int)padding :(int)maxSideLen :(float)boxScoreThresh :(float)boxThresh :(float)unClipRatio :(bool)doAngle :(bool)mostAngle;
- (NSMutableArray *)detectMat:(NSString *)imageId :(int)padding :(int)maxSideLen :(float)boxScoreThresh
        :(float)boxThresh :(float)unClipRatio :(bool)doAngle :(bool)mostAngle ;
- (bool)initModels:(NSString *)detPath :(NSString *)clsPath :(NSString *)recPath :(NSString *)keysPath;
@end

@interface OcrLiteResult : NSObject {
@public
    NSString *label;
    int x;
    int y;
    int width;
    int height;
    float confidence;
}
- (NSString *)getLabel;

- (int)getX;

- (int)getY;

- (int)getWidth;

- (int)getHeight;

- (float)getConfidence;
@end

