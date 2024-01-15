#import <Foundation/Foundation.h>
#import "WebSocket.h"
#import "GCDAsyncSocket.h"


@interface MyWebSocket : WebSocket

@property(nonatomic, copy) void (^connectionResponseHandler)(GCDAsyncSocket *socket);
@property(nonatomic, copy) void (^receiveDataHandler)(GCDAsyncSocket *socket);


- (void)sendConnectForSocket:(GCDAsyncSocket *)clientSocket;
- (void)sendPayload:(NSData *)payload forSocket:(GCDAsyncSocket *)socket;


@end
