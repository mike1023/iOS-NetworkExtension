#import "MyWebSocket.h"
#import "SharedSocketsManager.h"
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"




@implementation MyWebSocket



- (void)didOpen
{
	[super didOpen];
    NSLog(@"jsp------didOpen");
}

- (void)didReceiveData:(NSData *)data {
    if (data.length) {
        NSLog(@"jsp----- websocket server receive data length from ws client: %lu", (unsigned long)data.length);
        NSMutableArray * socketClients = [SharedSocketsManager sharedInstance].socketClients;
        GCDAsyncSocket *currentSocket = nil;
        NSInteger len = data.length;
        
        Byte * headerBytes = (Byte *)data.bytes;
        Byte srcPort1 = headerBytes[9];
        Byte srcPort2 = headerBytes[10];
        
        Byte srcport[] = {srcPort1, srcPort2};
        UInt16 portValue;
        memcpy(&portValue, srcport, sizeof(portValue));
        // iOS is little-endian by default
        UInt16 res = htons(portValue);
        if (len > 11) {
            NSData * payload = [data subdataWithRange:NSMakeRange(11, data.length - 11)];
            for (GCDAsyncSocket *socket in socketClients) {
                if (socket.connectedPort == res) {
                    currentSocket = socket;
                    [socket writeData:payload withTimeout:-1 tag:0];
                    break;
                }
            }
            
        } else {
            NSLog(@"jsp---- receive connect response....");
            if (self.connectionResponseHandler) {
                for (GCDAsyncSocket *socket in socketClients) {
                    if (socket.connectedPort == res) {
                        currentSocket = socket;
                        break;
                    }
                }
                self.connectionResponseHandler(currentSocket);
            }
        }
    }
    
}



/*
- (void)didReceiveMessage:(NSString *)msg
{
    NSLog(@"jsp----- websocket server receive msg from ws client 0000000: %@", msg);
    NSString * payload = [msg substringFromIndex:22];

    NSData * response = [self convertHexStrToData:payload];
    NSString * str = [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    NSLog(@"jsp----- websocket server receive msg from ws client 111111: %@", str);

    NSMutableArray * socketClients = [SharedSocketsManager sharedInstance].socketClients;
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
        
        NSString * payload = [msg substringFromIndex:22];
        NSData * data = [self convertHexStrToData:payload];
        NSLog(@"jsp----- send payload to socket: %@", data.description);
//        GCDAsyncSocket * connectSocket = nil;
        for (GCDAsyncSocket *socket in socketClients) {
            if (socket.connectedPort == res) {
                [socket writeData:data withTimeout:-1 tag:0];
                [socket readDataWithTimeout:-1 tag:0];
                break;
            }
        }
//        if (headerBytes[1] == 0x00) { // success
//            
//        } else { // fail, remove socket client
//            GCDAsyncSocket * failedSocket = nil;
//            for (GCDAsyncSocket *socket in socketClients) {
//                if (socket.connectedPort == res) {
//                    failedSocket = socket;
//                    break;
//                }
//            }
//            [[SharedSocketsManager sharedInstance].socketClients removeObject:failedSocket];
//        }
    } else {
        NSLog(@"jsp---- receive connect response....");
        if (self.receiveMessageHandler) {
            self.receiveMessageHandler(msg);
        }
    }
}
 */
 

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

- (void)sendPayload:(NSData *)payload forSocket:(GCDAsyncSocket *)socket {
    uint16_t srcPort = socket.connectedPort;
    Byte srcPort1 = (srcPort >> 8) & 0xff;
    Byte srcPort2 = srcPort & 0xff;
    
    Byte version = 0x01;
    Byte cmd = 0x12;
    Byte ipPro = 0x04;
    
    NSString * remoteIP = [SharedSocketsManager sharedInstance].remoteIP;
    NSArray * ipArr = [remoteIP componentsSeparatedByString:@"."];
    Byte ip1 = (Byte)[ipArr[0] intValue];
    Byte ip2 = (Byte)[ipArr[1] intValue];
    Byte ip3 = (Byte)[ipArr[2] intValue];
    Byte ip4 = (Byte)[ipArr[3] intValue];
    
    //des port
//    Byte desPort1 = 0x1f;
//    Byte desPort2 = 0x90;
    
    Byte desPort1 = 0x13;
    Byte desPort2 = 0x89;
    
    Byte headerBytes[] = {
        version, cmd, ipPro, ip1, ip2, ip3, ip4,
        desPort1, desPort2, srcPort1, srcPort2
    };
    NSMutableData * header = [NSMutableData dataWithBytes:headerBytes length:sizeof(headerBytes)];
    [header appendData:payload];
    [self sendData:header isBinary:YES];
}

// send connect command to server.
- (void)sendConnectForSocket:(GCDAsyncSocket *)clientSocket {
    uint16_t srcPort = clientSocket.connectedPort;
    Byte srcPort1 = (srcPort >> 8) & 0xff;
    Byte srcPort2 = srcPort & 0xff;
    
    Byte version = 0x01;
    Byte cmd = 0x11;
    Byte ipPro = 0x04;
    
    NSString * remoteIP = [SharedSocketsManager sharedInstance].remoteIP;
    NSArray * ipArr = [remoteIP componentsSeparatedByString:@"."];
    Byte ip1 = (Byte)[ipArr[0] intValue];
    Byte ip2 = (Byte)[ipArr[1] intValue];
    Byte ip3 = (Byte)[ipArr[2] intValue];
    Byte ip4 = (Byte)[ipArr[3] intValue];
    
    //des port
//    Byte desPort1 = 0x1f;
//    Byte desPort2 = 0x90;
    
    Byte desPort1 = 0x13;
    Byte desPort2 = 0x89;
    
    Byte connectBytes[] = {
        version, cmd, ipPro, ip1, ip2, ip3, ip4,
        desPort1, desPort2, srcPort1, srcPort2
    };
    NSData * data = [NSData dataWithBytes:connectBytes length:sizeof(connectBytes)];
    
    [self sendData:data isBinary:YES];
}

@end
