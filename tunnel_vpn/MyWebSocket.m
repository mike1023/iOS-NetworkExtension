#import "MyWebSocket.h"
#import "SharedSocketsManager.h"





@implementation MyWebSocket



- (void)didOpen
{
	
	[super didOpen];
	
//	[self sendMessage:@"Welcome to my WebSocket"];
}



- (void)didReceiveMessage:(NSString *)msg
{
    NSDictionary * dict;
    if (msg) {
        NSData * data = [msg dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
    }
    NSLog(@"jsp--- receive : ##### %@", msg);
    // websocker server that in device should send the message received from network extension to connector websocket
    NSString * s = [NSString stringWithFormat:@"device server ---> connector: %@", msg];
    [[SharedSocketsManager sharedInstance].cws sendMessage:s];
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
