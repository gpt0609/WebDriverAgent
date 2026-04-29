/**
 * EasyClick OCR Commands Implementation
 * Endpoints: ocr/init, ocr/detect, ocr/detectRegion
 */

#import "FBECOCRCommands.h"

#import <iosauto/OcrLiteObjc.h>
#import <iosauto/OnnxPaddleObjc.h>

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIDevice+FBHelpers.h"

// Singleton OCR engines
static OcrLiteObjc *_sharedOcrLite = nil;
static OnnxPaddleObjc *_sharedOnnxPaddle = nil;
static NSString *_currentOCREngine = nil;

@implementation FBECOCRCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/ocr/init"].withoutSession respondWithTarget:self action:@selector(handleOCRInit:)],
    [[FBRoute POST:@"/ecnb/ocr/detect"].withoutSession respondWithTarget:self action:@selector(handleOCRDetect:)],
    [[FBRoute POST:@"/ecnb/ocr/detectRegion"].withoutSession respondWithTarget:self action:@selector(handleOCRDetectRegion:)],
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

+ (UIImage *)cropImage:(UIImage *)image region:(CGRect)region
{
  CGFloat scale = image.scale;
  CGRect scaledRect = CGRectMake(region.origin.x * scale, region.origin.y * scale,
                                  region.size.width * scale, region.size.height * scale);
  CGRect imageRect = CGRectMake(0, 0, image.size.width * scale, image.size.height * scale);
  scaledRect = CGRectIntersection(scaledRect, imageRect);
  if (CGRectIsEmpty(scaledRect)) return nil;

  CGImageRef croppedRef = CGImageCreateWithImageInRect(image.CGImage, scaledRect);
  if (NULL == croppedRef) return nil;
  UIImage *cropped = [UIImage imageWithCGImage:croppedRef scale:scale orientation:UIImageOrientationUp];
  CGImageRelease(croppedRef);
  return cropped;
}

+ (NSArray *)convertOcrLiteResults:(NSMutableArray *)results
{
  NSMutableArray *arr = [NSMutableArray array];
  for (OcrLiteResult *r in results) {
    [arr addObject:@{
      @"label": [r getLabel] ?: @"",
      @"x": @([r getX]),
      @"y": @([r getY]),
      @"width": @([r getWidth]),
      @"height": @([r getHeight]),
      @"confidence": @([r getConfidence]),
    }];
  }
  return arr;
}

+ (NSArray *)convertPaddleResults:(NSMutableArray *)results
{
  NSMutableArray *arr = [NSMutableArray array];
  for (OnnxPaddleObjcResult *r in results) {
    [arr addObject:@{
      @"label": [r getLabel] ?: @"",
      @"x": @([r getX]),
      @"y": @([r getY]),
      @"width": @([r getWidth]),
      @"height": @([r getHeight]),
      @"confidence": @([r getConfidence]),
    }];
  }
  return arr;
}

+ (NSString *)modelPathForResource:(NSString *)name ofType:(NSString *)ext subdir:(NSString *)subdir
{
  NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:ext inDirectory:subdir];
  if (nil == path) {
    // Try framework bundle
    NSBundle *frameworkBundle = [NSBundle bundleForClass:[OcrLiteObjc class]];
    path = [frameworkBundle pathForResource:name ofType:ext inDirectory:subdir];
  }
  return path;
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleOCRInit:(FBRouteRequest *)request
{
  @try {
    NSString *engine = request.arguments[@"engine"] ?: @"lite";
    NSNumber *numThread = request.arguments[@"numThread"] ?: @(4);

    if ([engine isEqualToString:@"lite"]) {
      if (nil == _sharedOcrLite) {
        _sharedOcrLite = [[OcrLiteObjc alloc] init];
      }
      [_sharedOcrLite setNumThread:numThread.intValue];

      NSString *detPath = [self modelPathForResource:@"det" ofType:@"onnx" subdir:@"ocrlite/model"];
      NSString *clsPath = [self modelPathForResource:@"cls" ofType:@"onnx" subdir:@"ocrlite/model"];
      NSString *recPath = [self modelPathForResource:@"rec" ofType:@"onnx" subdir:@"ocrlite/model"];
      NSString *keysPath = [self modelPathForResource:@"keys" ofType:@"txt" subdir:@"ocrlite/model"];

      if (nil == detPath || nil == clsPath || nil == recPath || nil == keysPath) {
        return FBECErrorWithCode(-2, @"OCR Lite model files not found in bundle");
      }

      bool success = [_sharedOcrLite initModels:detPath :clsPath :recPath :keysPath];
      if (!success) {
        return FBECErrorWithCode(-3, @"Failed to initialize OCR Lite models");
      }
      _currentOCREngine = @"lite";
      return FBECSuccessWithData(@{@"engine": @"lite"});

    } else if ([engine isEqualToString:@"paddle"]) {
      if (nil == _sharedOnnxPaddle) {
        _sharedOnnxPaddle = [[OnnxPaddleObjc alloc] init];
      }
      [_sharedOnnxPaddle setNumThread:numThread.intValue];

      NSString *detPath = [self modelPathForResource:@"det" ofType:@"onnx" subdir:@"paddlelite_models/v5"];
      NSString *clsPath = [self modelPathForResource:@"cls" ofType:@"onnx" subdir:@"paddlelite_models/v5"];
      NSString *recPath = [self modelPathForResource:@"rec" ofType:@"onnx" subdir:@"paddlelite_models/v5"];
      NSString *keysPath = [self modelPathForResource:@"keys" ofType:@"txt" subdir:@"paddlelite_models/v5"];

      if (nil == detPath || nil == clsPath || nil == recPath || nil == keysPath) {
        return FBECErrorWithCode(-2, @"OnnxPaddle model files not found in bundle");
      }

      bool success = [_sharedOnnxPaddle initModels:detPath :clsPath :recPath :keysPath];
      if (!success) {
        return FBECErrorWithCode(-3, @"Failed to initialize OnnxPaddle models");
      }
      _currentOCREngine = @"paddle";
      return FBECSuccessWithData(@{@"engine": @"paddle"});

    } else {
      return FBECErrorWithCode(-1, [NSString stringWithFormat:@"Unknown OCR engine: %@. Use 'lite' or 'paddle'", engine]);
    }
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during OCR init");
  }
}

+ (id<FBResponsePayload>)handleOCRDetect:(FBRouteRequest *)request
{
  @try {
    if (nil == _currentOCREngine) {
      return FBECErrorWithCode(-1, @"OCR engine not initialized. Call /ecnb/ocr/init first");
    }

    int padding = [request.arguments[@"padding"] intValue] ?: 10;
    int maxSideLen = [request.arguments[@"maxSideLen"] intValue] ?: 960;
    float boxScoreThresh = request.arguments[@"boxScoreThresh"] ? [request.arguments[@"boxScoreThresh"] floatValue] : 0.6f;
    float boxThresh = request.arguments[@"boxThresh"] ? [request.arguments[@"boxThresh"] floatValue] : 0.3f;
    float unClipRatio = request.arguments[@"unClipRatio"] ? [request.arguments[@"unClipRatio"] floatValue] : 1.6f;
    bool doAngle = request.arguments[@"doAngle"] ? [request.arguments[@"doAngle"] boolValue] : true;
    bool mostAngle = request.arguments[@"mostAngle"] ? [request.arguments[@"mostAngle"] boolValue] : true;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot for OCR");
    }

    if ([_currentOCREngine isEqualToString:@"lite"]) {
      NSMutableArray *results = [_sharedOcrLite detect:screenshot :padding :maxSideLen :boxScoreThresh :boxThresh :unClipRatio :doAngle :mostAngle];
      return FBECSuccessWithData([self convertOcrLiteResults:results]);
    } else {
      NSMutableArray *results = [_sharedOnnxPaddle detect:screenshot :padding :maxSideLen :boxScoreThresh :boxThresh :unClipRatio :doAngle :mostAngle];
      return FBECSuccessWithData([self convertPaddleResults:results]);
    }
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during OCR detect");
  }
}

+ (id<FBResponsePayload>)handleOCRDetectRegion:(FBRouteRequest *)request
{
  @try {
    if (nil == _currentOCREngine) {
      return FBECErrorWithCode(-1, @"OCR engine not initialized. Call /ecnb/ocr/init first");
    }

    int padding = [request.arguments[@"padding"] intValue] ?: 10;
    int maxSideLen = [request.arguments[@"maxSideLen"] intValue] ?: 960;
    float boxScoreThresh = request.arguments[@"boxScoreThresh"] ? [request.arguments[@"boxScoreThresh"] floatValue] : 0.6f;
    float boxThresh = request.arguments[@"boxThresh"] ? [request.arguments[@"boxThresh"] floatValue] : 0.3f;
    float unClipRatio = request.arguments[@"unClipRatio"] ? [request.arguments[@"unClipRatio"] floatValue] : 1.6f;
    bool doAngle = request.arguments[@"doAngle"] ? [request.arguments[@"doAngle"] boolValue] : true;
    bool mostAngle = request.arguments[@"mostAngle"] ? [request.arguments[@"mostAngle"] boolValue] : true;

    CGFloat regionX = [request.arguments[@"regionX"] doubleValue];
    CGFloat regionY = [request.arguments[@"regionY"] doubleValue];
    CGFloat regionWidth = [request.arguments[@"regionWidth"] doubleValue];
    CGFloat regionHeight = [request.arguments[@"regionHeight"] doubleValue];

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot for OCR");
    }

    UIImage *regionImage = [self cropImage:screenshot region:CGRectMake(regionX, regionY, regionWidth, regionHeight)];
    if (nil == regionImage) {
      return FBECErrorWithCode(-2, @"Failed to crop region from screenshot");
    }

    if ([_currentOCREngine isEqualToString:@"lite"]) {
      NSMutableArray *results = [_sharedOcrLite detect:regionImage :padding :maxSideLen :boxScoreThresh :boxThresh :unClipRatio :doAngle :mostAngle];
      return FBECSuccessWithData([self convertOcrLiteResults:results]);
    } else {
      NSMutableArray *results = [_sharedOnnxPaddle detect:regionImage :padding :maxSideLen :boxScoreThresh :boxThresh :unClipRatio :doAngle :mostAngle];
      return FBECSuccessWithData([self convertPaddleResults:results]);
    }
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during OCR detectRegion");
  }
}

@end
