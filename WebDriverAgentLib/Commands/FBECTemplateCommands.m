/**
 * EasyClick Template Matching Commands Implementation
 * Endpoints: matchTemplate, findImage
 */

#import "FBECTemplateCommands.h"

#import <iosauto/MatchTmplObjc.h>

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIDevice+FBHelpers.h"

@implementation FBECTemplateCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/matchTemplate"].withoutSession respondWithTarget:self action:@selector(handleMatchTemplate:)],
    [[FBRoute POST:@"/ecnb/findImage"].withoutSession respondWithTarget:self action:@selector(handleFindImage:)],
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

+ (UIImage *)imageFromBase64:(NSString *)base64
{
  NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
  if (nil == data) return nil;
  return [UIImage imageWithData:data];
}

+ (NSArray *)convertMatchResults:(NSMutableArray *)results
{
  NSMutableArray *arr = [NSMutableArray array];
  for (ImageRect *r in results) {
    [arr addObject:@{
      @"x": @([r getX]),
      @"y": @([r getY]),
      @"width": @([r getWidth]),
      @"height": @([r getHeight]),
      @"similarity": @([r getSimilarity]),
    }];
  }
  return arr;
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleMatchTemplate:(FBRouteRequest *)request
{
  @try {
    NSString *templateBase64 = request.arguments[@"templateBase64"];
    if (nil == templateBase64) {
      return FBECErrorWithCode(-1, @"Parameter 'templateBase64' is required");
    }

    int matchMethod = request.arguments[@"matchMethod"] ? [request.arguments[@"matchMethod"] intValue] : 0;
    float weakThreshold = request.arguments[@"weakThreshold"] ? [request.arguments[@"weakThreshold"] floatValue] : 0.7f;
    float strictThreshold = request.arguments[@"strictThreshold"] ? [request.arguments[@"strictThreshold"] floatValue] : 0.9f;
    int maxLevel = request.arguments[@"maxLevel"] ? [request.arguments[@"maxLevel"] intValue] : 3;
    int limit = request.arguments[@"limit"] ? [request.arguments[@"limit"] intValue] : 5;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    UIImage *templateImage = [self imageFromBase64:templateBase64];
    if (nil == templateImage) {
      return FBECErrorWithCode(-2, @"Failed to decode template image from base64");
    }

    MatchTmplObjc *matcher = [[MatchTmplObjc alloc] init];
    NSMutableArray *results = [matcher matchTemplate:screenshot :templateImage :matchMethod :weakThreshold :strictThreshold :maxLevel :limit];

    return FBECSuccessWithData([self convertMatchResults:results]);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during matchTemplate");
  }
}

+ (id<FBResponsePayload>)handleFindImage:(FBRouteRequest *)request
{
  @try {
    NSString *templateBase64 = request.arguments[@"templateBase64"];
    if (nil == templateBase64) {
      return FBECErrorWithCode(-1, @"Parameter 'templateBase64' is required");
    }

    float threshold = request.arguments[@"threshold"] ? [request.arguments[@"threshold"] floatValue] : 0.9f;

    UIImage *screenshot = [self takeScreenshot];
    if (nil == screenshot) {
      return FBECErrorWithCode(-1, @"Failed to capture screenshot");
    }

    UIImage *templateImage = [self imageFromBase64:templateBase64];
    if (nil == templateImage) {
      return FBECErrorWithCode(-2, @"Failed to decode template image from base64");
    }

    // Use matchTemplate with simplified parameters: matchMethod=0, maxLevel=3, limit=1
    MatchTmplObjc *matcher = [[MatchTmplObjc alloc] init];
    NSMutableArray *results = [matcher matchTemplate:screenshot :templateImage :0 :threshold :threshold :3 :1];

    if (nil == results || results.count == 0) {
      return FBECSuccessWithData([NSNull null]);
    }

    return FBECSuccessWithData([self convertMatchResults:results]);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during findImage");
  }
}

@end
