//
//  MCUDPSession.h
//  tunnel_vpn
//
//  Created by Harris on 2023/8/11.
//

#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <NetworkExtension/NetworkExtension.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCUDPSession : NSObject
@property (nonatomic, strong) NWUDPSession * udpSession;
@property (nonatomic, strong) NSData * data;
@end

NS_ASSUME_NONNULL_END
