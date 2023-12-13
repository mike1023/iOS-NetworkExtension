//
//  SharedSocketsManager.m
//  tunnel_vpn
//
//  Created by Harris on 2023/11/27.
//

#import "SharedSocketsManager.h"

@implementation SharedSocketsManager


+ (SharedSocketsManager *)sharedInstance {
    static SharedSocketsManager * sharedSocketsManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSocketsManager = [[SharedSocketsManager alloc] init];
    });
    return sharedSocketsManager;
}

@end
