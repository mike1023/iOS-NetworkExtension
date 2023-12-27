//
//  ViewController.m
//  tunnel_vpn
//
//  Created by Harris on 2023/5/12.
//

#import "ViewController.h"
#import <NetworkExtension/NetworkExtension.h>
#import "HTTPServer.h"
#import "MyHTTPConnection.h"
#import "SRWebSocket.h"
#import "SharedSocketsManager.h"

#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"

#define EXTENSION_BUNDLE_ID @"com.opentext.harris.tunnel-vpn.tunnelVPN"
#define HOST @"127.0.0.1"
#define PORT @"12355"

static const char *QUEUE_NAME = "com.opentext.tunnel_vpn";

@interface ViewController ()<GCDAsyncSocketDelegate>
@property (nonatomic, strong) NETunnelProviderManager * manager;

//@property (nonatomic, strong) hpSRWebSocket * myWebSocket;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (nonatomic, strong) NSMutableArray<GCDAsyncSocket *> *clientSockets;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [SharedSocketsManager sharedInstance].socketClients = [NSMutableArray array];
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
                    //                    [self startWSServer];
                    [self startServer];
                    break;
                }
            }
        }
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NEVPNStatusDidChangeNotification object:self.manager.connection queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        [self updateVPNStatus];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NEVPNConfigurationChangeNotification object:self.manager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
        [self notifyConfiguteStatus];
    }];
}


#pragma --mark configureManager
- (void)configureManager {
    self.manager = [[NETunnelProviderManager alloc] init];
    NETunnelProviderProtocol * providerProtocol = [[NETunnelProviderProtocol alloc] init];
    providerProtocol.serverAddress = HOST;
    providerProtocol.providerBundleIdentifier = EXTENSION_BUNDLE_ID;
    providerProtocol.disconnectOnSleep = NO;
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
//                [self startWSServer];
                [self startServer];
            }];
        }
    }];
}
- (IBAction)startWS:(id)sender {
    [self startWSServer];
}

- (IBAction)sendToWSClient:(id)sender {
    [[SharedSocketsManager sharedInstance].myws sendConnectForSocket:nil];
}



- (void)startServer {
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    self.clientSockets = [[NSMutableArray alloc] initWithCapacity:1];
    NSError * error = nil;
    [self.socket acceptOnPort:[PORT intValue] error:&error];
    if (error) {
        NSLog(@"start TCP socket server error: %@", error.localizedDescription);
    } else {
        NSLog(@"start TCP socket server success......");
    }
}

- (void)startWSServer {
    self.httpServer = [[HTTPServer alloc] init];
    [self.httpServer setConnectionClass:[MyHTTPConnection class]];
    [self.httpServer setPort:23456];
    
    NSString *webPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Web"];
    [self.httpServer setDocumentRoot:webPath];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        if (![self.httpServer start:&error]) {
            NSLog(@"jsp--- %@", error);
        } else {
            NSLog(@"jsp----- start server success....");
        }
    });
}




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
    // get params from job
    NSDictionary * params = @{
        @"name": @"opop0.com",
        @"ip": @"10.168.80.187"
    };
    [SharedSocketsManager sharedInstance].remoteIP = params[@"ip"];
    [self.manager.connection startVPNTunnelWithOptions:params andReturnError:nil];
    if (error) {
        NSLog(@"error: %@", error.localizedDescription);
    } else {
        NSLog(@"start vpn success......");
    }
}

- (void)stopVPN {
    [self.manager.connection stopVPNTunnel];
//    if ([self.httpServer isRunning]) {
//        [self.httpServer stop];
//    }
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

- (void)notifyConfiguteStatus {
    
}

//#pragma mark ---websocket delegate
//- (void)webSocketDidOpen:(hpSRWebSocket *)webSocket {
//    NSLog(@"jsp----- webSocketDidOpen");
//}
//
//- (void)webSocket:(hpSRWebSocket *)webSocket didFailWithError:(NSError *)error {
//    NSLog(@"jsp------ fail: %@", error);
//}
//
//- (void)webSocket:(hpSRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
//    NSLog(@"jsp-------- close");
//}
//
//- (void)webSocket:(hpSRWebSocket *)webSocket didReceiveMessage:(id)message {
//    NSLog(@"jsp----- receive message: %@", message);
//}


//- (void)stopServer {
//    for (GCDAsyncSocket *sock in self.clientSockets) {
//        [sock disconnectAfterWriting];
//    }
//    [self.socket disconnect];
//    [self.socket setDelegate:nil];
//    self.socket = nil;
//    [self.clientSockets removeAllObjects];
//}

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

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"jsp----------%@ %d %@", sock, sock.connectedPort, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    if (data.length > 0) {
        [[SharedSocketsManager sharedInstance].myws sendPayload:data forSocket:sock];
        [sock readDataWithTimeout:-1 tag:tag];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    NSLog(@"jsp-----%@ new socket connect: %@ %d", sock, newSocket, newSocket.connectedPort);
    // This method is executed on the socketQueue (not the main thread)
    @synchronized(self.clientSockets) {
        [[SharedSocketsManager sharedInstance].socketClients addObject:newSocket];
        // when received a new socket client, we should send a 'connect' command to server.
        [[SharedSocketsManager sharedInstance].myws sendConnectForSocket:newSocket];
        [SharedSocketsManager sharedInstance].myws.receiveMessageHandler = ^(NSString *msg) {
            [newSocket readDataWithTimeout:-1 tag:0];
        };
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (err) {
        NSLog(@"%@ DidDisconnect, error: %@", sock, err.localizedDescription);
    } else {
        @synchronized(self.clientSockets) {
            [[SharedSocketsManager sharedInstance].socketClients removeObject:sock];
        }
    }
}



@end
