/**
 * EasyClick YOLO Object Detection Commands Implementation
 * Endpoints: yolo/loadModel, yolo/detect, yolo/close
 */

#import "FBECYoloCommands.h"

#import <iosauto/yolo.h>
#import <iosauto/OnnxYoloObjc.h>

#import "Routing/FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIDevice+FBHelpers.h"

// Singleton YOLO engines
static YoloInter *_sharedNcnnYolo = nil;
static OnnxYoloObjc *_sharedOnnxYolo = nil;
static NSString *_currentYoloEngine = nil;

@implementation FBECYoloCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/yolo/loadModel"].withoutSession respondWithTarget:self action:@selector(handleLoadModel:)],
    [[FBRoute POST:@"/ecnb/yolo/detect"].withoutSession respondWithTarget:self action:@selector(handleDetect:)],
    [[FBRoute POST:@"/ecnb/yolo/close"].withoutSession respondWithTarget:self action:@selector(handleClose:)],
  ];
}

#pragma mark - Helpers

+ (UIImage *)takeScreenshot
{
  NSError *error;
  NSData *data = [[XCUIDevice sharedDevice] fb_screenshotWithError:&error];
  if (nil == data) return nil;
  return [UIImage imageWithData:data];
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleLoadModel:(FBRouteRequest *)request
{
  @try {
    NSString *engine = request.arguments[@"engine"] ?: @"ncnn";
    int numThread = request.arguments[@"numThread"] ? [request.arguments[@"numThread"] intValue] : 4;

    if ([engine isEqualToString:@"ncnn"]) {
      NSString *paramPath = request.arguments[@"paramPath"];
      NSString *binPath = request.arguments[@"binPath"];
      if (nil == paramPath || nil == binPath) {
        return FBECErrorWithCode(-1, @"Parameters 'paramPath' and 'binPath' are required for NCNN engine");
      }

      // Close previous instance if exists
      if (nil != _sharedNcnnYolo) {
        [_sharedNcnnYolo closeYolo];
      }
      _sharedNcnnYolo = [[YoloInter alloc] init];

      int useVulkan = request.arguments[@"useVulkan"] ? [request.arguments[@"useVulkan"] intValue] : 0;
      bool success = [_sharedNcnnYolo loadModelFullPath:paramPath :binPath :numThread :useVulkan];
      if (!success) {
        return FBECErrorWithCode(-3, @"Failed to load NCNN YOLO model");
      }
      _currentYoloEngine = @"ncnn";
      return FBECSuccessWithData(@{@"engine": @"ncnn"});

    } else if ([engine isEqualToString:@"onnx"]) {
      NSString *onnxPath = request.arguments[@"paramPath"] ?: request.arguments[@"onnxPath"];
      NSString *labels = request.arguments[@"binPath"] ?: request.arguments[@"labelsPath"] ?: @"";
      if (nil == onnxPath) {
        return FBECErrorWithCode(-1, @"Parameter 'paramPath' (onnx model path) is required for ONNX engine");
      }

      int inputWidth = request.arguments[@"inputWidth"] ? [request.arguments[@"inputWidth"] intValue] : 640;
      int inputHeight = request.arguments[@"inputHeight"] ? [request.arguments[@"inputHeight"] intValue] : 640;

      // Close previous instance if exists
      if (nil != _sharedOnnxYolo) {
        [_sharedOnnxYolo closeYolo];
      }
      _sharedOnnxYolo = [[OnnxYoloObjc alloc] init];

      bool success = [_sharedOnnxYolo loadModelFullPath:onnxPath :labels :numThread :inputWidth :inputHeight];
      if (!success) {
        NSString *errMsg = [_sharedOnnxYolo getErrMsg] ?: @"Unknown error";
        return FBECErrorWithCode(-3, [NSString stringWithFormat:@"Failed to load ONNX YOLO model: %@", errMsg]);
      }

      // Set thresholds if provided
      float confThreshold = request.arguments[@"confThreshold"] ? [request.arguments[@"confThreshold"] floatValue] : 0.5f;
      float iouThreshold = request.arguments[@"iouThreshold"] ? [request.arguments[@"iouThreshold"] floatValue] : 0.45f;
      [_sharedOnnxYolo setThreshold:confThreshold :iouThreshold];

      _currentYoloEngine = @"onnx";
      return FBECSuccessWithData(@{@"engine": @"onnx"});

    } else {
      return FBECErrorWithCode(-1, [NSString stringWithFormat:@"Unknown YOLO engine: %@. Use 'ncnn' or 'onnx'", engine]);
    }
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during YOLO loadModel");
  }
}

+ (id<FBResponsePayload>)handleDetect:(FBRouteRequest *)request
{
  @try {
    if (nil == _currentYoloEngine) {
      return FBECErrorWithCode(-1, @"YOLO model not loaded. Call /ecnb/yolo/loadModel first");
    }

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    if ([_currentYoloEngine isEqualToString:@"ncnn"]) {
      // Convert UIImage to NSData for NCNN
      CGImageRef cgImage = screenshot.CGImage;
      int width = (int)CGImageGetWidth(cgImage);
      int height = (int)CGImageGetHeight(cgImage);

      // Get raw RGBA pixel data
      NSUInteger bytesPerPixel = 4;
      NSUInteger bytesPerRow = bytesPerPixel * width;
      NSUInteger bitsPerComponent = 8;
      NSMutableData *rawData = [NSMutableData dataWithLength:height * bytesPerRow];

      CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
      CGContextRef context = CGBitmapContextCreate(rawData.mutableBytes, width, height,
                                                    bitsPerComponent, bytesPerRow, colorSpace,
                                                    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
      CGColorSpaceRelease(colorSpace);
      CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
      CGContextRelease(context);

      NSMutableArray *results = [_sharedNcnnYolo detectImageData:rawData :width :height];

      // NCNN returns OnnxYoloObjcResult-like objects
      NSMutableArray *arr = [NSMutableArray array];
      for (id r in results) {
        if ([r isKindOfClass:[OnnxYoloObjcResult class]]) {
          OnnxYoloObjcResult *yoloR = (OnnxYoloObjcResult *)r;
          [arr addObject:@{
            @"clsName": [yoloR getClsName] ?: @"",
            @"clsIndex": @([yoloR getClsIndex]),
            @"x": @([yoloR getX]),
            @"y": @([yoloR getY]),
            @"width": @([yoloR getWidth]),
            @"height": @([yoloR getHeight]),
            @"confidence": @([yoloR getConfidence]),
          }];
        } else {
          // Fallback: try to extract via KVC
          [arr addObject:@{
            @"clsName": [r valueForKey:@"clsName"] ?: @"",
            @"clsIndex": [r valueForKey:@"clsIndex"] ?: @(0),
            @"x": [r valueForKey:@"x"] ?: @(0),
            @"y": [r valueForKey:@"y"] ?: @(0),
            @"width": [r valueForKey:@"width"] ?: @(0),
            @"height": [r valueForKey:@"height"] ?: @(0),
            @"confidence": [r valueForKey:@"confidence"] ?: @(0),
          }];
        }
      }
      return FBECSuccessWithData(arr);

    } else {
      // ONNX engine
      int width = (int)screenshot.size.width;
      int height = (int)screenshot.size.height;

      NSMutableArray *results = [_sharedOnnxYolo detectImageData:screenshot :width :height];

      NSMutableArray *arr = [NSMutableArray array];
      for (OnnxYoloObjcResult *r in results) {
        [arr addObject:@{
          @"clsName": [r getClsName] ?: @"",
          @"clsIndex": @([r getClsIndex]),
          @"x": @([r getX]),
          @"y": @([r getY]),
          @"width": @([r getWidth]),
          @"height": @([r getHeight]),
          @"confidence": @([r getConfidence]),
        }];
      }
      return FBECSuccessWithData(arr);
    }
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during YOLO detect");
  }
}

+ (id<FBResponsePayload>)handleClose:(FBRouteRequest *)request
{
  @try {
    if ([_currentYoloEngine isEqualToString:@"ncnn"] && nil != _sharedNcnnYolo) {
      [_sharedNcnnYolo closeYolo];
      _sharedNcnnYolo = nil;
    }
    if ([_currentYoloEngine isEqualToString:@"onnx"] && nil != _sharedOnnxYolo) {
      [_sharedOnnxYolo closeYolo];
      _sharedOnnxYolo = nil;
    }
    _currentYoloEngine = nil;
    return FBECSuccessWithData(@{@"closed": @(YES)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during YOLO close");
  }
}

@end
