//
//  IPPacket.m
//  INetworkPacketParser
//
//  Created by smallyou on 2019/3/12.
//



#define _IP_VHL
#ifndef __IPPacket_Header_
#define __IPPacket_Header_

#include <netinet/ip.h>
#include <arpa/inet.h>

#import "IPPacket.h"
#import "IPConstant.h"
#import "NSData+HexString.h"


#endif

@interface IPPacket ()

@property (nonatomic, strong) NSData *rawData;
@property (nonatomic, strong) IPHeader *header;
@property (nonatomic, strong) NSData   *payload;

@end

@implementation IPPacket

- (instancetype)initWithRawData:(NSData *)rawData {
    if (self = [super init]) {
        self.rawData = rawData;
        
        // auto parse
        NSError *error = nil;
        BOOL flag = [self parse:&error];
        if (!flag) {
            NSLog(@"IP packet parse error: %@", error);
        }
    }
    return self;
}


// parse ip header and payload
- (BOOL)parse:(NSError **)error {
    
    NSData *data = self.rawData;
    const Byte *bytes = (Byte *)data.bytes;
    if (data == nil) {
        NSError *err = [NSError errorWithDomain:IPErrorDomainName code:IPErrorCodeFormatError userInfo:@{NSLocalizedDescriptionKey:@"IP packet rawdata is not exist"}];
        *error = err;
        return NO;
    }
    
    // first byte
    Byte firstByte = bytes[0];
    //(vhl) & 0x0f IP_VHL_HL
    // (vhl) >> 4 IP_VHL_V
    UInt8 ihl     = (firstByte) & 0x0f;         // 获取IP报文头部长度 单位32bit
    UInt8 version = (firstByte) >> 4;          // 获取版本号
    if (version == 6) {
        // unsupport ipv6
        NSError *err = [NSError errorWithDomain:IPErrorDomainName code:IPErrorCodeUnsupport userInfo:@{NSLocalizedDescriptionKey: @"unsupport ipv6"}];
        *error = err;
        return NO;
    }
    
    struct ip header;
    memcpy(&header, bytes, ihl * 32 / 8);
    
    // parse header
    self.header.version = (version == 4)?iPv4:iPv6;
    self.header.headerLength = ihl * 32 / 8;      // 转换成字节
    self.header.tos  = (UInt8)header.ip_tos;
    self.header.totalLength = NTOHS(header.ip_len);
    self.header.identification = NTOHS(header.ip_id);
    self.header.offset = NTOHS(header.ip_off);
    self.header.TTL = (UInt8)header.ip_ttl;
    self.header.sourceAddress = [NSString stringWithFormat:@"%s", inet_ntoa(header.ip_src)];
    self.header.destinationAddress = [NSString stringWithFormat:@"%s", inet_ntoa(header.ip_dst)];
    self.header.transportProtocol  = header.ip_p;
    
    // parse payload
    UInt8 offset = ihl * 32 / 8;
    
    //get source port
    NSData * sourcePortData = [data subdataWithRange:NSMakeRange(offset, 2)];
    NSLog(@"source port: %@", [sourcePortData hexString]);
    unsigned source = 0;
    NSScanner *sourceScanner = [NSScanner scannerWithString:[sourcePortData hexString]];
    [sourceScanner scanHexInt:&source];
    self.sourcePort = source;
    
    // get destination port
    NSData * desPortData = [data subdataWithRange:NSMakeRange(offset + 2, 2)];
    NSLog(@"des port: %@", [desPortData hexString]);
    unsigned des = 0;
    NSScanner *desScanner = [NSScanner scannerWithString:[desPortData hexString]];
    [desScanner scanHexInt:&des];
    self.destinationPort = des;
    
    bytes+=offset;
    NSInteger length = self.header.totalLength - offset;
    if (length <= 0) {
        NSError *err = [NSError errorWithDomain:IPErrorDomainName code:IPErrorCodeFormatError userInfo:@{NSLocalizedDescriptionKey: @"packet format error: payload does not exist"}];
        *error = err;
        return NO;
    }
    NSData *payload = [NSData dataWithBytes:bytes length:length];
    self.payload = payload;
    
    return YES;
}

// todo
- (NSData *)toRawData {
    return nil;
}


- (IPHeader *)header {
    if (_header == nil) {
        _header = [[IPHeader alloc] init];
    }
    return _header;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"\
            \n========IPPacket Info========\n \
            header {\n\
            version: %d\n \
            headerLength: %hhu\n \
            tos: %hhu\n \
            totalLength: %hu\n \
            identification: %hu\n \
            offset: %hu\n \
            TTL: %hhu\n \
            sourceAddress: %@\n \
            destinationAddress: %@\n \
            transportProtocol: %d (icmp:1, tcp:6, udp:17)\n \
            }\n\
            rawData :%@", self.header.version,
            self.header.headerLength,
            self.header.tos,
            self.header.totalLength,
            self.header.identification,
            self.header.offset,
            self.header.TTL,
            self.header.sourceAddress,
            self.header.destinationAddress,
            self.header.transportProtocol,
            self.rawData
            ];
}


@end


@implementation IPHeader


@end
