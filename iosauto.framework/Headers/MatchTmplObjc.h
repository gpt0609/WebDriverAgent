//
// Created by wangbx on 2024/9/5.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface MatchTmplObjc : NSObject

- (NSMutableArray *)matchTemplate:(UIImage *)image :(UIImage *)tmpl
        :(int)matchMethod
        :(float)weakThreshold
        :(float)strictThreshold
        :(int)maxLevel
        :(int)limit;

- (UIImage *)binaryzationBitmapEx:(UIImage *)image :(int)diameter :(int)adaptiveMethod :(int)blockSize :(int)c :(int)thresholdType :(int)maxValue;
- (UIImage *)grayBitmap:(UIImage *)image;

@end




@interface ImageRect : NSObject {
@public
    int x;
    int y;
    int width;
    int height;
    float similarity;
}

- (int)getX;

- (int)getY;

- (int)getWidth;

- (int)getHeight;

- (float)getSimilarity;
@end


@interface ImagePoint : NSObject {
@public
    int x;
    int y;
    float similarity;
}

- (int)getX;

- (int)getY;

- (float)getSimilarity;

@end