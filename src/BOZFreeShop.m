#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import <stdint.h>
#import <string.h>
#import <fcntl.h>
#import <unistd.h>
#import "BOZWalletStore.h"

// Only the SHA-pinned 1.3.5 ARM64 game used by Loader Fix v5 is supported.
static uintptr_t gBase;
static IMP gShow;
static _Atomic(int) gPending, gBalance, gReady;
static UIButton *gButton;
static unsigned gReadyFrames;
static dispatch_queue_t gWalletQueue;
static NSString *gWalletPath;
static _Atomic(int) gWalletLoaded,gStoredBalance;
static BOOL gWalletRestored;
static int32_t gLastBalance;

static BOOL ReadMemory(uintptr_t address, void *out, size_t size) {
    _Static_assert(sizeof(vm_address_t)>=sizeof(uintptr_t),"ARM64 VM addresses required");
    vm_size_t read=0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address, size,
        (vm_address_t)out, &read)==KERN_SUCCESS && read==size;
}
static NSString *Documents(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
}
static void ShopLog(NSString *message) {
    @autoreleasepool {
        NSString *folder=[Documents() stringByAppendingPathComponent:@"BOZDiagnostics"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *path=[folder stringByAppendingPathComponent:@"shop.log"];
        NSData *line=[[NSString stringWithFormat:@"%@ %@\n",NSDate.date,message] dataUsingEncoding:NSUTF8StringEncoding];
        if(![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:YES];
        NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
        @try { [file seekToEndOfFile]; [file writeData:line]; [file synchronizeFile]; [file closeFile]; }
        @catch(NSException *exception) { NSLog(@"[BOZFreeShop] %@",message); }
        // The existing report uploader reads session.log. Only our own status
        // events are appended, never wallet contents or unrelated files.
        int fd=open([[folder stringByAppendingPathComponent:@"session.log"] fileSystemRepresentation],O_WRONLY|O_APPEND);
        if(fd>=0) { write(fd,line.bytes,line.length);close(fd); }
    }
}
static UIWindow *GameWindow(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive) {
            for(UIWindow *window in ((UIWindowScene *)scene).windows)
                if(window.isKeyWindow && !window.hidden) return window;
        }
    }
    // Marmalade can create a legacy UIWindow outside the host's scene list.
    for(UIWindow *window in UIApplication.sharedApplication.windows)
        if(window.isKeyWindow && !window.hidden) return window;
    return nil;
}
static void Alert(NSString *title,NSString *text) {
    NSCAssert(NSThread.isMainThread,@"Shop UI must use main thread");
    UIViewController *controller=GameWindow().rootViewController;
    while(controller.presentedViewController) controller=controller.presentedViewController;
    if(!controller || [controller isKindOfClass:UIAlertController.class]) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
static BOOL Store(uintptr_t *object,int32_t *balance) {
    uintptr_t pointer=0,vtable=0;
    if(!gBase || !ReadMemory(gBase+0x642fd8,&pointer,sizeof(pointer)) || !pointer) return NO;
    if(!ReadMemory(pointer,&vtable,sizeof(vtable)) || vtable!=gBase+0x5be8d8) return NO;
    if(!ReadMemory(pointer+0x20,balance,sizeof(*balance)) || *balance<0) return NO;
    *object=pointer; return YES;
}
static BOOL SetBalance(uintptr_t object,int32_t balance) {
    if(balance<0 || balance>1000000) return NO;
    kern_return_t status=vm_write(mach_task_self(),(vm_address_t)(object+0x20),(vm_offset_t)&balance,sizeof(balance));
    uintptr_t current=0;int32_t after=0;
    return status==KERN_SUCCESS && Store(&current,&after) && current==object && after==balance;
}
static void SaveWallet(int32_t balance,BOOL notify) {
    dispatch_async(gWalletQueue,^{ @autoreleasepool {
        NSError *error=nil;
        BOOL saved=[BOZWalletStore saveBalance:balance atPath:gWalletPath error:&error];
        ShopLog([NSString stringWithFormat:@"wallet-save balance=%d success=%d",balance,saved]);
        if(notify) {
            NSString *message=saved ? [NSString stringWithFormat:@"Local balance: %d\nSaved in the add-on wallet. Keep this add-on enabled to restore it after restarting.",balance] : @"The balance changed, but the local wallet could not be saved. Keep the game open and send the diagnostic report.";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ Alert(@"Free Shop",message); });
        }
    } });
}
static BOOL BackupSaves(void) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *documents=Documents();
    if(!documents) return NO;
    NSString *backup=[documents stringByAppendingPathComponent:[@"BOZShopBackups" stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSError *error=nil;
    if(![fm createDirectoryAtPath:backup withIntermediateDirectories:YES attributes:nil error:&error]) return NO;
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:documents];
    NSString *relative;
    while((relative=enumerator.nextObject)) {
        if([relative hasPrefix:@"BOZShopBackups"] || [relative hasPrefix:@"BOZDiagnostics"]) { [enumerator skipDescendants];continue; }
        if(![relative.pathExtension.lowercaseString isEqualToString:@"i3d"]) continue;
        NSString *from=[documents stringByAppendingPathComponent:relative];
        NSDictionary *attributes=[fm attributesOfItemAtPath:from error:&error];
        // Never follow symlinks or copy game assets as part of a wallet backup.
        if(![attributes[NSFileType] isEqualToString:NSFileTypeRegular] || [attributes[NSFileSize] unsignedLongLongValue]>4*1024*1024) return NO;
        NSString *to=[backup stringByAppendingPathComponent:relative];
        if(![fm createDirectoryAtPath:to.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error] || ![fm copyItemAtPath:from toPath:to error:&error]) return NO;
    }
    ShopLog(@"backup=created");return YES;
}
static void ShopFrame(id self,SEL selector) {
    ((void (*)(id,SEL))gShow)(self,selector);
    if(atomic_load(&gWalletLoaded)!=1) return;
    int amount=atomic_exchange(&gPending,0);
    uintptr_t object=0;int32_t before=0;
    BOOL ready=Store(&object,&before);
    if(!gWalletRestored && ready && ++gReadyFrames<120) { atomic_store(&gReady,0);return; }
    if(ready && !gWalletRestored) {
        int stored=atomic_load(&gStoredBalance);
        if(stored>=0 && stored!=before) {
            ready=SetBalance(object,stored);
            ShopLog([NSString stringWithFormat:@"wallet-restore balance=%d success=%d",stored,ready]);
            if(ready) before=stored;
        }
        if(ready) { gWalletRestored=YES;gLastBalance=before;if(stored<0) SaveWallet(before,NO); }
    }
    atomic_store(&gReady,ready); if(ready) {
        atomic_store(&gBalance,before);
        if(gWalletRestored && gLastBalance!=before) { gLastBalance=before;SaveWallet(before,NO); }
    }
    if(!amount) return;
    @autoreleasepool {
        NSString *message;
        if(!ready) message=@"The game store is not ready. Return to the main menu and try again.";
        else if(amount<=0 || amount>10000 || before>1000000-amount) message=@"The local credit limit is 1,000,000. No credits were changed.";
        else if(!BackupSaves()) message=@"Could not back up the save files. No credits were changed.";
        else {
            int32_t after=before+amount;
            ShopLog([NSString stringWithFormat:@"grant-write enter amount=%d before=%d",amount,before]);
            BOOL valid=SetBalance(object,after);
            ShopLog([NSString stringWithFormat:@"grant-write return after=%d success=%d",after,valid]);
            if(valid) { atomic_store(&gBalance,after);gLastBalance=after;SaveWallet(after,YES);return; }
            message=@"The balance could not be updated. Send the diagnostic report before trying again.";
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ Alert(@"Free Shop",message); });
    }
}

@interface BOZFreeShop : NSObject
+ (void)open;
@end
@implementation BOZFreeShop
+ (void)open {
    UIViewController *controller=GameWindow().rootViewController;
    while(controller.presentedViewController) controller=controller.presentedViewController;
    if(!controller || [controller isKindOfClass:UIAlertController.class]) return;
    if(atomic_load(&gWalletLoaded)==-1) { Alert(@"Free Shop",@"The saved add-on wallet could not be read. Send the diagnostic report. Existing wallet data was not overwritten.");return; }
    if(!atomic_load(&gReady)) { Alert(@"Free Shop",@"Wait for the main menu to finish loading. If the old shop says Accessing Store, cancel it first.");return; }
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Free Shop" message:[NSString stringWithFormat:@"Local balance: %d\nChoose a free credit grant. No App Store checkout is used.",atomic_load(&gBalance)] preferredStyle:UIAlertControllerStyleAlert];
    for(NSNumber *number in @[@1000,@10000]) {
        int amount=number.intValue;
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Add %@ Credits",number] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            int expected=0;
            if(!atomic_compare_exchange_strong(&gPending,&expected,amount)) ShopLog(@"grant=ignored-already-pending");
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:menu animated:YES completion:nil];
}
@end

static void Install(void) {
    if(!gBase) {
        Method accessor=class_getInstanceMethod(objc_getClass("s3eAppDelegate"),sel_registerName("m_View"));
        Dl_info info={0};
        if(!accessor || !dladdr((void *)method_getImplementation(accessor),&info) || !info.dli_fbase) return;
        uintptr_t base=(uintptr_t)info.dli_fbase;
        uint32_t expected[]={0xb9402002,0x2b010041,0x1a9f5021,0xb9002001,0x52800001,0x17ffff4e};
        uint32_t actual[6];
        if(!ReadMemory(base+0x1d7434,actual,sizeof(actual)) || memcmp(actual,expected,sizeof(actual))) return;
        Method show=class_getInstanceMethod(objc_getClass("GLView"),sel_registerName("show"));
        if(!show) return;
        gBase=base;gShow=method_getImplementation(show);
        method_setImplementation(show,(IMP)ShopFrame);
        ShopLog(@"free-shop=v2 installed supported-guest=1 native-save-call=disabled");
    }
    UIWindow *window=GameWindow();if(!window) return;
    if(!gButton) {
        gButton=[UIButton buttonWithType:UIButtonTypeSystem];
        [gButton setTitle:@"Free Shop" forState:UIControlStateNormal];
        [gButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        gButton.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.75];
        gButton.layer.cornerRadius=9;
        gButton.titleLabel.font=[UIFont boldSystemFontOfSize:16];
        [gButton addTarget:BOZFreeShop.class action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        gButton.accessibilityLabel=@"Open offline free credit shop";
    }
    if(gButton.superview!=window) [window addSubview:gButton];
    UIEdgeInsets safe=window.safeAreaInsets;
    gButton.frame=CGRectMake(safe.left+12,safe.top+12,110,42);
    [window bringSubviewToFront:gButton];
}
__attribute__((constructor)) static void StartFreeShop(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        gWalletQueue=dispatch_queue_create("dev.boz.free-shop.wallet",DISPATCH_QUEUE_SERIAL);
        gWalletPath=[Documents() stringByAppendingPathComponent:@"BOZFreeShop/wallet.plist"];
        dispatch_async(gWalletQueue,^{ @autoreleasepool {
            int32_t stored=-1;NSError *error=nil;
            BOOL valid=gWalletPath && [BOZWalletStore loadAtPath:gWalletPath balance:&stored error:&error];
            atomic_store(&gStoredBalance,stored);
            atomic_store(&gWalletLoaded,valid?1:-1);
            ShopLog([NSString stringWithFormat:@"wallet-load valid=%d stored=%d",valid,stored]);
        } });
        Install();
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){ Install(); }];
    });
}
