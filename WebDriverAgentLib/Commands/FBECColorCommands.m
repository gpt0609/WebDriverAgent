/**
 * EasyClick Color Commands Implementation
 * Endpoints: findColor, findMultiColor, cmpColor, getPixelColor
 */

#import "FBECColorCommands.h"

#import <iosauto/FindColorMatObjc.h>

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIDevice+FBHelpers.h"

@implementation FBECColorCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/findColor"].withoutSession respondWithTarget:self action:@selector(handleFindColor:)],
    [[FBRoute POST:@"/ecnb/findMultiColor"].withoutSession respondWithTarget:self action:@selector(handleFindMultiColor:)],
    [[FBRoute POST:@"/ecnb/cmpColor"].withoutSession respondWithTarget:self action:@selector(handleCmpColor:)],
    [[FBRoute POST:@"/ecnb/getPixelColor"].withoutSession respondWithTarget:self action:@selector(handleGetPixelColor:)],
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

+ (FindColorMatObjc *)sharedColorFinder
{
  static FindColorMatObjc *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[FindColorMatObjc alloc] init];
  });
  return instance;
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleFindColor:(FBRouteRequest *)request
{
  @try {
    NSString *color = request.arguments[@"color"];
    if (nil == color) {
      return FBECErrorWithCode(-1, @"Parameter 'color' is required");
    }

    int x = [request.arguments[@"x"] intValue];
    int y = [request.arguments[@"y"] intValue];
    int w = [request.arguments[@"width"] intValue];
    int h = [request.arguments[@"height"] intValue];
    float threshold = request.arguments[@"threshold"] ? [request.arguments[@"threshold"] floatValue] : 0.9f;
    int limit = request.arguments[@"limit"] ? [request.arguments[@"limit"] intValue] : 1;
    int orz = request.arguments[@"orz"] ? [request.arguments[@"orz"] intValue] : 0;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    FindColorMatObjc *finder = [self sharedColorFinder];
    MatObjc *mat = [finder makeMat:screenshot];
    if (nil == mat) {
      return FBECErrorWithCode(-1, @"Failed to create Mat from screenshot");
    }

    NSString *result = [finder findColor:[mat getNativeAdr] :color :threshold :x :y :w :h :limit :orz];
    [mat close];

    return FBECSuccessWithData(result ?: @"");
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during findColor");
  }
}

+ (id<FBResponsePayload>)handleFindMultiColor:(FBRouteRequest *)request
{
  @try {
    NSString *firstColor = request.arguments[@"firstColor"];
    NSString *offsetColors = request.arguments[@"offsetColors"];
    if (nil == firstColor || nil == offsetColors) {
      return FBECErrorWithCode(-1, @"Parameters 'firstColor' and 'offsetColors' are required");
    }

    int x = [request.arguments[@"x"] intValue];
    int y = [request.arguments[@"y"] intValue];
    int w = [request.arguments[@"width"] intValue];
    int h = [request.arguments[@"height"] intValue];
    float threshold = request.arguments[@"threshold"] ? [request.arguments[@"threshold"] floatValue] : 0.9f;
    int limit = request.arguments[@"limit"] ? [request.arguments[@"limit"] intValue] : 1;
    int orz = request.arguments[@"orz"] ? [request.arguments[@"orz"] intValue] : 0;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    FindColorMatObjc *finder = [self sharedColorFinder];
    MatObjc *mat = [finder makeMat:screenshot];
    if (nil == mat) {
      return FBECErrorWithCode(-1, @"Failed to create Mat from screenshot");
    }

    NSString *result = [finder findMultiColor:[mat getNativeAdr] :firstColor :offsetColors :threshold :x :y :w :h :limit :orz];
    [mat close];

    return FBECSuccessWithData(result ?: @"");
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during findMultiColor");
  }
}

+ (id<FBResponsePayload>)handleCmpColor:(FBRouteRequest *)request
{
  @try {
    NSNumber *xNum = request.arguments[@"x"];
    NSNumber *yNum = request.arguments[@"y"];
    NSString *color = request.arguments[@"color"];
    if (nil == xNum || nil == yNum || nil == color) {
      return FBECErrorWithCode(-1, @"Parameters 'x', 'y', and 'color' are required");
    }

    int x = xNum.intValue;
    int y = yNum.intValue;
    float threshold = request.arguments[@"threshold"] ? [request.arguments[@"threshold"] floatValue] : 0.9f;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    FindColorMatObjc *finder = [self sharedColorFinder];
    MatObjc *mat = [finder makeMat:screenshot];
    if (nil == mat) {
      return FBECErrorWithCode(-1, @"Failed to create Mat from screenshot");
    }

    // cmpColor expects points format: "x,y,color"
    NSString *points = [NSString stringWithFormat:@"%d,%d,%@", x, y, color];
    int result = [finder cmpColor:[mat getNativeAdr] :points :threshold :0 :0 :0 :0];
    [mat close];

    return FBECSuccessWithData(@{@"match": @(result == 1)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during cmpColor");
  }
}

+ (id<FBResponsePayload>)handleGetPixelColor:(FBRouteRequest *)request
{
  @try {
    NSNumber *xNum = request.arguments[@"x"];
    NSNumber *yNum = request.arguments[@"y"];
    if (nil == xNum || nil == yNum) {
      return FBECErrorWithCode(-1, @"Parameters 'x' and 'y' are required");
    }

    int x = xNum.intValue;
    int y = yNum.intValue;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    FindColorMatObjc *finder = [self sharedColorFinder];
    MatObjc *mat = [finder makeMat:screenshot];
    if (nil == mat) {
      return FBECErrorWithCode(-1, @"Failed to create Mat from screenshot");
    }

    NSString *hexColor = [mat getMatColorHex:x :y];
    [mat close];

    return FBECSuccessWithData(@{@"color": hexColor ?: @""});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during getPixelColor");
  }
}

@end
