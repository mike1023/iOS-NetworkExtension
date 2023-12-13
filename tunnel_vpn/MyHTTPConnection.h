#import <Foundation/Foundation.h>
#import "HTTPConnection.h"

@class MyWebSocket;
@class ConnectorWebSocket;

@interface MyHTTPConnection : HTTPConnection

@property (nonatomic, strong) MyWebSocket *ws;
@property (nonatomic, strong) ConnectorWebSocket *connectorWS;

@end
