/**
 * EasyClick EC Response Payload Implementation
 */

#import "FBECResponsePayload.h"
#import "FBResponseJSONPayload.h"
#import "FBHTTPStatusCodes.h"

id<FBResponsePayload> FBECResponseWithCode(NSInteger code, id data, NSString *msg)
{
  NSDictionary *response = @{
    @"code": @(code),
    @"data": data ?: [NSNull null],
    @"msg": msg ?: @""
  };
  HTTPStatusCode httpStatus = (code == 0) ? HTTPStatusCode_OK : HTTPStatusCode_OK;
  return [[FBResponseJSONPayload alloc] initWithDictionary:response
                                            httpStatusCode:httpStatus];
}

id<FBResponsePayload> FBECSuccessWithData(id data)
{
  return FBECResponseWithCode(0, data, @"success");
}

id<FBResponsePayload> FBECErrorWithCode(NSInteger code, NSString *msg)
{
  return FBECResponseWithCode(code, nil, msg);
}
