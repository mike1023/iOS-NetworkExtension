//
//  PacketTunnelProvider.m
//  tunnelVPN
//
//  Created by Harris on 2023/5/12.
//

#import "PacketTunnelProvider.h"
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"


@interface PacketTunnelProvider ()<GCDAsyncSocketDelegate>
@property (nonatomic, copy) void (^completionHandler)(NSError *);
@property (nonatomic, copy) NSString * hostname;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *clientSockets;
@property (nonatomic, assign) BOOL isRunning;

//@property (nonatomic, strong) NWUDPSession * udpSession;
//@property (nonatomic, strong) NSMutableDictionary * udpSessionDict;


@end

@implementation PacketTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler {
    // Add code here to start the process of connecting the tunnel.
    [self getConfigurationInfo:self.protocolConfiguration];
    self.completionHandler = completionHandler;
//    [self setupUDPSession];
//    [self setupTunnelNetwork];
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
    ipv4Settings.includedRoutes = @[[NEIPv4Route defaultRoute]];
    ipv4Settings.excludedRoutes = @[[[NEIPv4Route alloc] initWithDestinationAddress:@"127.0.0.1" subnetMask:subnetMask]];
    settings.IPv4Settings = ipv4Settings;
    
    //ipv6 setting
    NSString * ipv6 = @"fd12:1:1:1::2";
    NEIPv6Settings * ipv6Settings = [[NEIPv6Settings alloc] initWithAddresses:@[ipv6] networkPrefixLengths:@[@128]];
    //https://www.jianshu.com/p/3db3a97510ab
    NEIPv6Route * route = [[NEIPv6Route alloc] initWithDestinationAddress:@"::" networkPrefixLength:@1];
    NEIPv6Route *route1 = [[NEIPv6Route alloc]initWithDestinationAddress:@"8000::" networkPrefixLength:@1];
    ipv6Settings.includedRoutes = @[route, route1];
    settings.IPv6Settings = ipv6Settings;
    
    //dns setting
    NEDNSSettings * dnsSettings = [[NEDNSSettings alloc] initWithServers:@[@"8.8.8.8", @"8.8.4.4"]];
    dnsSettings.matchDomains = @[@""];
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
                [self.socket writeData:obj.data withTimeout:-1 tag:0];
//                [self.udpSession writeDatagram:obj.data completionHandler:^(NSError * _Nullable error) {
//                    if (error) {
//                        NSLog(@"jsp---- udp write data error:%@", error.localizedDescription);
//                    } else {
//                        NSLog(@"jsp---- udp write data: %@", obj.data);
//                    }
//                }];
            });
        }];
        [self readPackets];
    }];
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
    NSLog(@"socket connect success...");
    [sock readDataWithTimeout:-1 tag:100];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {

}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSMutableArray * arr = [self getCorrectPacket:data];
    for (NSData *obj in arr) {
        NSLog(@"receive data from device server: %@", [obj hexString]);
        [self.packetFlow writePackets:@[obj] withProtocols:@[@AF_INET]];
    }
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
