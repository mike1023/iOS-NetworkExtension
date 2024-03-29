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
#import <SafariServices/SafariServices.h>
#import "GCDAsyncSocket.h"
#import "NSData+HexString.h"

#define EXTENSION_BUNDLE_ID @"com.opentext.harris.tunnel-vpn.tunnelVPN"
#define HOST @"127.0.0.1"
#define PORT @"12355"
#define HTTPSERVERPORT 23456

static const char *QUEUE_NAME = "com.opentext.tunnel_vpn";


@interface ViewController ()<GCDAsyncSocketDelegate>
@property (nonatomic, strong) NETunnelProviderManager * manager;
@property (nonatomic, strong) GCDAsyncSocket *socket;
@property (nonatomic, strong) dispatch_queue_t socketQueue;
@property (weak, nonatomic) IBOutlet UITextField *tf;
@property (nonatomic, assign) NSInteger clientID;
@property (nonatomic, strong) NSMutableArray * socketForMapArr;

@property (nonatomic, strong) NSMutableSet * randomIPSet;
@property (weak, nonatomic) IBOutlet UILabel *errLab;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.clientID = -1;
    self.socketForMapArr = [NSMutableArray array];
    self.tf.text = @"server002.uftmobile.admlabs.aws.swinfra.net:8080";

    [SharedSocketsManager sharedInstance].socketClients = [NSMutableArray array];
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    self.socketQueue = dispatch_queue_create(QUEUE_NAME, queueAttributes);
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> * _Nullable managers, NSError * _Nullable error) {
        if (error) {
            NSLog(@"load preferences error: %@", error);
            self.errLab.text = error.localizedFailureReason;
            return;
        }
        if (managers.count == 0) {
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


- (IBAction)removePreference:(id)sender {
    [self.manager removeFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"error...");
        } else {
            NSLog(@"1111");
        }
    }];
}

- (IBAction)requesstWeb:(id)sender {
    if (self.tf.text.length > 0) {
        NSString * text = [NSString stringWithFormat:@"http://%@", self.tf.text];
        NSURL * url = [NSURL URLWithString:text];
        SFSafariViewControllerConfiguration * config = [[SFSafariViewControllerConfiguration alloc] init];
        config.entersReaderIfAvailable = YES;
        SFSafariViewController * vc = [[SFSafariViewController alloc] initWithURL:url configuration:config];
        [self presentViewController:vc animated:YES completion:nil];
    }
}



- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
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
            self.errLab.text = @"22222222 saveToPreferences error";
        } else {
            NSLog(@"configure success......");
            [self.manager loadFromPreferencesWithCompletionHandler:^(NSError * _Nullable error) {
                if (error) {
                    NSLog(@"load error: %@", error.localizedDescription);
                    self.errLab.text = @"33333333 loadFromPreferences error";
                    return;
                }
                [self startServer];
            }];
        }
    }];
}
- (IBAction)startWS:(id)sender {
    if (self.httpServer.isRunning) {
        return;
    }
    [self startWSServer];
}

- (void)startServer {
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:self.socketQueue];
    NSError * error = nil;
    [self.socket acceptOnPort:[PORT intValue] error:&error];
    if (error) {
        NSLog(@"start TCP socket server error: %@", error.localizedDescription);
        return;
    } else {
        NSLog(@"start TCP socket server success......");
        [self startWSServer];
    }
}

- (void)startWSServer {
    self.httpServer = [[HTTPServer alloc] init];
    [self.httpServer setConnectionClass:[MyHTTPConnection class]];
    [self.httpServer setPort:HTTPSERVERPORT];
    
    NSString *webPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Web"];
    [self.httpServer setDocumentRoot:webPath];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        if (![self.httpServer start:&error]) {
            NSLog(@"jsp--- %@", error);
            return;
        } else {
            NSLog(@"jsp----- start server success....");
        }
    });
}

- (void)stopWSServer {
    if (self.httpServer.isRunning) {
        [self.httpServer stop];
    }
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
- (NSMutableDictionary *)generateRouteIPForDomain:(NSArray *)domainArr {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    self.randomIPSet = [NSMutableSet set];
    
    for (NSString *domain in domainArr) {
        NSString * randomIP = [self generateRandomIP];
        [dict setObject:randomIP forKey:domain];
    }
    return dict;
}
- (NSString *)generateRandomIP {
    // arc4random() % 11, return a number between [0, 10];
    // 10.0.0.0 ----- 10.10.10.9
    NSString * ipStr = [NSString stringWithFormat:@"10.%d.%d.%d", arc4random() % 11, arc4random() % 11, arc4random() % 10];
    while ([self.randomIPSet containsObject:ipStr]) {
        ipStr = [NSString stringWithFormat:@"10.%d.%d.%d", arc4random() % 11, arc4random() % 11, arc4random() % 10];
    }
    [self.randomIPSet addObject:ipStr];
    return ipStr;
}

- (void)startVPN {
    NSError * error = nil;
    NSArray * domains = @[@"server002.uftmobile.admlabs.aws.swinfra.net", @"www.opop90.com", @"www.opop80.com", @"www.baidu.com", @"www.163.com"];
    [SharedSocketsManager sharedInstance].domainIPMap = [self generateRouteIPForDomain:domains];
    [self.manager.connection startVPNTunnelWithOptions:[SharedSocketsManager sharedInstance].domainIPMap andReturnError:nil];
    if (error) {
        NSLog(@"error: %@", error.localizedDescription);
        self.errLab.text = @"4444444444 startVPNTunnelWithOptions error";
    } else {
        NSLog(@"start vpn success......");
    }
}

- (void)stopVPN {
    [self.manager.connection stopVPNTunnel];
    self.clientID = -1;

    [self stopServer];
    [self stopWSServer];
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


- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (tag == 101) {
        // message about port map
        if (data.length) {
            NSError *error = nil;
            NSDictionary *dictFromData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
            if (error) {
                NSLog(@"jsp---- port map error: %@", error);
            } else {
                [SharedSocketsManager sharedInstance].portMap = [NSMutableDictionary dictionaryWithDictionary:dictFromData];
                [sock readDataWithTimeout:-1 tag:101];
            }
        }
    } else {
        if (data.length > 0) {
            [[SharedSocketsManager sharedInstance].myws sendData:data withSocket:sock];
        }
        [SharedSocketsManager sharedInstance].myws.receiveDataHandler = ^(GCDAsyncSocket *socket) {
            [socket readDataWithTimeout:-1 tag:tag];
        };
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {

}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
//    NSLog(@"jsp-----%@ new socket connect: %@ %d %@", sock, newSocket, newSocket.connectedPort, newSocket.localHost);
    if (self.clientID == -1) {
        self.clientID += 1;
        @synchronized (self.socketForMapArr) {
            [self.socketForMapArr addObject:newSocket];
            [newSocket readDataWithTimeout:-1 tag:101];
        }
    } else {
        // This method is executed on the socketQueue (not the main thread)
        @synchronized([SharedSocketsManager sharedInstance].socketClients) {
            [[SharedSocketsManager sharedInstance].socketClients addObject:newSocket];
            // when received a new socket client, we should send a 'connect' command to server.
            [[SharedSocketsManager sharedInstance].myws sendData:nil withSocket:newSocket];
            [SharedSocketsManager sharedInstance].myws.connectionResponseHandler = ^(GCDAsyncSocket *socket) {
//                NSLog(@"jsp----------connectionResponseHandler");
                [socket readDataWithTimeout:-1 tag:0];
            };
        }
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if (err) {
        NSLog(@"%@ DidDisconnect, error: %@", sock, err.localizedDescription);
    } else {
        @synchronized([SharedSocketsManager sharedInstance].socketClients) {
            [[SharedSocketsManager sharedInstance].socketClients removeObject:sock];
        }
    }
}



- (void)stopServer {
    for (GCDAsyncSocket *sock in self.socketForMapArr) {
        [sock disconnectAfterWriting];
    }
    [self.socket disconnect];
    [self.socket setDelegate:nil];
    self.socket = nil;
    [self.socketForMapArr removeAllObjects];
    
    [self stopWSServer];
    
    [[SharedSocketsManager sharedInstance].socketClients removeAllObjects];
    [[SharedSocketsManager sharedInstance].portMap removeAllObjects];
}

@end
