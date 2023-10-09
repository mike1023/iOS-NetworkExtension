//
//  ViewController.m
//  tunnel_vpn
//
//  Created by Harris on 2023/5/12.
//

#import "ViewController.h"
#import <NetworkExtension/NetworkExtension.h>
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"

#define EXTENSION_BUNDLE_ID @"com.opentext.harris.tunnel-vpn.tunnelVPN"
#define HOST @"127.0.0.1"
#define PORT @"12344"

static const char *QUEUE_NAME = "com.opentext.tunnel_vpn";

@interface ViewController ()<GCDAsyncSocketDelegate>
@property (nonatomic, strong) NETunnelProviderManager * manager;
@property (nonatomic, strong) GCDAsyncSocket *socket;
//@property (nonatomic, strong) GCDAsyncUdpSocket *udpSocket;


@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *clientSockets;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create(QUEUE_NAME, queueAttributes);
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> * _Nullable managers, NSError * _Nullable error) {
        if (error) {
            NSLog(@"load preferences error: %@", error.localizedFailureReason);
            return;
        }
        if (managers == nil || managers.count == 0) {
            [self configureManager];
        } else {
            for (NETunnelProviderManager *tunnelProviderManager in managers) {
                NETunnelProviderProtocol * pro = (NETunnelProviderProtocol *)tunnelProviderManager.protocolConfiguration;
                if ([pro.providerBundleIdentifier isEqualToString:EXTENSION_BUNDLE_ID]) {
                    self.manager = tunnelProviderManager;
                    [self startServer];
                    break;
                }
            }
        }
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NEVPNStatusDidChangeNotification object:self.manager.connection queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        [self updateVPNStatus];
    }];
}

#pragma --mark configureManager
- (void)configureManager {
    self.manager = [[NETunnelProviderManager alloc] init];
    NETunnelProviderProtocol * providerProtocol = [[NETunnelProviderProtocol alloc] init];
    providerProtocol.serverAddress = [NSString stringWithFormat:@"%@:%@", HOST,PORT];
    providerProtocol.providerBundleIdentifier = EXTENSION_BUNDLE_ID;
    self.manager.protocolConfiguration = providerProtocol;
    self.manager.localizedDescription = @"opentext vpn";
    [self.manager setEnabled:YES];

    [self.manager saveToPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"error: %@", error.localizedDescription);
        } else {
            NSLog(@"configure success......");
            [self.manager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"load error: %@", error.localizedDescription);
                    return;
                }
                [self startServer];
            }];
        }
    }];
}

- (void)startServer {
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    self.clientSockets = [[NSMutableArray alloc] initWithCapacity:1];
    NSError * error = nil;
    [self.socket acceptOnPort:[PORT intValue] error:&error];
    if (error) {
        NSLog(@"start vpn server error: %@", error.localizedDescription);
    } else {
        NSLog(@"start vpn server success......");
    }
}

- (void)stopServer {
    for (GCDAsyncSocket *sock in self.clientSockets) {
        [sock disconnectAfterWriting];
    }
    [self.socket disconnect];
    [self.socket setDelegate:nil];
    self.socket = nil;
    [self.clientSockets removeAllObjects];
}




/*
#pragma --mark UDP Server
- (void)startUDP {
    if (self.isRunning) {
        return;
    } else {
        self.udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
        NSError * error = nil;
        
        int port = [PORT intValue];
        if (![self.udpSocket bindToPort:port error:&error]) {
            NSLog(@"bind port error....");
            return;
        }
        if (![self.udpSocket beginReceiving:&error]) {
            NSLog(@"beginReceiving error...");
            return;
        }
        NSLog(@"jsp---- start udp server success !!!");
        self.isRunning = YES;
    }
}

- (void)stopUDP {
    for (GCDAsyncUdpSocket *sock in self.clientSockets) {
        [sock closeAfterSending];
    }
    [self.udpSocket close];
    self.isRunning = NO;
    [self.udpSocket setDelegate:nil];
    self.udpSocket = nil;
    [self.clientSockets removeAllObjects];
}
 */


#pragma --mark VPN
- (IBAction)switchVPN:(id)sender {
    UISwitch * sw = (UISwitch *)sender;
    if (sw.isOn) {
        [self startVPN];
    } else {
        [self stopVPN];
    }
}

- (void)startVPN {
    NSError * error = nil;
    [self.manager.connection startVPNTunnelAndReturnError:&error];
    if (error) {
        NSLog(@"error: %@", error.localizedDescription);
    } else {
        NSLog(@"start vpn success......");
    }
}

- (void)stopVPN {
    [self stopServer];
    [self.manager.connection stopVPNTunnel];
}



- (void)updateVPNStatus {
    switch (self.manager.connection.status) {
        case NEVPNStatusConnecting:
            NSLog(@"Connecting......");
            break;
        case NEVPNStatusConnected:
            NSLog(@"Connected......");
            break;
        case NEVPNStatusDisconnecting:
            NSLog(@"Disconnecting......");
            break;
        case NEVPNStatusDisconnected:
            NSLog(@"Disconnected......");
            break;
        case NEVPNStatusInvalid:
            NSLog(@"Invalid......");
            break;
        default:
            break;
    }
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


- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (self.clientSockets.count < 2) {
        [sock readDataWithTimeout:-1 tag:100];
    } else {
        GCDAsyncSocket * vpnSocket = self.clientSockets[0];
        GCDAsyncSocket * connectorSocket = self.clientSockets[1];
        if ([sock isEqual:vpnSocket]) {
            NSLog(@"%lu, receive from vpnSocket: %@", data.length, data);
            NSMutableArray * res = [self getCorrectPacket:data];
            for (NSData *obj in res) {
                [connectorSocket writeData:obj withTimeout:-1 tag:tag];
            }
            [sock readDataWithTimeout:-1 tag:100];
        } else {
            NSLog(@"%lu, receive from connectorSocket: %@", data.length, data);
            NSMutableArray * res = [self getCorrectPacket:data];
            for (NSData *obj in res) {
                [vpnSocket writeData:obj withTimeout:-1 tag:tag];
            }
            [sock readDataWithTimeout:-1 tag:100];
        }
    }
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

@end
