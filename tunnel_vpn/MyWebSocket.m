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

- (void)didClose
{
    [super didClose];
    NSLog(@"jsp------didClose");
}

// [version, cmd(0x00, 0x01), type, domain_len, (domain), desPort1, desPort2, srcPort1, srcPort2]
- (void)didReceiveData:(NSData *)data {
    if (data.length) {
        NSLog(@"jsp----- websocket server receive data length from ws client: %lu", (unsigned long)data.length);
        NSMutableArray * socketClients = [SharedSocketsManager sharedInstance].socketClients;
        GCDAsyncSocket *currentSocket = nil;
        NSInteger totalLen = data.length;
        
        Byte * headerBytes = (Byte *)data.bytes;
        // get domain name len
        Byte domainLen = headerBytes[3];
        
        Byte srcPort1 = headerBytes[domainLen + 5];
        Byte srcPort2 = headerBytes[domainLen + 6];
        
        Byte srcport[] = {srcPort1, srcPort2};
        UInt16 portValue;
        memcpy(&portValue, srcport, sizeof(portValue));
        // iOS is little-endian by default
        UInt16 res = htons(portValue);
        
        NSUInteger headerLen = 4 + domainLen + 4;
        
        if (totalLen > headerLen) {
            NSData * payload = [data subdataWithRange:NSMakeRange(headerLen + 1, totalLen - headerLen)];
            for (GCDAsyncSocket *socket in socketClients) {
                if (socket.connectedPort == res) {
                    currentSocket = socket;
                    [socket writeData:payload withTimeout:-1 tag:0];
                    break;
                }
            }
            if (self.receiveDataHandler) {
                self.receiveDataHandler(currentSocket);
            }
        } else {
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

- (UInt16)getDesPort:(UInt16)srcPort {
    NSMutableDictionary * portMap = [SharedSocketsManager sharedInstance].portMap;
    UInt16 desport = [[portMap valueForKey:[NSString stringWithFormat:@"%d", srcPort]] intValue];
    return desport;
}
- (NSData *)getDomainDataFromSocket:(GCDAsyncSocket *)socket {
    NSString * clientRemoteIP = socket.connectedHost;
    NSString * domain = [[SharedSocketsManager sharedInstance].domainIPMap allKeysForObject:clientRemoteIP].firstObject;
    NSData * domainData = [domain dataUsingEncoding:NSUTF8StringEncoding];
    return domainData;
}


// header: [version, cmd, ipPro, domain, desPort1, desPort2, srcPort1, srcPort2]
- (void)sendData:(NSData *)data withSocket:(GCDAsyncSocket *)socket {
    Byte version = 0x01;
    Byte cmd = 0x12;
    Byte domainType = 0x03;
    

    //get client remote hostname.
    NSData * domainData = [self getDomainDataFromSocket:socket];
    Byte domain_len = domainData.length;
    
    Byte headerByte[] = {version, cmd, domainType, domain_len};
    NSData *headerData = [NSData dataWithBytes:headerByte length:sizeof(headerByte)];
    
    uint16_t srcPort = socket.connectedPort;
    Byte srcPort1 = (srcPort >> 8) & 0xff;
    Byte srcPort2 = srcPort & 0xff;
    //des port
    UInt16 desport = [self getDesPort:srcPort];
    Byte desPort1 = (desport >> 8) & 0xff;
    Byte desPort2 = desport & 0xff;
    
    Byte portBytes[] = {desPort1, desPort2, srcPort1, srcPort2};
    NSData *portData = [NSData dataWithBytes:portBytes length:sizeof(portBytes)];

    NSMutableData *toConnectorData = [NSMutableData data];
    [toConnectorData appendData:headerData];
    [toConnectorData appendData:domainData];
    [toConnectorData appendData:portData];
    
    if (data) {
        [toConnectorData appendData:data];
    }
    [self sendData:toConnectorData isBinary:YES];
}

@end
