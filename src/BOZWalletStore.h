#import <Foundation/Foundation.h>
@interface BOZWalletStore : NSObject
+ (BOOL)loadAtPath:(NSString *)path balance:(int32_t *)balance error:(NSError **)error;
+ (BOOL)saveBalance:(int32_t)balance atPath:(NSString *)path error:(NSError **)error;
@end
