#import "BOZWalletStore.h"
@implementation BOZWalletStore
+ (NSError *)invalid {
    return [NSError errorWithDomain:@"BOZFreeShop.Wallet" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The local wallet is invalid. No stored credits were overwritten."}];
}
+ (BOOL)loadAtPath:(NSString *)path balance:(int32_t *)balance error:(NSError **)error {
    if(![NSFileManager.defaultManager fileExistsAtPath:path]) { *balance=-1;return YES; }
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:error];
    if(!attrs) return NO;
    if(![attrs[NSFileType] isEqualToString:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue]>4096) {
        if(error) *error=[self invalid];return NO;
    }
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error];
    if(!data) return NO;
    id obj=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:error];
    if(![obj isKindOfClass:NSDictionary.class]) { if(error) *error=[self invalid];return NO; }
    id version=obj[@"version"],value=obj[@"balance"];
    if(![version isKindOfClass:NSNumber.class] || [version integerValue]!=1 || ![value isKindOfClass:NSNumber.class] || [value doubleValue] != [value longLongValue] || [value longLongValue]<0 || [value longLongValue]>1000000) {
        if(error) *error=[self invalid];return NO;
    }
    *balance=[value intValue];return YES;
}
+ (BOOL)saveBalance:(int32_t)balance atPath:(NSString *)path error:(NSError **)error {
    if(balance<0 || balance>1000000) { if(error) *error=[self invalid];return NO; }
    if(![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"balance":@(balance)} format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
@end
