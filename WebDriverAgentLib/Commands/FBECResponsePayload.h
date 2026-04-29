/**
 * EasyClick EC Response Payload
 * Unified EC response format: {code: int, data: id, msg: NSString}
 */

#import <Foundation/Foundation.h>
#import <WebDriverAgentLib/FBResponsePayload.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Convenience method to create EC format response
 * Response body: {"code": 0, "data": ..., "msg": "success"}
 */
id<FBResponsePayload> FBECResponseWithCode(NSInteger code, id _Nullable data, NSString *msg);

/**
 * Convenience method for success response
 * Response body: {"code": 0, "data": ..., "msg": "success"}
 */
id<FBResponsePayload> FBECSuccessWithData(id _Nullable data);

/**
 * Convenience method for error response
 * Response body: {"code": <code>, "data": null, "msg": <msg>}
 */
id<FBResponsePayload> FBECErrorWithCode(NSInteger code, NSString *msg);

NS_ASSUME_NONNULL_END
