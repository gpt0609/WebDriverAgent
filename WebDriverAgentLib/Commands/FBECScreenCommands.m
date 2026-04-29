/**
 * EasyClick Screen Commands Implementation
 * Endpoints: captureScreen, captureScreenRegion, screenInfo
 */

#import "FBECScreenCommands.h"

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBScreen.h"
#import "FBMathUtils.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement.h"
#import "XCUIElement+FBWebDriverAttributes.h"

@implementation FBECScreenCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/ecnb/captureScreen"].withoutSession respondWithTarget:self action:@selector(handleCaptureScreen:)],
    [[FBRoute POST:@"/ecnb/captureScreenRegion"].withoutSession respondWithTarget:self action:@selector(handleCaptureScreenRegion:)],
    [[FBRoute GET:@"/ecnb/screenInfo"].withoutSession respondWithTarget:self action:@selector(handleScreenInfo:)],
  ];
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleCaptureScreen:(FBRouteRequest *)request
{
  @try {
    NSError *error;
    NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotWithError:&error];
    if (nil == screenshotData) {
      return FBECErrorWithCode(-1, error.description ?: @"Failed to capture screenshot");
    }
    NSString *base64 = [screenshotData base64EncodedStringWithOptions:0];
    return FBECSuccessWithData(base64);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during screenshot");
  }
}

+ (id<FBResponsePayload>)handleCaptureScreenRegion:(FBRouteRequest *)request
{
  @try {
    NSError *error;
    NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotWithError:&error];
    if (nil == screenshotData) {
      return FBECErrorWithCode(-1, error.description ?: @"Failed to capture screenshot");
    }

    CGFloat x = [request.arguments[@"x"] doubleValue];
    CGFloat y = [request.arguments[@"y"] doubleValue];
    CGFloat width = [request.arguments[@"width"] doubleValue];
    CGFloat height = [request.arguments[@"height"] doubleValue];

    UIImage *fullImage = [UIImage imageWithData:screenshotData];
    if (nil == fullImage) {
      return FBECErrorWithCode(-1, @"Failed to create image from screenshot data");
    }

    CGFloat scale = fullImage.scale;
    CGRect cropRect = CGRectMake(x * scale, y * scale, width * scale, height * scale);

    // Clamp to image bounds
    CGRect imageRect = CGRectMake(0, 0, fullImage.size.width * scale, fullImage.size.height * scale);
    cropRect = CGRectIntersection(cropRect, imageRect);
    if (CGRectIsEmpty(cropRect)) {
      return FBECErrorWithCode(-2, @"Crop region is out of bounds or empty");
    }

    CGImageRef croppedRef = CGImageCreateWithImageInRect(fullImage.CGImage, cropRect);
    if (NULL == croppedRef) {
      return FBECErrorWithCode(-1, @"Failed to crop image");
    }

    UIImage *croppedImage = [UIImage imageWithCGImage:croppedRef scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(croppedRef);

    NSData *pngData = UIImagePNGRepresentation(croppedImage);
    if (nil == pngData) {
      return FBECErrorWithCode(-1, @"Failed to encode cropped image to PNG");
    }

    NSString *base64 = [pngData base64EncodedStringWithOptions:0];
    return FBECSuccessWithData(base64);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during region screenshot");
  }
}

+ (id<FBResponsePayload>)handleScreenInfo:(FBRouteRequest *)request
{
  @try {
    XCUIApplication *app = XCUIApplication.fb_systemApplication;

    XCUIElement *mainStatusBar = app.statusBars.allElementsBoundByIndex.firstObject;
    CGSize statusBarSize = (nil == mainStatusBar) ? CGSizeZero : mainStatusBar.frame.size;

#if TARGET_OS_TV
    CGSize screenSize = app.frame.size;
#else
    CGSize screenSize = FBAdjustDimensionsForApplication(app.wdFrame.size, app.interfaceOrientation);
#endif

    CGFloat scale = [FBScreen scale];

    NSDictionary *info = @{
      @"screenWidth": @(screenSize.width),
      @"screenHeight": @(screenSize.height),
      @"statusBarWidth": @(statusBarSize.width),
      @"statusBarHeight": @(statusBarSize.height),
      @"scale": @(scale),
    };
    return FBECSuccessWithData(info);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception getting screen info");
  }
}

@end
