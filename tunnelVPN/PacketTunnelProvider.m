//
//  PacketTunnelProvider.m
//  tunnelVPN
//
//  Created by Harris on 2023/5/12.
//

#import "PacketTunnelProvider.h"
#import "NSData+HexString.h"
#import "GCDAsyncSocket.h"



typedef NS_ENUM(UInt8, TransportProtocol) {
    TCP = 6,
    UDP = 17
};

#define TCPLISTENINGPORT 12355
static const char *CLIENT_QUEUE_NAME = "com.opentext.tunnel_vpn.client";

@interface PacketTunnelProvider ()<GCDAsyncSocketDelegate>
@property (nonatomic, copy) void (^completionHandler)(NSError *);

@property (nonatomic, copy) NSArray * domainArr;

@property (nonatomic, copy) NSString * requestDomainName;
@property (nonatomic, copy) NSArray * userDomainArr;
@property (nonatomic, copy) NSArray * routeIPs;

@property (nonatomic, strong) NSMutableDictionary * connectionMap;
@property (nonatomic, strong) NSDictionary * domainIPDict;

@property (nonatomic, strong) GCDAsyncSocket* socketClient;
@property (nonatomic, strong) dispatch_queue_t socketQueue;

@end

@implementation PacketTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler {
    // Add code here to start the process of connecting the tunnel.
    NSMutableDictionary * tempDict = [NSMutableDictionary dictionaryWithDictionary:options];
    // options be added two keys by system: AuthMethod, ServerAddress
    [tempDict removeObjectForKey:@"AuthMethod"];
    [tempDict removeObjectForKey:@"ServerAddress"];
    self.domainIPDict = [tempDict copy];
    self.userDomainArr = tempDict.allKeys;
    self.routeIPs = tempDict.allValues;
    NSLog(@"jsp---- %@", self.domainIPDict);
    NSLog(@"jsp---- %@", self.routeIPs);

    self.domainArr = [NSArray array];
    self.connectionMap = [NSMutableDictionary dictionary];

    self.completionHandler = completionHandler;
    [self setupSocketClient];
//    [self setupTunnelNetwork];
}


- (void)setupSocketClient {
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create(CLIENT_QUEUE_NAME, queueAttributes);
    self.socketClient = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    
    NSError *error = nil;
    if (![self.socketClient connectToHost:@"127.0.0.1" onPort:12355 error:&error]) {
        NSLog(@"jsp--- socket client connect failed: %@", error.localizedFailureReason);
        return;
    }
}

#pragma mark --socket delegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"jsp----- didConnectToHost");
    [self setupTunnelNetwork];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"jsp----- didWriteDataWithTag:%ld", tag);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"jsp----- socketDidDisconnect: %@", err);
}

#pragma mark --------
- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    // Add code here to start the process of stopping the tunnel.
    [self.connectionMap removeAllObjects];
    completionHandler();
}

- (void)setupTunnelNetwork {
    // configure TUN interface, it can capture IP packets.
    NSString * ip = @"10.10.10.10";
    NSString * subnetMask = @"255.255.255.0";
    NEPacketTunnelNetworkSettings * settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];

    settings.MTU = @65535;
    NEIPv4Settings * ipv4Settings = [[NEIPv4Settings alloc] initWithAddresses:@[ip] subnetMasks:@[subnetMask]];
    NSMutableArray * routeArr = [NSMutableArray array];
    for (NSString *routeIP in self.routeIPs) {
        NEIPv4Route * allowRoute = [[NEIPv4Route alloc] initWithDestinationAddress:routeIP subnetMask:subnetMask];
        [routeArr addObject:allowRoute];
    }
    NEIPv4Route * allowDNSRoute = [[NEIPv4Route alloc] initWithDestinationAddress:@"2.2.2.2" subnetMask:subnetMask];
    [routeArr addObject:allowDNSRoute];
    ipv4Settings.includedRoutes = [routeArr copy];
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
    NEDNSSettings * dnsSettings = [[NEDNSSettings alloc] initWithServers:@[@"2.2.2.2"]];
    dnsSettings.matchDomains = self.userDomainArr;
    dnsSettings.matchDomainsNoSearch = YES;
    settings.DNSSettings = dnsSettings;
    
    __weak typeof(self) weakSelf = self;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
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
            [self parsePacket:obj.data];
        }];
        [self readPackets];
    }];
}

- (void)exchangeIP:(NSMutableArray *)arr {
    [arr exchangeObjectAtIndex:12 withObjectAtIndex:16];
    [arr exchangeObjectAtIndex:13 withObjectAtIndex:17];
    [arr exchangeObjectAtIndex:14 withObjectAtIndex:18];
    [arr exchangeObjectAtIndex:15 withObjectAtIndex:19];
}

- (NSData *)convertPortMapToData:(NSMutableDictionary *)dict {
    NSError *error;
    NSData *dataFromDict = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        NSLog(@"jsp----- convert failed: %@", error);
        return nil;
    }
    return dataFromDict;
}

- (void)parsePacket:(NSData *)packet {
    Byte *byteArr = (Byte *)packet.bytes;
    // we only parse IPv4 packet now.
    NSUInteger ipVersion = [self getIPVersion:byteArr];
    if (ipVersion == 4) {
        // 1. is it a UDP
        TransportProtocol transProtocol = [self getTransProtocol:byteArr];
        if (transProtocol == TCP) {
            // 1. read: 10.10.10.10:1234 ----> 1.2.3.4:80
            // 2. change to: 1.2.3.4:1234 -----> 10.10.10.10:12355, and write to tun0
            // 3. read: 10.10.10.10:12355 -----> 1.2.3.4:1234
            // 4. change to: 1.2.3.4:80 -----> 10.10.10.10:1234, and write to tun0
            
            // get src des port
            UInt16 srcPort = [self getSourcePort:byteArr];
            UInt16 desPort = [self getDestinationPort:byteArr];
            // 1. read: 10.10.10.10:1234 ----> 1.2.3.4:80
            if (byteArr[12] == 0x0a && byteArr[13] == 0x0a &&
                byteArr[14] == 0x0a && byteArr[15] == 0x0a &&
                srcPort != 12355) {
                NSLog(@"jsp---- TCP  from tun0: %@", packet.hexString);

                BOOL isOdd = NO;
                NSString * key = [NSString stringWithFormat:@"%d", srcPort];
                NSString * value = [self.connectionMap valueForKey:key];
                if (value == nil) {
                    [self.connectionMap setObject:[NSString stringWithFormat:@"%d", desPort] forKey:key];
                    [self.socketClient writeData:[self convertPortMapToData:self.connectionMap] withTimeout:-1 tag:101];
                }
                UInt16 len = [self getTotalLength:byteArr];
                if (len % 2 != 0) {
                    isOdd = YES;
                }
                int ipHeaderLen = [self getIPHeaderLength:byteArr];
                
                NSMutableArray * resIP = [NSMutableArray array];
                for (int i = 0; i < ipHeaderLen; i++) {
                    resIP[i] = [NSNumber numberWithUnsignedChar:byteArr[i]];
                }
                //exchange source IP <---> destination IP
                [self exchangeIP:resIP];

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
                
                //change des port to TCP server listenning port
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
                NSLog(@"jsp---- 1111 send to tun0: %@", data.hexString);
                [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
            }
            
            // 3. read: 10.10.10.10:12355 -----> 1.2.3.4:1234
            if (byteArr[12] == 0x0a && byteArr[13] == 0x0a &&
                byteArr[14] == 0x0a && byteArr[15] == 0x0a &&
                srcPort == 12355) {
                NSLog(@"jsp---- 12355 read from tun0: %@", packet.hexString);

                // isOdd: if totalLen is odd, we need add a 0x00 byte at the last of packet, for checksum
                BOOL isOdd = NO;
                UInt16 len = [self getTotalLength:byteArr];
                if (len % 2 != 0) {
                    isOdd = YES;
                }
                int ipHeaderLen = [self getIPHeaderLength:byteArr];
                
                UInt16 desPort = [self getDestinationPort:byteArr];
                // currently, desPort is key for connMap, we can get original desPort from this key.
                NSString * key = [NSString stringWithFormat:@"%d", desPort];
                NSString * originalDesport = [self.connectionMap valueForKey:key];
                int port = [originalDesport intValue];
                
                NSMutableArray * resIP = [NSMutableArray array];
                for (int i = 0; i < ipHeaderLen; i++) {
                    resIP[i] = [NSNumber numberWithUnsignedChar:byteArr[i]];
                }
                
                //exchange source IP <---> destination IP
                [self exchangeIP:resIP];
                
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
                NSLog(@"jsp---- 12355 send to tun0: %@", data.hexString);
                [self.packetFlow writePackets:@[data] withProtocols:@[@AF_INET]];
            }
        } else if (transProtocol == UDP) {
            // 2. destination port: generally, 53 is for DNS query
            UInt16 desPort = [self getDestinationPort:byteArr];
            if (desPort == 53) {
//                NSLog(@"jsp------ dns query: %@", packet.hexString);

                // 3. only reply DNS query which its type is 'A'(IPv4)
                // 00 1C (28): AAAA(IPv6)
                // 00 41 (65): HTTPS
                // 00 01 (1):  A(IPv4)
                UInt16 type = [self getDNSQueryType:byteArr];
                if (type == 1) {
//                    NSLog(@"jsp------ dns query: %@", packet.hexString);
                    // 3. get the target DNS query domainame
                    if ([self isPacketForPrivateDomainQuery:byteArr]) {
                        [self generateDNSResponsePacket:byteArr];
                    }
                } else {
                    return;
                }
            }
        }
    }
}


- (BOOL)isPacketForPrivateDomainQuery:(unsigned char *)byteArr {
    UInt16 totalLen = [self getTotalLength:byteArr];
    // domain name start from index of 40, after domain name, type field has 2 bytes, class: IN has two 2 bytes.
    UInt16 domainNamePartLen = totalLen - 40 - 2 - 2;
    NSMutableArray * tempArr = [NSMutableArray array];
    NSMutableArray * res = [NSMutableArray array];
    for (int i = 40; i < domainNamePartLen + 40; i++) {
        char byte = byteArr[i];
        [res addObject:@(byte)];
        // In ASCII, printable characters are in the range of 0x20 (32 in decimal) to 0x7E (126 in decimal).
        if (byte >= 0x20 && byte <= 0x7e) {
            [tempArr addObject:@(byte)];
        }
    }
    NSUInteger count = tempArr.count;
    char domain[count + 1];
    for (int i = 0; i < count; i++) {
        NSNumber * obj = tempArr[i];
        domain[i] = [obj unsignedShortValue];
    }
    domain[count] = '\0';
    // domainStr: www.baidu.com -----> wwwbaiducom
    NSString * domainStr = [[NSString alloc] initWithCString:domain encoding:NSUTF8StringEncoding];
    
    for (NSString *domain in self.userDomainArr) {
        NSString * domainWithoutHttp = domain;
        if ([domain hasPrefix:@"http://"]) {
            domainWithoutHttp = [domain substringFromIndex:7];
        }
        if ([domain hasPrefix:@"https://"]) {
            domainWithoutHttp = [domain substringFromIndex:8];
        }
        
        NSArray * tempArr = [domainWithoutHttp componentsSeparatedByString:@"."];
        NSString * domainCombined = [tempArr componentsJoinedByString:@""];
        if ([domainCombined isEqualToString:domainStr]) {
            self.requestDomainName = domainWithoutHttp;
            self.domainArr = [res copy];
            NSLog(@"jsp---requestDomainName: %@", self.requestDomainName);
            NSLog(@"jsp--- domainArr: %@", self.domainArr);
            return YES;
        }
    }
    return NO;
}

- (void)generateDNSResponsePacket:(Byte *)byteArr {
    // 4. if the packet is a dns query for private domain name, let's start generate a fake response packet.
    //************************DNS*************************
    // IP header length 20bytes, UDP header 8bytes, so the start index of DNS part is 28.
    // 1. Transaction ID: the same as query packet
    Byte transactionID1 = byteArr[28];
    Byte transactionID2 = byteArr[29];
    // 2. Flags
    Byte flags1 = 0x81;
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
    Byte ttl3 = 0x00;
    Byte ttl4 = 0x78;
    
    // data length
    Byte len1 = 0x00;
    Byte len2 = 0x04;
    
    NSString * routeIP = [self.domainIPDict valueForKey:self.requestDomainName];
    NSArray * ipArr = [routeIP componentsSeparatedByString:@"."];
    
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
    
    size_t count = sizeof(resUDPForChecksum);
    uint16_t udpChecksum;
    if (count % 2 != 0) {
        Byte resArr[count + 1];
        memcpy(resArr, resUDPForChecksum, count);
        resArr[count] = 0x00;
        udpChecksum = [self calculateChecksum:resArr length:sizeof(resArr)];
    } else {
        udpChecksum = [self calculateChecksum:resUDPForChecksum length:sizeof(resUDPForChecksum)];
    }
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

@end
