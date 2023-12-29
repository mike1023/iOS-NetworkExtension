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
#import "SRWebSocket.h"

typedef NS_ENUM(UInt8, TransportProtocol) {
    TCP = 6,
    UDP = 17
};

@interface PacketTunnelProvider ()<GCDAsyncSocketDelegate, hpSRWebSocketDelegate>
@property (nonatomic, copy) void (^completionHandler)(NSError *);

@property (nonatomic, copy) NSString * domainName;
@property (nonatomic, copy) NSString * routeIP;
@property (nonatomic, copy) NSArray * domainArr;
@property (nonatomic, strong) hpSRWebSocket * myWebSocket;

@property (nonatomic, copy) NSString * hostname;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *clientSockets;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) NWTCPConnection * conn;
@property (nonatomic, strong) NSMutableDictionary * connectionMap;
@end

@implementation PacketTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler {
    // Add code here to start the process of connecting the tunnel.
//    [self getConfigurationInfo:self.protocolConfiguration];
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create("com.opentext.tunnel_vpn", queueAttributes);
    self.domainName = options[@"name"];
    self.routeIP = options[@"ip"];
    self.connectionMap = [NSMutableDictionary dictionary];
    self.completionHandler = completionHandler;
//    [self setupSocketClient];
    [self setupTunnelNetwork];

}

- (void)getConfigurationInfo:(NEVPNProtocol *)configuration {
    NETunnelProviderProtocol * providerProtocol = (NETunnelProviderProtocol *)configuration;
    NSString * fullAddress = providerProtocol.serverAddress;
    NSArray * addressArr = [fullAddress componentsSeparatedByString:@":"];
    self.hostname = addressArr[0];
    self.port = [addressArr[1] intValue];
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    // Add code here to start the process of stopping the tunnel.
    [self.connectionMap removeAllObjects];
    completionHandler();
}

- (void)setupSocketClient {
    //ws://10.5.34.90/ws   ws://127.0.0.1:%d/vpn
//    NSString *urlString = [NSString stringWithFormat:@"ws://10.168.80.250:8080/ws1"];
//    self.myWebSocket = [[hpSRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];
//    self.myWebSocket.delegate = self;
//    [self.myWebSocket open];
    
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


- (void)setupTunnelNetwork {
    // configure TUN interface, it can capture IP packets.
    NSString * ip = @"10.10.10.10";
    NSString * subnetMask = @"255.255.255.0";
    NEPacketTunnelNetworkSettings * settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];

    settings.MTU = @65535;
    NEIPv4Settings * ipv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[ip] subnetMasks:@[subnetMask]];
    NEIPv4Route * allowRoute = [[NEIPv4Route alloc] initWithDestinationAddress:self.routeIP subnetMask:subnetMask];
    NEIPv4Route * allowRoute1 = [[NEIPv4Route alloc] initWithDestinationAddress:@"1.1.1.1" subnetMask:subnetMask];
    ipv4Settings.includedRoutes = @[allowRoute, allowRoute1];
//    ipv4Settings.excludedRoutes = @[
//        [[NEIPv4Route alloc] initWithDestinationAddress:@"10.0.0.0" subnetMask:@"255.0.0.0"],
//        [[NEIPv4Route alloc] initWithDestinationAddress:@"127.0.0.0" subnetMask:@"255.0.0.0"],
//        [[NEIPv4Route alloc] initWithDestinationAddress:@"192.168.0.0" subnetMask:@"255.0.0.0"]
//    ];
    settings.IPv4Settings = ipv4Settings;
    
    
    //ipv6 setting  https://www.jianshu.com/p/3db3a97510ab
//    NSString * ipv6 = @"fd12:1:1:1::2";
//    NEIPv6Settings * ipv6Settings = [[NEIPv6Settings alloc] initWithAddresses:@[ipv6] networkPrefixLengths:@[@128]];
//    NEIPv6Route * route = [[NEIPv6Route alloc] initWithDestinationAddress:@"::" networkPrefixLength:@1];
//    NEIPv6Route *route1 = [[NEIPv6Route alloc]initWithDestinationAddress:@"8000::" networkPrefixLength:@1];
//    ipv6Settings.includedRoutes = @[route, route1];
//    settings.IPv6Settings = ipv6Settings;
    
    //dns setting
    NEDNSSettings * dnsSettings = [[NEDNSSettings alloc] initWithServers:@[@"1.1.1.1"]];
    dnsSettings.matchDomains = @[self.domainName];
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

//- (void)startServer {
//    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
//    self.clientSockets = [[NSMutableArray alloc] initWithCapacity:1];
//    NSError * error = nil;
//    [self.socket acceptOnPort:12355 error:&error];
//    if (error) {
//        NSLog(@"start TCP socket server error: %@", error.localizedDescription);
//    } else {
//        NSLog(@"start TCP socket server success......");
//    }
//}


- (void)readPackets {
    NSLog(@"jsp---------start readPackets---------");
    [self.packetFlow readPacketObjectsWithCompletionHandler:^(NSArray<NEPacket *> * _Nonnull packets) {
        [packets enumerateObjectsUsingBlock:^(NEPacket * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self parsePacket:obj.data];
        }];
        [self readPackets];
    }];
}

- (void)parsePacket:(NSData *)packet {
    NSLog(@"jsp---- read from tun0: %@", packet.hexString);
    Byte *byteArr = (Byte *)packet.bytes;
    NSArray * arr = [self.routeIP componentsSeparatedByString:@"."];
    
    // we only parse IPv4 packet now.
    NSUInteger ipVersion = [self getIPVersion:byteArr];
    if (ipVersion == 4) {
        // 1. is it a UDP
        TransportProtocol transProtocol = [self getTransProtocol:byteArr];
        if (transProtocol == TCP) {
            NSLog(@"jsp------ read from tun0 data length :%d", packet.length);
            UInt16 len = [self getTotalLength:byteArr];
            NSLog(@"jsp------ read from tun0, len = %d", len);
            // 1. read: 10.10.10.10:1234 ----> 1.2.3.4:80
            // 2. change to: 1.2.3.4:1234 -----> 10.10.10.10:12355, and write to tun0
            // 3. read: 10.10.10.10:12355 -----> 1.2.3.4:1234
            // 4. change to: 1.2.3.4:80 -----> 10.10.10.10:1234, and write to tun0
            
            //TCP flag [ACK]:0x10  [SYN,ACK]:0x12  [SYN]:0x02
//            Byte flag = byteArr[33];
            
            
            // get src des port
            UInt16 srcPort = [self getSourcePort:byteArr];
            UInt16 desPort = [self getDestinationPort:byteArr];
            
            // 1. read: 10.10.10.10:1234 ----> 1.2.3.4:80
            if (byteArr[12] == 0x0a && byteArr[13] == 0x0a &&
                byteArr[14] == 0x0a && byteArr[15] == 0x0a &&
                srcPort != 12355) {
                BOOL isOdd = NO;
                
                NSString * key = [NSString stringWithFormat:@"%d", srcPort];
                NSString * value = [self.connectionMap valueForKey:key];
                if (value == nil) {
                    [self.connectionMap setObject:[NSString stringWithFormat:@"%d", desPort] forKey:key];
                }
                UInt16 len = [self getTotalLength:byteArr];
                if (len % 2 != 0) {
                    isOdd = YES;
                }
                int ipHeaderLen = [self getIPHeaderLength:byteArr];
                NSLog(@"jsp-------ipHeaderLen: %d", ipHeaderLen);
                
                NSMutableArray * resIP = [NSMutableArray array];
                for (int i = 0; i < ipHeaderLen; i++) {
                    resIP[i] = [NSNumber numberWithUnsignedChar:byteArr[i]];
                }
                //exchange source IP <---> destination IP
                [resIP exchangeObjectAtIndex:12 withObjectAtIndex:16];
                [resIP exchangeObjectAtIndex:13 withObjectAtIndex:17];
                [resIP exchangeObjectAtIndex:14 withObjectAtIndex:18];
                [resIP exchangeObjectAtIndex:15 withObjectAtIndex:19];
                
                NSMutableArray * resTCP = [NSMutableArray array];
                NSUInteger tcpLen = len - ipHeaderLen;

                Byte tcpLen1 = (tcpLen >> 8) & 0xff;
                Byte tcpLen2 = tcpLen & 0xff;
                
                for (int i = 0; i < tcpLen; i++) {
                    resTCP[i] = [NSNumber numberWithUnsignedChar:byteArr[ipHeaderLen + i]];
                }
                
                NSMutableArray * tempArr = [NSMutableArray array];
                NSArray * fakeTCPHeader = @[
                    resIP[12], resIP[13], resIP[14], resIP[15],
                    resIP[16], resIP[17], resIP[18], resIP[19],
                    @(0x00), @(0x06), @(tcpLen1), @(tcpLen2)
                ];
                
                //change des port to TCP server listenning port: 12355
                Byte desPort1 = (12355 >> 8) & 0xff;
                Byte desPort2 = 12355 & 0xff;
                resTCP[2] = @(desPort1);
                resTCP[3] = @(desPort2);
                
                [tempArr addObjectsFromArray:fakeTCPHeader];
                //reset TCP checksum
                resTCP[16] = @(0x00);
                resTCP[17] = @(0x00);
                
                if (isOdd) {
                    [resTCP addObject:@(0x00)];
                }
                [tempArr addObjectsFromArray:resTCP];
                uint16_t res = [self calculateCheckSum:tempArr];
                Byte tcpChecksum1 = (res >> 8) & 0xff;
                Byte tcpChecksum2 = res & 0xff;
                // replace checksum field
                resTCP[16] = @(tcpChecksum1);
                resTCP[17] = @(tcpChecksum2);
                
                [tempArr removeAllObjects];
                [tempArr addObjectsFromArray:resIP];
                if (isOdd) {
                    [resTCP removeLastObject];
                }
                [tempArr addObjectsFromArray:resTCP];
                
                NSUInteger n = tempArr.count;
                Byte reveive[n];
                for (int i = 0; i < n; i++) {
                    reveive[i] = [tempArr[i] unsignedCharValue];
                }
                NSData * data = [NSData dataWithBytes:reveive length:sizeof(reveive)];
                NSLog(@"jsp------1111 send to tun0: %@", data.hexString);
                [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
            }
            
            // 3. read: 10.10.10.10:12355 -----> 1.2.3.4:1234
            if (byteArr[12] == 0x0a && byteArr[13] == 0x0a &&
                byteArr[14] == 0x0a && byteArr[15] == 0x0a &&
                srcPort == 12355) {
                NSLog(@"jsp------ srcPort == 12355");
                // isOdd: if totalLen is odd, we need add a 0x00 byte at the last of packet, for checksum
                BOOL isOdd = NO;
                UInt16 len = [self getTotalLength:byteArr];
                if (len % 2 != 0) {
                    isOdd = YES;
                }
                int ipHeaderLen = [self getIPHeaderLength:byteArr];
                
                UInt16 desPort = [self getDestinationPort:byteArr];
                // desPort is key for connMap, we can get original desPort from this key.
                NSString * key = [NSString stringWithFormat:@"%d", desPort];
                NSString * originalDesport = [self.connectionMap valueForKey:key];
                Byte port = (Byte)[originalDesport intValue];
                
                
                NSMutableArray * resIP = [NSMutableArray array];
                for (int i = 0; i < ipHeaderLen; i++) {
                    resIP[i] = [NSNumber numberWithUnsignedChar:byteArr[i]];
                }
                
                //exchange source IP <---> destination IP
                [resIP exchangeObjectAtIndex:12 withObjectAtIndex:16];
                [resIP exchangeObjectAtIndex:13 withObjectAtIndex:17];
                [resIP exchangeObjectAtIndex:14 withObjectAtIndex:18];
                [resIP exchangeObjectAtIndex:15 withObjectAtIndex:19];
                
                NSMutableArray * resTCP = [NSMutableArray array];
                NSUInteger tcpLen = len - ipHeaderLen;
                Byte tcpLen1 = (tcpLen >> 8) & 0xff;
                Byte tcpLen2 = tcpLen & 0xff;
                
                for (int i = 0; i < tcpLen; i++) {
                    resTCP[i] = [NSNumber numberWithUnsignedChar:byteArr[ipHeaderLen + i]];
                }
                if (isOdd) {
                    [resTCP addObject:@(0x00)];
                }
                
                NSMutableArray * tempArr = [NSMutableArray array];
                NSArray * fakeTCPHeader = @[
                    resIP[12], resIP[13], resIP[14], resIP[15],
                    resIP[16], resIP[17], resIP[18], resIP[19],
                    @(0x00), @(0x06), @(tcpLen1), @(tcpLen2)
                ];
                
                //change src port to originalDesPort
                Byte srcPort1 = (port >> 8) & 0xff;
                Byte srcPort2 = port & 0xff;
                resTCP[0] = @(srcPort1);
                resTCP[1] = @(srcPort2);
                
                [tempArr addObjectsFromArray:fakeTCPHeader];
                
                resTCP[16] = @(0x00);
                resTCP[17] = @(0x00);
                
                [tempArr addObjectsFromArray:resTCP];
                uint16_t res = [self calculateCheckSum:tempArr];
                Byte tcpChecksum1 = (res >> 8) & 0xff;
                Byte tcpChecksum2 = res & 0xff;
                
                // replace checksum field
                resTCP[16] = @(tcpChecksum1);
                resTCP[17] = @(tcpChecksum2);
                // remove last object if total count is not odd
                
                
                [tempArr removeAllObjects];
                [tempArr addObjectsFromArray:resIP];
                if (isOdd) {
                    [resTCP removeLastObject];
                }
                [tempArr addObjectsFromArray:resTCP];
                
                NSUInteger n = tempArr.count;
                Byte reveive[n];
                for (int i = 0; i < n; i++) {
                    reveive[i] = [tempArr[i] unsignedCharValue];
                }
                NSData * data = [NSData dataWithBytes:reveive length:sizeof(reveive)];
                NSLog(@"jsp------22222 send to tun0: %@", data.hexString);
                [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
            }
            
            
            


//            [self.packetFlow writePackets:@[packet] withProtocols:@[@AF_INET]];
//            NSLog(@"jsp---------- 11111");
//            NSString * desIP = @"127.0.0.1";
//            UInt16 len = [self getTotalLength:byteArr];
//            int ipHeaderLen = [self getIPHeaderLength:byteArr];
//            
//            NSMutableArray * resIP = [NSMutableArray array];
//            for (int i = 0; i < ipHeaderLen; i++) {
//                resIP[i] = [NSNumber numberWithUnsignedChar:byteArr[i]];
//            }
//            // replace desIP to "127.0.0.1"
//            resIP[16] = @(127);
//            resIP[17] = @(0);
//            resIP[18] = @(0);
//            resIP[19] = @(1);
//            // reset checksum
//            resIP[10] = @(0x00);
//            resIP[11] = @(0x00);
//            
//            uint16_t ipCheckSum = [self calculateCheckSum:resIP];
//            Byte ipCheckSum1 = (ipCheckSum >> 8) & 0xff;
//            Byte ipCheckSum2 = ipCheckSum & 0xff;
//            
//            resIP[10] = @(ipCheckSum1);
//            resIP[11] = @(ipCheckSum2);
//            
//            NSMutableArray * resTCP = [NSMutableArray array];
//            NSUInteger tcpLen = len - ipHeaderLen;
//            Byte tcpLen1 = (tcpLen >> 8) & 0xff;
//            Byte tcpLen2 = tcpLen & 0xff;
//            
//            for (int i = 0; i < tcpLen; i++) {
//                resTCP[i] = [NSNumber numberWithUnsignedChar:byteArr[ipHeaderLen + i]];
//            }
//            
//            NSMutableArray * tempArr = [NSMutableArray array];
//            NSArray * fakeTCPHeader = @[
//                @(0x0a), @(0x0a), @(0x0a), @(0x0a),
//                @(127), @(0), @(0), @(1),
//                @(0x00), @(0x06), @(tcpLen1), @(tcpLen2)
//            ];
//            [tempArr addObjectsFromArray:fakeTCPHeader];
//            resTCP[16] = @(0x00);
//            resTCP[17] = @(0x00);
//            
//            
//            [tempArr addObjectsFromArray:resTCP];
//            
//            uint16_t res = [self calculateCheckSum:tempArr];
//            Byte tcpChecksum1 = (res >> 8) & 0xff;
//            Byte tcpChecksum2 = res & 0xff;
//            
//            // replace checksum field
//            resTCP[16] = @(tcpChecksum1);
//            resTCP[17] = @(tcpChecksum2);
//            
//            [tempArr removeAllObjects];
//            [tempArr addObjectsFromArray:resIP];
//            [tempArr addObjectsFromArray:resTCP];
//            
//            NSUInteger n = tempArr.count;
//            Byte reveive[n];
//            for (int i = 0; i < n; i++) {
//                reveive[i] = [tempArr[i] unsignedCharValue];
//            }
//            NSData * data = [NSData dataWithBytes:reveive length:sizeof(reveive)];
//            NSLog(@"jsp------ send to tun0: %@", data.hexString);
//            [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
            
//            Byte flag = byteArr[33];
//            // we could simulate TCP handshake packets
//            // 1. client send  [SYN]
//            // 2. response [SYN, ACK]
//            // 3. client send [ACK]
//            if (flag == 0x02) { // SYN
//                NSLog(@"jsp--------SYN");
//                [self generateSYNACK:byteArr];
//            } else if (flag == 0x10) { // [ACK]:
//                NSLog(@"jsp--------ACK");
//                
//            } else if (flag == 0x11) { // [FIN, ACK]
//                NSLog(@"jsp------ [FIN, ACK]");
//                //1. client send [FIN, ACK]
//                //2. server reponse a [ACK] packet
//                [self generateACKPacket:byteArr];
//                //3. server send [FIN, ACK]
////                [self generateFINACKPacket:byteArr];
//                //4. client send  [ACK]
//            }
        } else if (transProtocol == UDP) {
            // 2. destination port: generally, 53 is for DNS query
            UInt16 desPort = [self getDestinationPort:byteArr];
            NSLog(@"jsp------- DNS port: %d", desPort);
            if (desPort != 53) {
                return;
            }
            // 3. only reply DNS query which its type is 'A'(IPv4)
            // 00 1C (28): AAAA(IPv6)
            // 00 41 (65): HTTPS
            // 00 01 (1):  A(IPv4)
            UInt16 type = [self getDNSQueryType:byteArr];
            NSLog(@"jsp----- DNS TYPE = %d", type);
            if (type == 1) {
                [self getDomainName:byteArr];
                // 3. get the target DNS query domainame
                if ([self isPacketForPrivateDomainQuery:byteArr]) {
                    NSLog(@"jsp---- match domainname.......");
                    [self generateDNSResponsePacket:byteArr];
                }
            }
        }
    }
}

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
//    NSLog(@"jsp---- %@", tempArr); // 3www4bbnn3com0
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
        domaninName[i] = (Byte)[self.domainArr[i] intValue];
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
    
    // address, domain name --> IP: self.routeIP
    NSArray * ipArr = [self.routeIP componentsSeparatedByString:@"."];
    
    Byte ip1 = (Byte)[ipArr[0] intValue];
    Byte ip2 = (Byte)[ipArr[1] intValue];
    Byte ip3 = (Byte)[ipArr[2] intValue];
    Byte ip4 = (Byte)[ipArr[3] intValue];
    
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

    //*****************************IP*********************************
    // protocol and header length  IPv4 or IPv6 , header length 20
    Byte ipVersionAndHeaderLength = byteArr[0];
    
    // differentiated services field
    Byte dsf = byteArr[1];
    
    // IP packet length: IP header length(20) + UDP length
    // get IP header length
    int ipHeaderLen = (byteArr[0] & 0x0f) * 4;
    UInt16 ipLen = ipHeaderLen + resUDPLength;
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

- (NSUInteger)getIPVersion:(Byte *)byteArr {
    Byte b = byteArr[0];
    return (b >> 4) & 0xff;
}

- (TransportProtocol)getTransProtocol:(Byte *)byteArr {
    return (TransportProtocol)byteArr[9];
}

- (UInt16)getTotalLength:(Byte *)byteArr {
    Byte totalLen[] = {byteArr[2], byteArr[3]};
    UInt16 len;
    memcpy(&len, totalLen, sizeof(len));
    // iOS is little-endian by default
    UInt16 res = htons(len);
    return res;
}

- (UInt16)getDestinationPort:(Byte *)byteArr {
    Byte desport[] = {byteArr[22], byteArr[23]};
    UInt16 portValue;
    memcpy(&portValue, desport, sizeof(portValue));
    // iOS is little-endian by default
    UInt16 res = htons(portValue);
    return res;
}

- (UInt16)getSourcePort:(Byte *)byteArr {
    Byte srcport[] = {byteArr[20], byteArr[21]};
    UInt16 portValue;
    memcpy(&portValue, srcport, sizeof(portValue));
    // iOS is little-endian by default
    UInt16 res = htons(portValue);
    return res;
}


- (UInt16)getDNSQueryType:(Byte *)byteArr {
    UInt16 len = [self getTotalLength:byteArr];
    Byte type[] = {byteArr[len - 4], byteArr[len - 3]};
    UInt16 typeValue;
    memcpy(&typeValue, type, sizeof(typeValue));
    // iOS is little-endian by default
    UInt16 res = htons(typeValue);
    return res;
}

- (int)getIPHeaderLength:(Byte *)byteArr {
    return (byteArr[0] & 0x0f) * 4;
}

- (UInt32)getSYNSeqNum:(const Byte *)byteArr {
    UInt32 seqNum;
    memcpy(&seqNum, byteArr, sizeof(seqNum));
    seqNum = htonl(seqNum);
    return seqNum;
}
/*
- (void)generateSYNACK:(Byte *)byteArr {
    UInt16 len = [self getTotalLength:byteArr];
    int ipHeaderLen = [self getIPHeaderLength:byteArr];
    
    int tcpLen = len - ipHeaderLen;
    int tcpOptLen = tcpLen - 20; // TCP header length is 20 bytes(fixed).
    
    int index = ipHeaderLen;
    // reveive TCP[SYN], generate a TCP[SYN, ACK]
    Byte len1 = (len >> 8) & 0xff;
    Byte len2 = len & 0xff;

    NSMutableArray * resIP = [NSMutableArray arrayWithArray:@[
        @(0x45), @(0x00),
        @(len1), @(len2),
        @(0x10), @(0x6f),
        @(0x00), @(0x00),
        @(0x37), @(0x06),
        @(0x00), @(0x00), // checksum
        @(byteArr[16]), @(byteArr[17]), @(byteArr[18]), @(byteArr[19]),
        @(byteArr[12]), @(byteArr[13]), @(byteArr[14]), @(byteArr[15])
    ]];
    
    
    uint16_t ipCheckSum = [self calculateCheckSum:resIP];
    Byte ipCheckSum1 = (ipCheckSum >> 8) & 0xff;
    Byte ipCheckSum2 = ipCheckSum & 0xff;
    
    resIP[10] = @(ipCheckSum1);
    resIP[11] = @(ipCheckSum2);
    
    // 1. get source and destination port
    Byte srcPort1 = byteArr[index];
    Byte srcPort2 = byteArr[index + 1];
    
    Byte desPort1 = byteArr[index + 2];
    Byte desPort2 = byteArr[index + 3];
    
    // 2. get seq number
    Byte seqNum[] = { byteArr[index + 4], byteArr[index + 5], byteArr[index + 6], byteArr[index + 7] };
    UInt32 synSeqNum = [self getSYNSeqNum:seqNum];
    
    UInt32 synAckNum = synSeqNum + 1;
    Byte synAck1 = synAckNum & 0xff;
    Byte synAck2 = (synAckNum >> 8) & 0xff;
    Byte synAck3 = (synAckNum >> 16) & 0xff;
    Byte synAck4 = (synAckNum >> 24) & 0xff;
    
    NSMutableArray * resTCP = [NSMutableArray arrayWithArray:@[
        @(desPort1), @(desPort2), @(srcPort1), @(srcPort2),
        @(0x00), @(0x00), @(0x00), @(0x01), @(synAck4), @(synAck3), @(synAck2), @(synAck1),
        @(0xb0), @(0x12),
        @(0xff), @(0xff),
        @(0x00), @(0x00), //checksum
        @(0x00), @(0x00), //urgent pointer
    ]];
    
    NSMutableArray * opt = [NSMutableArray array];
    for (int i = 0; i < tcpOptLen; i++) {
        [opt addObject:@(byteArr[ipHeaderLen + 20 + i])];
    }
    
    Byte tcpLen1 = (tcpLen >> 8) & 0xff;
    Byte tcpLen2 = tcpLen & 0xff;
    
    NSArray * fakeTCPHeader = @[
        @(byteArr[16]), @(byteArr[17]), @(byteArr[18]), @(byteArr[19]),
        @(byteArr[12]), @(byteArr[13]), @(byteArr[14]), @(byteArr[15]),
        @(0x00), @(0x06), @(tcpLen1), @(tcpLen2)
    ];
    
    NSArray * tempTCPArr = [[fakeTCPHeader arrayByAddingObjectsFromArray:resTCP] arrayByAddingObjectsFromArray:opt];
    uint16_t res = [self calculateCheckSum:tempTCPArr];
    Byte tcpChecksum1 = (res >> 8) & 0xff;
    Byte tcpChecksum2 = res & 0xff;
    
    // replace checksum field
    resTCP[16] = @(tcpChecksum1);
    resTCP[17] = @(tcpChecksum2);
    
    [resIP addObjectsFromArray:resTCP];
    [resIP addObjectsFromArray:opt];
    NSUInteger n = resIP.count;
    Byte resSynAck[n];
    for (int i = 0; i < n; i++) {
        resSynAck[i] = (Byte)[resIP[i] intValue];
    }
    
    NSData * data = [NSData dataWithBytes:resSynAck length:n];
    [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
}
*/

/*
- (void)generateACKPacket:(Byte *)byteArr {
    NSMutableArray * ipArr = [NSMutableArray array];
    int ipHeaderLen = [self getIPHeaderLength:byteArr];
    for (int i = 0; i < ipHeaderLen; i++) {
        NSNumber * value = [NSNumber numberWithUnsignedChar:byteArr[i]];
        [ipArr addObject:value];
    }
    // replace sourceip and des ip
    [ipArr exchangeObjectAtIndex:12 withObjectAtIndex:16];
    [ipArr exchangeObjectAtIndex:13 withObjectAtIndex:17];
    [ipArr exchangeObjectAtIndex:14 withObjectAtIndex:18];
    [ipArr exchangeObjectAtIndex:15 withObjectAtIndex:19];
    
    // set checksum to 0x00
    ipArr[10] = @(0x00);
    ipArr[11] = @(0x00);
    
    uint16_t checksum = [self calculateCheckSum:ipArr];
    Byte ipChecksum1 = (checksum >> 8) & 0xff;
    Byte ipChecksum2 = checksum & 0xff;
    // replace checksum field
    ipArr[10] = @(ipChecksum1);
    ipArr[11] = @(ipChecksum2);
    
    
    //generate TCP part
    NSMutableArray * tcpArr = [NSMutableArray array];
    UInt16 len = [self getTotalLength:byteArr];
    int tcpLen = len - ipHeaderLen;
    
    for (int i = 0; i < tcpLen; i++) {
        NSNumber * value = [NSNumber numberWithUnsignedChar:byteArr[i + ipHeaderLen]];
        [tcpArr addObject:value];
    }
    // replace src port and des port
    // srcPort:[0] [1] desPort:[2] [3]
    [tcpArr exchangeObjectAtIndex:0 withObjectAtIndex:2];
    [tcpArr exchangeObjectAtIndex:1 withObjectAtIndex:3];
    
    // get seq number
    Byte seqNum[] = { [tcpArr[4] unsignedCharValue], [tcpArr[5] unsignedCharValue], [tcpArr[6] unsignedCharValue], [tcpArr[7] unsignedCharValue] };
    UInt32 synSeqNum = [self getSYNSeqNum:seqNum];
    
    // generate ack num: seq + 1
    UInt32 synAckNum = synSeqNum + 1;
    Byte synAck1 = synAckNum & 0xff;
    Byte synAck2 = (synAckNum >> 8) & 0xff;
    Byte synAck3 = (synAckNum >> 16) & 0xff;
    Byte synAck4 = (synAckNum >> 24) & 0xff;
    
    tcpArr[8] = @(synAck4);
    tcpArr[9] = @(synAck3);
    tcpArr[10] = @(synAck2);
    tcpArr[11] = @(synAck1);
    
    // set flag to ACK
    tcpArr[13] = @(0x010);
    
    // reset checksum to 0 temporarily
    tcpArr[16] = @(0x00);
    tcpArr[17] = @(0x00);
    
    //recalculate checksum for tcp part
    Byte tcpLen1 = (tcpLen >> 8) & 0xff;
    Byte tcpLen2 = tcpLen & 0xff;
    NSMutableArray * tempArr = [NSMutableArray array];
    
    NSArray * fakeTCPHeader = @[
        @(byteArr[16]), @(byteArr[17]), @(byteArr[18]), @(byteArr[19]),
        @(byteArr[12]), @(byteArr[13]), @(byteArr[14]), @(byteArr[15]),
        @(0x00), @(0x06), @(tcpLen1), @(tcpLen2)
    ];
    [tempArr addObjectsFromArray:fakeTCPHeader];
    [tempArr addObjectsFromArray:tcpArr];
    
    uint16_t res = [self calculateCheckSum:tempArr];
    Byte tcpChecksum1 = (res >> 8) & 0xff;
    Byte tcpChecksum2 = res & 0xff;
    
    // replace checksum field
    tcpArr[16] = @(tcpChecksum1);
    tcpArr[17] = @(tcpChecksum2);
    
    [tempArr removeAllObjects];
    [tempArr addObjectsFromArray:ipArr];
    [tempArr addObjectsFromArray:tcpArr];
    
    NSUInteger n = tempArr.count;
    Byte resFINACK[n];
    for (int i = 0; i < n; i++) {
        resFINACK[i] = [tempArr[i] unsignedCharValue];
    }
    NSLog(@"jsp-------[ACK]: %@", tempArr);
    NSData * data = [NSData dataWithBytes:resFINACK length:n];
    [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
    
    // set flag to FIN,ACK
    tcpArr[13] = @(0x11);
    
    // reset checksum
    tcpArr[16] = @(0x00);
    tcpArr[17] = @(0x00);
    
    // seq + 1
    // get seq number
    Byte seqNum1[] = { [tcpArr[4] unsignedCharValue], [tcpArr[5] unsignedCharValue], [tcpArr[6] unsignedCharValue], [tcpArr[7] unsignedCharValue] };
    UInt32 finACKSeqNum = [self getSYNSeqNum:seqNum1];
    
    // generate new seq num: seq + 1
    UInt32 finACKSeqNumRes = finACKSeqNum + 1;
    Byte finAck1 = finACKSeqNumRes & 0xff;
    Byte finAck2 = (finACKSeqNumRes >> 8) & 0xff;
    Byte finAck3 = (finACKSeqNumRes >> 16) & 0xff;
    Byte finAck4 = (finACKSeqNumRes >> 24) & 0xff;
    
    tcpArr[4] = @(finAck4);
    tcpArr[5] = @(finAck3);
    tcpArr[6] = @(finAck2);
    tcpArr[7] = @(finAck1);
    
    [tempArr removeAllObjects];
    [tempArr addObjectsFromArray:fakeTCPHeader];
    [tempArr addObjectsFromArray:tcpArr];
    
    uint16_t res1 = [self calculateCheckSum:tempArr];
    Byte tcpChecksum11 = (res1 >> 8) & 0xff;
    Byte tcpChecksum22 = res1 & 0xff;
    
    // replace checksum field
    tcpArr[16] = @(tcpChecksum11);
    tcpArr[17] = @(tcpChecksum22);
    
    [tempArr removeAllObjects];
    [tempArr addObjectsFromArray:ipArr];
    [tempArr addObjectsFromArray:tcpArr];
    
    
    NSUInteger n1 = tempArr.count;
    Byte finACKToClient[n];
    for (int i = 0; i < n1; i++) {
        finACKToClient[i] = (Byte)[tempArr[i] unsignedCharValue];
    }
    NSLog(@"jsp-------[FIN, ACK]: %@", tempArr);
    NSData * data1 = [NSData dataWithBytes:finACKToClient length:n1];
    [self.packetFlow writePackets:@[data1] withProtocols:@[@AF_INET]];
    
}
*/

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

- (uint16_t)calculateCheckSum:(NSArray *)header {
    uint32_t sum = 0;
    unsigned long length = header.count;
    for (int i = 0; i < length; i += 2) {
        UInt16 value = [header[i] intValue];
        UInt16 value1 = [header[i + 1] intValue];
        uint16_t word = (value << 8) + value1;
        sum += word;
        
        if (sum > 0xffff) {
            sum = (sum & 0xffff) + 1;
        }
    }
    return ~((uint16_t)sum);
}

/*
- (void)webSocketDidOpen:(hpSRWebSocket *)webSocket {
    NSLog(@"jsp------ didopen");
//    [self.myWebSocket send:@"sssss"];
    [self setupTunnelNetwork];
}

- (void)webSocket:(hpSRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"jsp------ fail: %@", error);
}

- (void)webSocket:(hpSRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"jsp-------- close");
}

- (void)webSocket:(hpSRWebSocket *)webSocket didReceiveMessage:(id)message {
    NSData * data = (NSData *)message;
    NSLog(@"jsp----- receive message: %@", data.hexString);
    [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
}
*/


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

//- (NSMutableArray *)getCorrectPacket:(NSData *)data {
//    NSInteger totalLength = data.length;
//    if (totalLength == 0) {
//        return nil;
//    }
//
//    NSInteger offset = 0;
//    NSMutableArray * arr = [NSMutableArray array];
//    while (offset < totalLength) {
//        NSData * temp = [data subdataWithRange:NSMakeRange(2 + offset, 2)];
//        unsigned result = 0;
//        NSScanner *scanner = [NSScanner scannerWithString:[temp hexString]];
//        [scanner scanHexInt:&result];
//        NSData * ele = [data subdataWithRange:NSMakeRange(offset, result)];
//        [arr addObject:ele];
//        offset += result;
//    }
//    return arr;
//}

/*
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"tcp server read:------ %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    [sock readDataWithTimeout:-1 tag:tag];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    NSLog(@"new socket connect: %@", newSocket);
    // in current logic, we should ensure connector connects with server first, so
    // the first object in self.clientSockets should be connector client.
    // This method is executed on the socketQueue (not the main thread)
    @synchronized(self.clientSockets) {
        [self.clientSockets addObject:newSocket];
        [newSocket readDataWithTimeout:-1 tag:100];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (err) {
        NSLog(@"DidDisconnect error: %@", err.localizedDescription);
    } else if (sock != self.socket) {
        @synchronized(self.clientSockets) {
            [self.clientSockets removeObject:sock];
        }
    }
}
*/

@end
