//
// Created by wangbx on 2025/7/13.
//

#ifndef OnnxYoloObjc_h
#define OnnxYoloObjc_h

#import <Foundation/Foundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface OnnxYoloObjc : NSObject
- (bool)loadModelFullPath:(NSString *)onnxPath :(NSString *)labels :(int)numThread :(int)input_width :(int)input_height;

- (NSMutableArray *)detectImageData:(UIImage *)image :(int)width :(int)height;

- (NSMutableArray *)detectMat:(NSString *)imageId;

- (void)closeYolo;

- (bool)setDebug:(int)debug;

- (bool)setThreshold:(float)confThreshold :(float)iouThreshold;

- (NSString *)getErrMsg;
@end


@interface OnnxYoloObjcResult : NSObject {
@public
    NSString *clsName;
    int clsIndex;
    int x;
    int y;
    int width;
    int height;
    float confidence;
}
- (NSString *)getClsName;

- (id)setClsName:(NSString *)clsName;

- (int)getClsIndex;

- (id)setClsIndex:(int)index;

- (int)getX;

- (id)setX:(int)x1;

- (int)getY;

- (id)setY:(int)y1;

- (int)getWidth;

- (id)setWidth:(int)w;

- (int)getHeight;

- (id)setHeight:(int)h;

- (float)getConfidence;

- (id)setConfidence:(float)c;

@end


#endif /* OnnxYoloObjc_h */
