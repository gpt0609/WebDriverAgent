//
// Created by wangbx on 2024/9/19.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface MatObjc : NSObject {

}
- (int)getWidth;

- (NSString *)getNativeAdr;

- (int)getHeight;

- (int)type;

- (int)channels;

- (void)close;

- (NSString *)getMatColorHex:(int)x :(int)y;

- (void)setNativeAdr:(NSString *)adr;
@end

@interface FindColorMatObjc : NSObject {
}
- (void)setLog:(int)log;

- (MatObjc *)makeMat:(UIImage *)image;

- (UIImage *)matConvertUIImage:(NSString *)uuid ;

- (MatObjc *)clipMat:(NSString *)uuid :(int)x :(int)y :(int)w :(int)h;

- (MatObjc *)binaryzationEx:(NSString *)uuid :(int)diameter :(int)adaptiveMethod :(int)blockSize :(int)c :(int)thresholdType :(int)maxValue;
- (MatObjc *)grayImage:(NSString *)uuid ;

- (UIImage *)binaryzationUIImageEx:(UIImage *)image :(int)diameter :(int)adaptiveMethod :(int)blockSize :(int)c :(int)thresholdType :(int)maxValue;
- (UIImage *)grayUIImageEx:(UIImage *)image ;


- (int)cmpColor:(NSString *)matAdr :(NSString *)points :(float)threshold :(int)x :(int)y :(int)w :(int)h;

- (int)cmpMultiColor:(NSString *)matAdr :(NSString *)points :(float)threshold :(int)x :(int)y :(int)w :(int)h;

//  _ firstColor: String,
//                   _ threshold: Float, _ x: Int, _ y: Int, _ w: Int, _ h: Int,
//                   _ limit: Int, _ orz: Int)
- (NSString *)findColor:(NSString *)matAdr :(NSString *)firstColor :(float)threshold :(int)x :(int)y :(int)w :(int)h :(int)limit :(int)orz;

- (NSString *)findNotColor:(NSString *)matAdr :(NSString *)firstColor :(float)threshold :(int)x :(int)y :(int)w :(int)h :(int)limit :(int)orz;

- (NSString *)findMultiColor:(NSString *)matAdr :(NSString *)firstColor :(NSString *)points :(float)threshold :(int)x :(int)y :(int)w :(int)h :(int)limit :(int)orz;

- (NSString *)findImageColor:(NSString *)matAdr :(NSString *)tmplAdr :(float)threshold :(int)x :(int)y :(int)w :(int)h :(int)limit;

- (NSString *)findImageColorEx:(NSString *)matAdr :(NSString *)tmplAdr
        :(int)x :(int)y :(int)w :(int)h :(int)limit
        :(NSString *)firstColorOffset :(float)firstColorThreshold
        :(NSString *)otherColorOffset :(float)otherColorThreshold
        :(float)cmpColorSucThreshold :(int)startRangeX :(int)startRangeY;


- (NSString *)findImageMat:(NSString *)matAdr :(NSString *)tmplAdr
        :(int)x :(int)y :(int)w :(int)h :(int)limit
        :(float)weakThreshold :(float)strictThreshold :(int)matchMethod;


- (NSString *)templateFindMat:(NSString *)matAdr :(NSString *)tmplAdr
        :(int)x :(int)y :(int)w :(int)h :(int)limit
        :(float)weakThreshold :(float)strictThreshold :(int)maxLevel :(int)matchMethod;
@end
