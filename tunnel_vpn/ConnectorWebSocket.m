//
//  ConnectorWebSocket.m
//  tunnel_vpn
//
//  Created by Harris on 2023/11/22.
//

#import "ConnectorWebSocket.h"

@implementation ConnectorWebSocket

- (void)didOpen
{
    [super didOpen];
    
    [self sendMessage:@"Welcome to my WebSocket"];
}



- (void)didReceiveMessage:(NSString *)msg
{
    NSLog(@"jsp----- receive from connector: %@", msg);
//    [self sendMessage:@"jsp-----mywebsocket send message to client"];
    
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



@end
