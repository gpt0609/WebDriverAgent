/**
 * EasyClick Device Extended Commands Implementation
 * Endpoints: ioHIDEvent, assistiveTouch, activeAppInfo, homeScreen
 */

#import "FBECDeviceCommands.h"

#import <XCTest/XCUIDevice.h>

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"

@implementation FBECDeviceCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/ioHIDEvent"].withoutSession respondWithTarget:self action:@selector(handleIOHIDEvent:)],
    [[FBRoute POST:@"/ecnb/assistiveTouch"].withoutSession respondWithTarget:self action:@selector(handleAssistiveTouch:)],
    [[FBRoute GET:@"/ecnb/activeAppInfo"].withoutSession respondWithTarget:self action:@selector(handleActiveAppInfo:)],
    [[FBRoute POST:@"/ecnb/homeScreen"].withoutSession respondWithTarget:self action:@selector(handleHomeScreen:)],
  ];
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleIOHIDEvent:(FBRouteRequest *)request
{
  @try {
    NSNumber *pageID = request.arguments[@"eventPageID"];
    NSNumber *usageID = request.arguments[@"eventUsageID"];
    if (nil == pageID || nil == usageID) {
      return FBECErrorWithCode(-1, @"Parameters 'eventPageID' and 'eventUsageID' are required");
    }

    NSNumber *duration = request.arguments[@"duration"] ?: @(0.1);

    NSError *error;
    if (![XCUIDevice.sharedDevice fb_performIOHIDEventWithPage:pageID.unsignedIntValue
                                                         usage:usageID.unsignedIntValue
                                                      duration:duration.doubleValue
                                                         error:&error]) {
      return FBECErrorWithCode(-1, error.description ?: @"Failed to perform IO-HID event");
    }
    return FBECSuccessWithData(@{@"performed": @(YES)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during ioHIDEvent");
  }
}

+ (id<FBResponsePayload>)handleAssistiveTouch:(FBRouteRequest *)request
{
  @try {
    NSNumber *enabled = request.arguments[@"enabled"];
    if (nil == enabled) {
      return FBECErrorWithCode(-1, @"Parameter 'enabled' is required");
    }

    // AssistiveTouch uses Accessibility setting via private API
    // Use AXSettings from PrivateHeaders
    Class axSettingsClass = NSClassFromString(@"AXSettings");
    if (nil != axSettingsClass) {
      SEL sharedSel = NSSelectorFromString(@"sharedInstance");
      if ([axSettingsClass respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id sharedInstance = [axSettingsClass performSelector:sharedSel];
        SEL setSel = NSSelectorFromString(@"setAssistiveTouchEnabled:");
        if ([sharedInstance respondsToSelector:setSel]) {
          NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                                      [[sharedInstance class] instanceMethodSignatureForSelector:setSel]];
          [invocation setSelector:setSel];
          [invocation setTarget:sharedInstance];
          BOOL val = enabled.boolValue;
          [invocation setArgument:&val atIndex:2];
          [invocation invoke];
          return FBECSuccessWithData(@{@"assistiveTouch": enabled});
        }
#pragma clang diagnostic pop
      }
    }

    return FBECErrorWithCode(-2, @"AssistiveTouch API not available on this device");
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during assistiveTouch");
  }
}

+ (id<FBResponsePayload>)handleActiveAppInfo:(FBRouteRequest *)request
{
  @try {
    XCUIApplication *app = FBSession.activeSession.activeApplication ?: XCUIApplication.fb_activeApplication;
    if (nil == app) {
      return FBECErrorWithCode(-1, @"No active application found");
    }

    NSDictionary *info = @{
      @"pid": @(app.processID),
      @"bundleId": app.bundleID ?: @"",
      @"name": app.identifier ?: @"",
    };
    return FBECSuccessWithData(info);
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during activeAppInfo");
  }
}

+ (id<FBResponsePayload>)handleHomeScreen:(FBRouteRequest *)request
{
  @try {
    NSError *error;
    if (![[XCUIDevice sharedDevice] fb_goToHomescreenWithError:&error]) {
      return FBECErrorWithCode(-1, error.description ?: @"Failed to go to home screen");
    }
    return FBECSuccessWithData(@{@"homeScreen": @(YES)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during homeScreen");
  }
}

@end
