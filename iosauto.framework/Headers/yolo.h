//
//  yolo.h
//  ecauto
//
//  Created by wangbx on 2024/8/29.
//

#ifndef yolo_h
#define yolo_h

#import <Foundation/Foundation.h>

@interface Mat : NSObject
- (instancetype)initFromPixels:(NSData *)data :(int)type :(int)w :(int)h;

- (int)w;

- (int)h;

- (int)c;

- (NSData *)toData;

@end


@interface YoloInter : NSObject
- (bool)loadModelFullPath:(NSString *)param_path :(NSString *)bin_path :(int)num_thread :(int)use_vulkan_compute;

- (NSMutableArray *)detectFile:(NSString *)path;

- (NSMutableArray *)detectImageData:(NSData *)data :(int)width :(int)height;

- (NSMutableArray *)detectMat:(NSString *)imageId;

- (void)update:(NSString *)key :(NSString *)value;

- (void)bindCpu:(int)value;

- (void)closeYolo;
@end

#endif /* yolo_h */
