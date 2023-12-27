#import "MyWebSocket.h"
#import "SharedSocketsManager.h"
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"




@implementation MyWebSocket



- (void)didOpen
{
	
	[super didOpen];
    NSLog(@"jsp------didOpen");
//	[self sendMessage:@"Welcome to my WebSocket"];
}



- (void)didReceiveMessage:(NSString *)msg
{
    NSLog(@"jsp----- websocket server receive msg from ws client: %@", msg);
    NSMutableArray * socketClients = [SharedSocketsManager sharedInstance].socketClients;
//    if (self.receiveMessageHandler) {
//        self.receiveMessageHandler(msg);
//    }
    NSInteger len = msg.length;
    // fix header length = 22
    if (len > 22) {
        NSString * header = [msg substringToIndex:22];
        NSData * headerData = [self convertHexStrToData:header];
        Byte * headerBytes = (Byte *)headerData.bytes;
        Byte srcPort1 = headerBytes[9];
        Byte srcPort2 = headerBytes[10];
        
        Byte srcport[] = {srcPort1, srcPort2};
        UInt16 portValue;
        memcpy(&portValue, srcport, sizeof(portValue));
        // iOS is little-endian by default
        UInt16 res = htons(portValue);
        
        if (headerBytes[1] == 0x00) { // success
            NSString * payload = [msg substringFromIndex:22];
            GCDAsyncSocket * connectSocket = nil;
            for (GCDAsyncSocket *socket in socketClients) {
                if (socket.connectedPort == res) {
                    [socket writeData:[payload dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
                    break;
                }
            }
        } else { // fail, remove socket client
            GCDAsyncSocket * failedSocket = nil;
            for (GCDAsyncSocket *socket in socketClients) {
                if (socket.connectedPort == res) {
                    failedSocket = socket;
                    break;
                }
            }
            [[SharedSocketsManager sharedInstance].socketClients removeObject:failedSocket];
        }
    }
}

- (NSData *)convertHexStrToData:(NSString *)str
{
    if (!str || [str length] == 0) {
        return nil;
    }
    
    NSMutableData *hexData = [[NSMutableData alloc] initWithCapacity:20];
    NSRange range;
    if ([str length] % 2 == 0) {
        range = NSMakeRange(0, 2);
    } else {
        range = NSMakeRange(0, 1);
    }
    for (NSInteger i = range.location; i < [str length]; i += 2) {
        unsigned int anInt;
        NSString *hexCharStr = [str substringWithRange:range];
        NSScanner *scanner = [[NSScanner alloc] initWithString:hexCharStr];
        
        [scanner scanHexInt:&anInt];
        NSData *entity = [[NSData alloc] initWithBytes:&anInt length:1];
        [hexData appendData:entity];
        
        range.location += range.length;
        range.length = 2;
    }
    return hexData;
}

- (void)didClose
{	
	[super didClose];
}


// send connect command to server.
- (void)sendConnectForSocket:(GCDAsyncSocket *)clientSocket {
    uint16_t srcPort = clientSocket.connectedPort;
    Byte srcPort1 = (srcPort >> 8) & 0xff;
    Byte srcPort2 = srcPort & 0xff;
    

    
    Byte version = 0x01;
    Byte cmd = 0x11;
    Byte ipPro = 0x04;
    
    //10.168.80.187
    Byte ip1 = 0x0a;
    Byte ip2 = 0xa8;
    Byte ip3 = 0x50;
    Byte ip4 = 0xbb;
    

    //des port
    Byte desPort1 = 0x00;
    Byte desPort2 = 0x50;
    
    Byte connectBytes[] = {
        version, cmd, ipPro, ip1, ip2, ip3, ip4,
        desPort1, desPort2, srcPort1, srcPort2
    };
    NSData * data = [NSData dataWithBytes:connectBytes length:sizeof(connectBytes)];

    [self sendMessage:data.hexString];
}

@end
