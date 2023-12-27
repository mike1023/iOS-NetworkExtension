#import <Foundation/Foundation.h>
#import "WebSocket.h"
#import "ConnectorWebSocket.h"
#import "GCDAsyncSocket.h"


@interface MyWebSocket : WebSocket

@property(nonatomic, copy) void (^receiveMessageHandler)(NSString *msg);

- (void)sendConnectForSocket:(GCDAsyncSocket *)clientSocket;


@end
