#import <Foundation/Foundation.h>
#import "WebSocket.h"
#import "GCDAsyncSocket.h"


@interface MyWebSocket : WebSocket

@property(nonatomic, copy) void (^connectionResponseHandler)(GCDAsyncSocket *socket);
@property(nonatomic, copy) void (^receiveDataHandler)(GCDAsyncSocket *socket);

- (void)sendData:(NSData *)data withSocket:(GCDAsyncSocket *)socket;

@end
