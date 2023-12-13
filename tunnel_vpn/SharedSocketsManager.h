//
//  SharedSocketsManager.h
//  tunnel_vpn
//
//  Created by Harris on 2023/11/27.
//

#import <Foundation/Foundation.h>
#import "MyWebSocket.h"
#import "ConnectorWebSocket.h"

NS_ASSUME_NONNULL_BEGIN

@interface SharedSocketsManager : NSObject

@property(nonatomic, strong) MyWebSocket *myws;
@property(nonatomic, strong) ConnectorWebSocket * cws;

+ (SharedSocketsManager *)sharedInstance;

@end

NS_ASSUME_NONNULL_END