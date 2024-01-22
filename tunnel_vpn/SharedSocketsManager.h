//
//  SharedSocketsManager.h
//  tunnel_vpn
//
//  Created by Harris on 2023/11/27.
//

#import <Foundation/Foundation.h>
#import "MyWebSocket.h"


NS_ASSUME_NONNULL_BEGIN

@interface SharedSocketsManager : NSObject

@property(nonatomic, strong) MyWebSocket *myws;
@property(nonatomic, strong) NSMutableArray * socketClients;
@property(nonatomic, strong) NSMutableDictionary * portMap;
@property(nonatomic, strong) NSMutableDictionary * domainIPMap;


+ (SharedSocketsManager *)sharedInstance;
@end

NS_ASSUME_NONNULL_END
