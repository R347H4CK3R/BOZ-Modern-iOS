#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <stdatomic.h>
#import <stdint.h>
#import <string.h>

// Only the SHA-pinned 1.3.5 ARM64 game used by Loader Fix v5 is supported.
static uintptr_t gBase;
static IMP gShow;
static _Atomic(int) gPending, gBalance, gReady;
static UIButton *gButton;
static unsigned gFrames;

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
    int amount=atomic_exchange(&gPending,0);
    if(!amount && (++gFrames%60)!=0) return;
    uintptr_t object=0;int32_t before=0;
    BOOL ready=Store(&object,&before);
    atomic_store(&gReady,ready); if(ready) atomic_store(&gBalance,before);
    if(!amount) return;
    @autoreleasepool {
        NSString *message;
        if(!ready) message=@"The game store is not ready. Return to the main menu and try again.";
        else if(amount<=0 || amount>10000 || before>1000000-amount) message=@"The local credit limit is 1,000,000. No credits were changed.";
        else if(!BackupSaves()) message=@"Could not back up the save files. No credits were changed.";
        else {
            // Executed from the game's GLView.show path, never from UIKit's timer.
            int (*addCredits)(void *,int32_t)=(void *)(gBase+0x1d7434);
            int status=addCredits((void *)object,amount);
            int32_t after=0;uintptr_t current=0;
            BOOL valid=Store(&current,&after) && current==object && after==before+amount;
            if(valid) atomic_store(&gBalance,after);
            ShopLog([NSString stringWithFormat:@"grant=%d before=%d after=%d save-status=%d verified=%d thread-main=%d",amount,before,after,status,valid,NSThread.isMainThread]);
            if(valid && status==0) message=[NSString stringWithFormat:@"Added %d credits.\nBalance: %d\n\nThe game reported a successful save. Restart the game to confirm the balance persists.",amount,after];
            else message=@"The credit/save check did not complete successfully. See BOZDiagnostics/shop.log before trying again.";
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
        ShopLog(@"free-shop=v1 installed supported-guest=1");
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
        Install();
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){ Install(); }];
    });
}
