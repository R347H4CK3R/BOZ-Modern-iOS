#import <Foundation/Foundation.h>
#import "BOZWalletStore.h"
#define CHECK(x) do { if(!(x)) { NSLog(@"FAIL: %s",#x);return 1; } } while(0)
int main(void) { @autoreleasepool {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path=[root stringByAppendingPathComponent:@"Wallet/balance.plist"];
    int32_t value=0;NSError *error=nil;
    CHECK([BOZWalletStore loadAtPath:path balance:&value error:&error] && value==-1);
    for(NSNumber *n in @[@0,@1000,@750,@1000000]) {
        CHECK([BOZWalletStore saveBalance:n.intValue atPath:path error:&error]);
        value=-1;
        CHECK([BOZWalletStore loadAtPath:path balance:&value error:&error] && value==n.intValue);
        NSDictionary *raw=[NSDictionary dictionaryWithContentsOfFile:path];
        CHECK([raw[@"balance"] intValue]==n.intValue);
    }
    NSData *before=[NSData dataWithContentsOfFile:path];
    CHECK(![BOZWalletStore saveBalance:1000001 atPath:path error:&error]);
    CHECK([before isEqual:[NSData dataWithContentsOfFile:path]]);
    CHECK(![BOZWalletStore saveBalance:-1 atPath:path error:&error]);
    CHECK([before isEqual:[NSData dataWithContentsOfFile:path]]);
    [@{@"version":@1,@"balance":@(-5)} writeToFile:path atomically:YES];
    CHECK(![BOZWalletStore loadAtPath:path balance:&value error:&error]);
    [@{@"version":@1,@"balance":@1.5} writeToFile:path atomically:YES];
    CHECK(![BOZWalletStore loadAtPath:path balance:&value error:&error]);
    [@{@"version":@2,@"balance":@100} writeToFile:path atomically:YES];
    CHECK(![BOZWalletStore loadAtPath:path balance:&value error:&error]);
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    NSLog(@"PASS: wallet creation, reload after changes/spending, limits, rejected writes preserve old data, invalid wallet rejection");
    return 0;
} }
