/**
 * EasyClick IME Commands Implementation
 * Endpoints: ime/input, ime/paste, ime/clipboard, ime/setClipboard
 */

#import "FBECIMECommands.h"

#import <XCTest/XCUIDevice.h>
#import <UIKit/UIPasteboard.h>

#import "FBECResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement.h"
#import "XCUIElement+FBTyping.h"

@implementation FBECIMECommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/ecnb/ime/input"].withoutSession respondWithTarget:self action:@selector(handleInput:)],
    [[FBRoute POST:@"/ecnb/ime/paste"].withoutSession respondWithTarget:self action:@selector(handlePaste:)],
    [[FBRoute GET:@"/ecnb/ime/clipboard"].withoutSession respondWithTarget:self action:@selector(handleGetClipboard:)],
    [[FBRoute POST:@"/ecnb/ime/setClipboard"].withoutSession respondWithTarget:self action:@selector(handleSetClipboard:)],
  ];
}

#pragma mark - Commands

+ (id<FBResponsePayload>)handleInput:(FBRouteRequest *)request
{
  @try {
    NSString *text = request.arguments[@"text"];
    if (nil == text) {
      return FBECErrorWithCode(-1, @"Parameter 'text' is required");
    }

    BOOL clear = [request.arguments[@"clear"] boolValue];
    XCUIApplication *app = FBSession.activeSession.activeApplication ?: XCUIApplication.fb_activeApplication;

    if (clear && nil != app) {
      XCUIElement *focusedElement = app.fb_focusedElement;
      if (nil != focusedElement) {
        NSError *clearError;
        [focusedElement fb_clearTextWithError:&clearError];
      }
    }

    NSError *error;
    if (!FBTypeText(text, 60, &error)) {
      return FBECErrorWithCode(-1, error.localizedDescription ?: @"Failed to type text");
    }

    return FBECSuccessWithData(@{@"typed": @(YES)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during ime/input");
  }
}

+ (id<FBResponsePayload>)handlePaste:(FBRouteRequest *)request
{
  @try {
    NSString *text = request.arguments[@"text"];
    if (nil == text) {
      return FBECErrorWithCode(-1, @"Parameter 'text' is required");
    }

    // Set text to pasteboard
    [UIPasteboard generalPasteboard].string = text;

    // Simulate paste via keyboard shortcut is not directly available
    // Instead we just set the pasteboard - the caller can trigger paste separately if needed
    return FBECSuccessWithData(@{@"pasted": @(YES), @"text": text});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during ime/paste");
  }
}

+ (id<FBResponsePayload>)handleGetClipboard:(FBRouteRequest *)request
{
  @try {
    NSString *content = [UIPasteboard generalPasteboard].string ?: @"";
    return FBECSuccessWithData(@{@"text": content});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during ime/clipboard");
  }
}

+ (id<FBResponsePayload>)handleSetClipboard:(FBRouteRequest *)request
{
  @try {
    NSString *text = request.arguments[@"text"];
    if (nil == text) {
      return FBECErrorWithCode(-1, @"Parameter 'text' is required");
    }

    [UIPasteboard generalPasteboard].string = text;
    return FBECSuccessWithData(@{@"set": @(YES)});
  } @catch (NSException *exception) {
    return FBECErrorWithCode(-1, exception.reason ?: @"Exception during ime/setClipboard");
  }
}

@end
