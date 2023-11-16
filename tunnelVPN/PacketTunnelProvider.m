//
//  PacketTunnelProvider.m
//  tunnelVPN
//
//  Created by Harris on 2023/5/12.
//

#import "PacketTunnelProvider.h"
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"
#import "Packet.h"

typedef NS_ENUM(UInt8, TransportProtocol) {
    TCP = 6,
    UDP = 17
};

@interface PacketTunnelProvider ()<GCDAsyncSocketDelegate>
@property (nonatomic, copy) void (^completionHandler)(NSError *);
@property (nonatomic, copy) NSString * hostname;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *clientSockets;
@property (nonatomic, assign) BOOL isRunning;

@property (nonatomic, copy) NSString * domainName;
@property (nonatomic, copy) NSArray * domainArr;

@end

@implementation PacketTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler {
    // Add code here to start the process of connecting the tunnel.
    self.domainName = @"www.163.com";
    [self getConfigurationInfo:self.protocolConfiguration];
    self.completionHandler = completionHandler;
    [self setupSocketClient];
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    // Add code here to start the process of stopping the tunnel.
//    [self.udpSession cancel];
    completionHandler();
}

- (void)setupSocketClient {
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create("tunnel.opentxt.queue", queueAttributes);
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    NSError * error = nil;
    [self.socket connectToHost:self.hostname onPort:self.port error:&error];
    if (error) {
        NSLog(@"error, client socket connect failed: %@", error.localizedDescription);
    } else {
        [self setupTunnelNetwork];
    }
}

/*
- (void)setupUDPSession {
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create("tunnel.opentxt.queue", queueAttributes);
    NSString * port = [@(self.port) stringValue];
    NWHostEndpoint * endPoint = [NWHostEndpoint endpointWithHostname:self.hostname port:port];
    self.udpSession = [self createUDPSessionToEndpoint:endPoint fromEndpoint:nil];
    __weak typeof(self) weakSelf = self;
    [self.udpSession setReadHandler:^(NSArray<NSData *> * _Nullable datagrams, NSError * _Nullable error) {
        for (NSData* data in datagrams) {
            NSLog(@"jsp--- tunnel receive data: %@", data);
            [weakSelf.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
        }
    } maxDatagrams:INT_MAX];
    [_udpSession addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"state"]) {
        switch (self.udpSession.state) {
            case NWUDPSessionStateReady:
                NSLog(@"jsp--- NWUDPSessionStateReady");
                [self setupTunnelNetwork];
                break;
            case NWUDPSessionStateFailed:
                NSLog(@"jsp--- udp connect failed...");
                break;
            case NWUDPSessionStatePreparing:
                NSLog(@"jsp--- udp connect Preparing...");
                break;
            default:
                break;
        }
    }
}
 */




- (void)setupTunnelNetwork {
    // configure TUN interface, it can capture IP packets.
    NSString * ip = @"10.10.10.10";
    NSString * subnetMask = @"255.255.255.0";
    NEPacketTunnelNetworkSettings * settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:self.hostname];
    settings.MTU = @1500;
    NEIPv4Settings * ipv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[ip] subnetMasks:@[subnetMask]];
    NEIPv4Route * allowRoute = [[NEIPv4Route alloc] initWithDestinationAddress:@"2.2.2.2" subnetMask:subnetMask];
    
    
    NEIPv4Route * allowRoute2 = [[NEIPv4Route alloc] initWithDestinationAddress:@"8.8.8.8" subnetMask:subnetMask];
    NEIPv4Route * allowRoute4 = [[NEIPv4Route alloc] initWithDestinationAddress:@"8.8.4.4" subnetMask:subnetMask];
    
//    ipv4Settings.includedRoutes = @[allowRoute, allowRoute2, allowRoute3, allowRoute4, allowRoute5];
    ipv4Settings.includedRoutes = @[allowRoute];
//    ipv4Settings.includedRoutes = @[[NEIPv4Route defaultRoute]];
    settings.IPv4Settings = ipv4Settings;
    
    
    //ipv6 setting
//    NSString * ipv6 = @"fd12:1:1:1::2";
//    NEIPv6Settings * ipv6Settings = [[NEIPv6Settings alloc] initWithAddresses:@[ipv6] networkPrefixLengths:@[@128]];
//    //https://www.jianshu.com/p/3db3a97510ab
//    NEIPv6Route * route = [[NEIPv6Route alloc] initWithDestinationAddress:@"::" networkPrefixLength:@1];
//    NEIPv6Route *route1 = [[NEIPv6Route alloc]initWithDestinationAddress:@"8000::" networkPrefixLength:@1];
//    ipv6Settings.includedRoutes = @[route, route1];
//    settings.IPv6Settings = ipv6Settings;
    
    //dns setting 15.122.222.53
    NEDNSSettings * dnsSettings = [[NEDNSSettings alloc] initWithServers:@[@"8.8.8.8", @"8.8.4.4"]];
//    dnsSettings.matchDomains = @[@""];
    dnsSettings.matchDomains = @[@"www.12306.com"];
    dnsSettings.matchDomainsNoSearch = YES;
    settings.DNSSettings = dnsSettings;
    
    __weak typeof(self) weakSelf = self;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"jsp--- error: %@", error.localizedDescription);
            weakSelf.completionHandler(error);
        } else {
            weakSelf.completionHandler(nil);
            [weakSelf readPackets];
        }
    }];
}

- (void)readPackets {
    [self.packetFlow readPacketObjectsWithCompletionHandler:^(NSArray<NEPacket *> * _Nonnull packets) {
        [packets enumerateObjectsUsingBlock:^(NEPacket * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            dispatch_async(self.socketQueue, ^{
                NSLog(@"jsp---- send: %@", obj.data.hexString);
//                [self parsePacket:obj.data];
//                [self.socket writeData:obj.data withTimeout:-1 tag:100];
            });
        }];
        [self readPackets];
    }];
}

/*
 NSArray *array = @[@(0x00), @(0x01), @(0x02), @(0x03), @(0x04)];
 unsigned char *byteArray = malloc(sizeof(unsigned char) * [array count]);

 for (NSUInteger i = 0; i < [array count]; i++) {
     byteArray[i] = [array[i] unsignedCharValue];
 }

 // Now you can use byteArray
 // Don't forget to free the memory when you're done with it:
 free(byteArray);
 */

- (NSArray *)getDomainName:(unsigned char *)byteArr {
    NSMutableString * tempStr = [[NSMutableString alloc] initWithString:@""];
    NSString * domainName = self.domainName;
    NSArray * arr = [domainName componentsSeparatedByString:@"."];
    for (int i = 0; i < arr.count; i++) {
        NSString * s = arr[i];
        NSInteger len = s.length;
        [tempStr appendString:[NSString stringWithFormat:@"%ld%@", (long)len, s]];
    }
    [tempStr appendString:@"0"];
    
    NSInteger tempLen = tempStr.length;
    NSMutableArray * tempArr = [NSMutableArray array];
    int n = 0;
    for (int i = 40; i < tempLen + 40; i++) {
        Byte byte = byteArr[i];
        [tempArr addObject:@(byte)];
        n++;
    }
    self.domainArr = [tempArr copy];
    return self.domainArr;
}

- (BOOL)isPacketForPrivateDomainQuery:(unsigned char *)byteArr {
    NSMutableString * domainStr = [[NSMutableString alloc] initWithString:@""];
    NSMutableString * tempStr = [[NSMutableString alloc] initWithString:@""];
    NSString * domainName = self.domainName;
    NSArray * arr = [domainName componentsSeparatedByString:@"."];
    for (int i = 0; i < arr.count; i++) {
        NSString * s = arr[i];
        NSInteger len = s.length;
        [domainStr appendString:s];
        [tempStr appendString:[NSString stringWithFormat:@"%ld%@", (long)len, s]];
    }
    [tempStr appendString:@"0"];
    
    
    NSInteger len = domainStr.length;
    NSInteger tempLen = tempStr.length;
    char temp[len + 1];
    int n = 0;
    for (int i = 40; i < tempLen + 40; i++) {
        char byte = byteArr[i];
        // In ASCII, printable characters are in the range of 0x20 (32 in decimal) to 0x7E (126 in decimal).
        if (byte >= 0x20 && byte <= 0x7e) {
            temp[n] = byte;
            n++;
        }
    }
    temp[len] = '\0';
    // temp must end with a NULL character, so we need add '\0' at the end
    NSString * finalStr = [[NSString alloc] initWithCString:temp encoding:NSUTF8StringEncoding];
    if (![finalStr isEqualToString:domainStr]) {
        return NO;
    }
    return YES;
}



- (void)generateDNSResponsePacket:(Byte *)byteArr {
    // 4. if the packet is a dns query for private domain name, let's start generate a fake response packet.
    //************************DNS*************************
    // IP header length 20bytes, UDP header 8bytes, so the start index of DNS part is 28.
    // 1. Transaction ID: the same as query packet
    Byte transactionID1 = byteArr[28];
    Byte transactionID2 = byteArr[29];
    // 2. Flags
    Byte flags1 = 0x85;
    Byte flags2 = 0x80;
    // 3. Questions
    Byte questions1 = byteArr[32]; //0x00
    Byte questions2 = byteArr[33]; //0x01
    // 4. Answer RRs: we only return 1 record for a special domain name
    Byte answer1 = 0x00;
    Byte answer2 = 0x01;
    // 5. Authority RRs
    Byte authorityRRs1 = 0x00;
    Byte authorityRRs2 = 0x00;
    // 6. Additional RRs
    Byte additionalRRs1 = 0x00;
    Byte additionalRRs2 = 0x00;
    // 7. queries: domainName: www.private.com
    // domain name
    Byte domaninName[self.domainArr.count];
    for (int i = 0; i < self.domainArr.count; i++) {
        domaninName[i] = [self.domainArr[i] unsignedCharValue];
    }
        
    // type: A
    Byte type1 = 0x00;
    Byte type2 = 0x01;
    
    // class in
    Byte class1 = 0x00;
    Byte class2 = 0x01;
    
    // Answers: we only build one answer record
    // https://cabulous.medium.com/dns-message-how-to-read-query-and-response-message-cfebcb4fe817
    Byte ans1 = 0xc0;
    Byte ans2 = 0x0c;
    
    // Answers type
    Byte ansType1 = 0x00;
    Byte ansType2 = 0x01;
    
    // Answers class in
    Byte ansClass1 = 0x00;
    Byte ansClass2 = 0x01;
    
    // time to live
    Byte ttl1 = 0x00;
    Byte ttl2 = 0x00;
    Byte ttl3 = 0x70;
    Byte ttl4 = 0x80;
    
    // data length
    Byte len1 = 0x00;
    Byte len2 = 0x04;
    
    // address, domain name --> IP 15.120.24.30
    Byte ip1 = 0x0f;
    Byte ip2 = 0x78;
    Byte ip3 = 0x18;
    Byte ip4 = 0x1e;
    
    Byte resDNS1[] = {
        transactionID1, transactionID2, flags1, flags2, questions1, questions2, answer1, answer2, authorityRRs1, authorityRRs2,
        additionalRRs1, additionalRRs2
    };
    
    Byte resDNS2[] = {
        type1, type2, class1, class2, ans1, ans2, ansType1, ansType2, ansClass1, ansClass2, ttl1, ttl2, ttl3, ttl4, len1, len2,
        ip1, ip2, ip3, ip4
    };
    
    size_t n1 = sizeof(resDNS1);
    size_t n2 = sizeof(domaninName);
    size_t n3 = sizeof(resDNS2);
    
    size_t n = n1 + n2 + n3;
    Byte resDNS[n];
    
    for (int i = 0; i < n1; i++) {
        resDNS[i] = resDNS1[i];
    }
    
    for (int i = 0; i < n2; i++) {
        resDNS[n1 + i] = domaninName[i];
    }
    
    for (int i = 0; i < n3; i++) {
        resDNS[n1 + n2 + i] = resDNS2[i];
    }
    
    // for debug: log resDNS
//    for (int i = 0; i < n; i++) {
//        NSLog(@"jsp---dns: %hu", resDNS[i]);
//    }
    
    //***********************UDP*************************
    // source port 53
    Byte sourcePort1 = 0x00;
    Byte sourcePort2 = 0x35;
    
    // destination port
    Byte desPort1 = byteArr[20];
    Byte desPort2 = byteArr[21];
    
    // UDP length: UDP header(8) + DNS length
    Byte dnsLen = 32 + (Byte)self.domainArr.count;
    
    UInt16 resUDPLength = 8 + sizeof(resDNS);
    Byte resudpLen1 = (resUDPLength >> 8) & 0xff; // upper byte
    Byte resudpLen2 = resUDPLength & 0xff; // low byte

    // UDP checksum, now we init them 0x00 at first
    Byte udpChecksum1 = 0x00;
    Byte udpChecksum2 = 0x00;
    
    // calculate response UDP checksum
    // 1. add fake udp header
    // sourceIP(4 bytes), destination IP(4 bytes), 0x00, protocol(UDP 0x11), data length
    Byte fakeUDPHeader[] = {
        byteArr[16], byteArr[17], byteArr[18], byteArr[19],
        byteArr[12], byteArr[13], byteArr[14], byteArr[15],
        0x00, 0x11, resudpLen1, resudpLen2, sourcePort1,
        sourcePort2, desPort1, desPort2, resudpLen1, resudpLen2,
        0x00, 0x00
    };
    
    size_t m = sizeof(fakeUDPHeader);
    Byte resUDPForChecksum[m + n];
    
    for (int i = 0; i < m; i++) {
        resUDPForChecksum[i] = fakeUDPHeader[i];
    }
    
    for (int i = 0; i < n; i++) {
        resUDPForChecksum[m + i] = resDNS[i];
    }
    
    uint16_t udpChecksum = [self calculateChecksum:resUDPForChecksum length:sizeof(resUDPForChecksum)];
    udpChecksum1 = (udpChecksum >> 8) & 0xff; // upper byte
    udpChecksum2 = udpChecksum & 0xff; // low byte
    
    Byte resUDP[] = {
        sourcePort1, sourcePort2, desPort1, desPort2, resudpLen1, resudpLen2, udpChecksum1, udpChecksum2
    };
    
    // for debug, log resUDP
//    for (int i = 0; i < sizeof(resUDP); i++) {
//        NSLog(@"jsp---udp: %hu", resUDP[i]);
//    }

    //*****************************IP*********************************
    // protocol and header length  IPv4 or IPv6 , header length 20
    Byte ipVersionAndHeaderLength = byteArr[0];
    
    // differentiated services field
    Byte dsf = byteArr[1];
    
    // IP packet length: IP header length(20) + UDP length
    UInt16 ipLen = 20 + resUDPLength;
    Byte ipLen1 = (ipLen >> 8) & 0xff; // upper byte
    Byte ipLen2 = ipLen & 0xff; // low byte
    
    //unique identify
    Byte uniqueID1 = byteArr[4];
    Byte uniqueID2 = byteArr[5];
    
    //flag offset
    Byte fragmentOffset1 = byteArr[6];
    Byte fragmentOffset2 = byteArr[7];
    
    // time to live
    Byte IPttl = byteArr[8];
    
    // tcp or udp
    Byte transformProtocol = 0x11; // UDP
    
    // checksum, 仅校验数据报的首部,使用二进制反码求和
    Byte ipChecksum1 = 0x00;
    Byte ipChecksum2 = 0x00;
    
    // source IP
    Byte sourceIP1 = byteArr[16];
    Byte sourceIP2 = byteArr[17];
    Byte sourceIP3 = byteArr[18];
    Byte sourceIP4 = byteArr[19];
    
    // destination IP
    Byte desIP1 = byteArr[12];
    Byte desIP2 = byteArr[13];
    Byte desIP3 = byteArr[14];
    Byte desIP4 = byteArr[15];
    
    // IP Checksum
    Byte resIP[] = {
        ipVersionAndHeaderLength, dsf, ipLen1, ipLen2, uniqueID1, uniqueID2, fragmentOffset1, fragmentOffset2, IPttl, transformProtocol, ipChecksum1,
        ipChecksum2, sourceIP1, sourceIP2, sourceIP3, sourceIP4, desIP1, desIP2, desIP3, desIP4
    };
    UInt16 ipCheckSum = [self calculateChecksum:resIP length:sizeof(resIP)];
    ipChecksum2 = ipCheckSum & 0xff;
    ipChecksum1 = (ipCheckSum >> 8) & 0xff;
    
    // replace checksum bytes in responseIP
    resIP[10] = ipChecksum1;
    resIP[11] = ipChecksum2;
    
    // IP + UDP + DNS
    size_t x = sizeof(resIP);
    size_t y = sizeof(resUDP);
    size_t z = sizeof(resDNS);
    
    size_t resN = x + y + z;
    Byte resPacket[resN];
    
    for (int i = 0; i < x; i++) {
        resPacket[i] = resIP[i];
    }
    for (int i = 0; i < y; i++) {
        resPacket[x + i] = resUDP[i];
    }
    for (int i = 0; i < z; i++) {
        resPacket[x + y + i] = resDNS[i];
    }
    
    NSData * data = [NSData dataWithBytes:resPacket length:sizeof(resPacket)];
    NSLog(@"jsp--- fake dns: %@", data.hexString);
    [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
}

- (void)parsePacket:(NSData *)packet {
    Byte *byteArr = (Byte *)packet.bytes;
    // 1. is it a UDP
    TransportProtocol transProtocol = byteArr[9];
    NSLog(@"jsp---- %d", transProtocol);
    if (transProtocol != UDP) {
        return;
    }
    
    // 2. destination port: generally, 53 is for DNS query
    Byte desport[] = {byteArr[22], byteArr[23]};
    UInt16 portValue;
    memcpy(&portValue, desport, sizeof(portValue));
    // iOS is little-endian by default
    UInt32 res = htons(portValue);
    if (res != 53) {
        return;
    }
    
    [self getDomainName:byteArr];
    // 3. get the target DNS query www.private.com
    if (![self isPacketForPrivateDomainQuery:byteArr]) {
        return;
    }
    [self generateDNSResponsePacket:byteArr];
}



- (uint16_t)calculateChecksum:(unsigned char *)header length:(size_t)length {
    uint32_t sum = 0;
    
    // Sum header data by 16-bit words
    for (int i = 0; i < length; i += 2) {
        uint16_t word = (header[i] << 8) + header[i + 1];
        sum += word;
        
        // Add carry over to sum if any
        if (sum > 0xFFFF) {
            sum = (sum & 0xFFFF) + 1;
        }
    }
    // Return one's complement of the checksum
    return ~((uint16_t) sum);
}




//- (void)sendUDPPacket:(IPPacket *)packet {
//    NSString * udpKey = [NSString stringWithFormat:@"%@:%d->%@:%d", packet.header.sourceAddress, packet.sourcePort, packet.header.destinationAddress, packet.destinationPort];
//
//    NSString * desPort = [NSString stringWithFormat:@"%d", packet.destinationPort];
//    NSString * sourcePort = [NSString stringWithFormat:@"%d", packet.sourcePort];
//    NSLog(@"source:%@:%@, des: %@:%@", packet.header.sourceAddress, sourcePort, packet.header.destinationAddress, desPort);
//
//    NWUDPSession * udpSession = self.udpSessionDict[udpKey];
//    if (udpSession) {
//        if (udpSession.state == NWUDPSessionStateReady) {
//            [udpSession writeDatagram:packet.payload completionHandler:^(NSError * _Nullable error) {
//                if (error) {
//                    NSLog(@"jsp----%@", [error localizedDescription]);
//                } else {
//
//                }
//            }];
//            [udpSession setReadHandler:^(NSArray<NSData *> * _Nullable datagrams, NSError * _Nullable error) {
//                for (NSData* data in datagrams) {
//                    NSLog(@"recv udp: %@", data);
//                }
//            } maxDatagrams:1500];
//        } else {
//            NSLog(@"=================");
//        }
//    } else {
//        NWUDPSession * session = [self createUDPSessionToEndpoint:[NWHostEndpoint endpointWithHostname:packet.header.destinationAddress port:desPort] fromEndpoint:[NWHostEndpoint endpointWithHostname:packet.header.sourceAddress port:sourcePort]];
//        self.tempUDPPacket = packet.payload;
//        [session addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:nil];
//        NSLog(@"=================");
//
//        [self.udpSessionDict setValue:session forKey:udpKey];
//    }
//}

//- (void)sendTCPPacket:(IPPacket *)packet {
//
//}

//- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
//    NWUDPSession * session = object;
//    NSLog(@"xxxxxxxxxx session:%@", session);
//    if ([keyPath isEqualToString:@"state"]) {
//        switch (session.state) {
//            case NWUDPSessionStatePreparing:
//                NSLog(@"111111udp Preparing");
//                break;
//            case NWUDPSessionStateReady:
//                NSLog(@"1111111udp ready");
//                // start send
//                [session writeDatagram:self.tempUDPPacket completionHandler:^(NSError * _Nullable error) {
//                    if (error) {
//                        NSLog(@"jsp----%@", [error localizedDescription]);
//                    } else {
//
//                    }
//                }];
//                break;
//            case NWUDPSessionStateWaiting:
//                NSLog(@"111111udp waiting...");
//                break;
//            case NWUDPSessionStateInvalid:
//                NSLog(@"111111udp invalid...");
//                break;
//            case NWUDPSessionStateFailed:
//                NSLog(@"111111udp failed...");
//                break;
//            case NWUDPSessionStateCancelled:
//                NSLog(@"111111udp cancelled");
//                [session removeObserver:session forKeyPath:@"state"];
//                break;
//            default:
//                break;
//        }
//    }
//}



- (void)getConfigurationInfo:(NEVPNProtocol *)configuration {
    NETunnelProviderProtocol * providerProtocol = (NETunnelProviderProtocol *)configuration;
    NSString * fullAddress = providerProtocol.serverAddress;
    NSArray * addressArr = [fullAddress componentsSeparatedByString:@":"];
    self.hostname = addressArr[0];
    self.port = [addressArr[1] intValue];
}


- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"jsp---- socket connect success...");
    [sock readDataWithTimeout:-1 tag:100];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {

}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
//    NSMutableArray * arr = [self getCorrectPacket:data];
//    for (NSData *obj in arr) {
//        NSLog(@"receive data from device server: %@", [obj hexString]);
//        [self.packetFlow writePackets:@[obj] withProtocols:@[@AF_INET]];
//    }
    NSLog(@"jsp---- recv: %@", data);

    [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];

    // call this to continue read data from server.
    [sock readDataWithTimeout:-1 tag:100];
}

- (NSMutableArray *)getCorrectPacket:(NSData *)data {
    NSInteger totalLength = data.length;
    if (totalLength == 0) {
        return nil;
    }

    NSInteger offset = 0;
    NSMutableArray * arr = [NSMutableArray array];
    while (offset < totalLength) {
        NSData * temp = [data subdataWithRange:NSMakeRange(2 + offset, 2)];
        unsigned result = 0;
        NSScanner *scanner = [NSScanner scannerWithString:[temp hexString]];
        [scanner scanHexInt:&result];
        NSData * ele = [data subdataWithRange:NSMakeRange(offset, result)];
        [arr addObject:ele];
        offset += result;
    }
    return arr;
}


- (void)handleAppMessage:(NSData *)messageData completionHandler:(void (^)(NSData *))completionHandler {
    // Add code here to handle the message.
}

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler {
    // Add code here to get ready to sleep.
    completionHandler();
}

- (void)wake {
    // Add code here to wake up.
}

@end
