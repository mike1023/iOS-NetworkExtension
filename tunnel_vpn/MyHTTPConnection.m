#import "MyHTTPConnection.h"
#import "HTTPMessage.h"
#import "HTTPResponse.h"
#import "HTTPDynamicFileResponse.h"
#import "GCDAsyncSocket.h"
#import "MyWebSocket.h"
#import "HTTPLogging.h"
#import "ConnectorWebSocket.h"
#import "HTTPDataResponse.h"
#import "SharedSocketsManager.h"

// Log levels: off, error, warn, info, verbose
// Other flags: trace
static const int httpLogLevel = HTTP_LOG_LEVEL_WARN; // | HTTP_LOG_FLAG_TRACE;


@implementation MyHTTPConnection

- (NSObject<HTTPResponse> *)httpResponseForMethod:(NSString *)method URI:(NSString *)path
{
	HTTPLogTrace();
//    NSLog(@"jsp----- %@", request);
    if([method isEqualToString:@"POST"] && [path isEqualToString:@"/test"]) {
        return [[HTTPDataResponse alloc] initWithData:[@"123" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    if ([method isEqualToString:@"GET"]) {
        return [[HTTPDataResponse alloc] initWithData:[@"456" dataUsingEncoding:NSUTF8StringEncoding]];
    }
	
	return [super httpResponseForMethod:method URI:path];
}

- (WebSocket *)webSocketForURI:(NSString *)path
{
	HTTPLogTrace2(@"%@[%p]: webSocketForURI: %@", THIS_FILE, self, path);
	
	if ([path isEqualToString:@"/vpn"]) {
        self.ws = [[MyWebSocket alloc] initWithRequest:request socket:asyncSocket];
        [SharedSocketsManager sharedInstance].myws = self.ws;
        return self.ws;
    } else if ([path isEqualToString:@"/connector"]) {
//        self.connectorWS = [[ConnectorWebSocket alloc] initWithRequest:request socket:asyncSocket];
//        [SharedSocketsManager sharedInstance].cws = self.connectorWS;
//        return self.connectorWS;
    }
	return [super webSocketForURI:path];
}

- (BOOL)supportsMethod:(NSString *)method atPath:(NSString *)path
{
    HTTPLogTrace();
    if ([method isEqualToString:@"POST"])
        return YES;
    else
        return [super supportsMethod:method atPath:path];
    
}

@end
