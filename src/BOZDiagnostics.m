#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/ucontext.h>
#import <mach/arm/thread_status.h>

static NSString *BOZLogPath;
static NSString *BOZCrashPath;
static int BOZCrashFD = -1;
static NSUncaughtExceptionHandler *BOZPreviousException;
static BOOL BOZUploading;
static NSString *const BOZRepo = @"R347H4CK3R/BOZ-Modern-iOS";
static NSString *const BOZTokenService = @"BOZ.PrivateDiagnostics";

void BOZDiagnosticLog(NSString *message) {
    if (!BOZLogPath) return;
    @synchronized (BOZLogPath) {
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date.description, message];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:BOZLogPath];
        @try { [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
        @catch (__unused NSException *e) {}
        @finally { [file closeFile]; }
    }
}

static NSMutableDictionary *BOZKeyQuery(void) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:BOZTokenService,
              (__bridge id)kSecAttrAccount:@"github-issues"} mutableCopy];
}
static NSString *BOZToken(void) {
    NSMutableDictionary *q = BOZKeyQuery();
    q[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef value = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &value) != errSecSuccess) return nil;
    return [[NSString alloc] initWithData:CFBridgingRelease(value) encoding:NSUTF8StringEncoding];
}
static OSStatus BOZSaveToken(NSString *token) {
    NSMutableDictionary *q = BOZKeyQuery();
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)q,
        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status != errSecItemNotFound) return status;
    q[(__bridge id)kSecValueData] = data;
    q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)q, NULL);
}

// Only async-signal-safe operations here. The OS retains the native crash report.
static struct sigaction BOZPreviousSignals[NSIG];
static void BOZHex(int fd, const char *label, size_t length, uint64_t value) {
    char buffer[18]; buffer[0]='0'; buffer[1]='x';
    const char hex[]="0123456789abcdef";
    for(int i=0;i<16;i++)buffer[2+i]=hex[(value>>((15-i)*4))&15];
    write(fd,label,length);write(fd,buffer,sizeof(buffer));write(fd,"\n",1);
}
static void BOZSignal(int sig, siginfo_t *info, void *context) {
    if (BOZCrashFD>=0) {
        BOZHex(BOZCrashFD,"signal=",7,(uint64_t)sig);
        if(info)BOZHex(BOZCrashFD,"fault=",6,(uintptr_t)info->si_addr);
        ucontext_t *uc=(ucontext_t *)context;
        if(uc && uc->uc_mcontext){
            BOZHex(BOZCrashFD,"pc=",3,arm_thread_state64_get_pc(uc->uc_mcontext->__ss));
            BOZHex(BOZCrashFD,"lr=",3,arm_thread_state64_get_lr(uc->uc_mcontext->__ss));
        }
        fsync(BOZCrashFD);
    }
    sigaction(sig,&BOZPreviousSignals[sig],NULL);
    kill(getpid(),sig);
}
static void BOZException(NSException *exception) {
    // Record exception type only: reasons and stacks can contain private paths.
    BOZDiagnosticLog([@"uncaught-exception=" stringByAppendingString:exception.name ?: @"unknown"]);
    if (BOZCrashFD >= 0) { const char marker[] = "uncaught-exception\n"; write(BOZCrashFD, marker, sizeof(marker)-1); fsync(BOZCrashFD); }
    if (BOZPreviousException) BOZPreviousException(exception);
}

static UIViewController *BOZPresenter(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) window = candidate;
        }
    }
    if (!window) for (UIWindow *candidate in UIApplication.sharedApplication.windows) if (candidate.isKeyWindow) window = candidate;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
static void BOZAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [BOZPresenter() presentViewController:a animated:YES completion:nil];
    });
}
static void BOZUpload(NSString *path, BOOL showResult) {
    NSString *token = BOZToken();
    if (token.length == 0) { if (showResult) BOZAlert(@"Reporting is not connected", @"Open Logs → Connect GitHub. Logs remain on this iPhone."); return; }
    if (BOZUploading) return;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return;
    // Reports contain only this diagnostic module's allowlisted events.
    if (data.length > 16000) data = [data subdataWithRange:NSMakeRange(data.length-16000,16000)];
    NSString *log = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"Log encoding unavailable";
    NSString *body = [NSString stringWithFormat:@"Automatic BOZ diagnostic report. No native crash stack is included.\n\n```text\n%@\n```", log];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/issues",BOZRepo]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 30;
    [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"title":@"[BOZ Diagnostics] iPhone runtime report",@"body":body} options:0 error:nil];
    BOZUploading = YES;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *result, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOZUploading = NO;
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (!error && status == 201) {
                if (![path isEqualToString:BOZLogPath]) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
                BOZDiagnosticLog(@"repository-report=accepted");
                if (showResult) BOZAlert(@"Report sent", @"The diagnostic report is in the private BOZ-Modern-iOS repository's Issues tab.");
            } else {
                BOZDiagnosticLog([NSString stringWithFormat:@"repository-report=failed HTTP=%ld network=%ld", (long)status, (long)error.code]);
                if (showResult) BOZAlert(@"Report retained locally", @"Check your connection and token access. GitHub must grant this token Issues: Read and write for BOZ-Modern-iOS.");
            }
        });
    }] resume];
}

@interface BOZDiagnosticsController : NSObject
+ (void)showMenu;
@end
@implementation BOZDiagnosticsController
+ (void)showMenu {
    UIViewController *vc = BOZPresenter();
    if (!vc) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"BOZ Diagnostics" message:@"Logs stay on your iPhone until reporting is connected. Crash markers upload on the next launch. Native iOS .ips reports must be shared separately." preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:@"Connect GitHub" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Connect private repository" message:@"Enter a fine-grained GitHub token for R347H4CK3R/BOZ-Modern-iOS with Issues: Read and write. It is stored in this device's Keychain and never included in logs." preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *field) { field.secureTextEntry=YES; field.autocorrectionType=UITextAutocorrectionTypeNo; field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.placeholder=@"Fine-grained token"; }];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Save and send test log" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action2) {
            NSString *token = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!token.length) return;
            if (BOZSaveToken(token) != errSecSuccess) { BOZAlert(@"Token was not saved", @"Keychain access failed. The token has not been written to a file."); return; }
            BOZUpload(BOZLogPath, YES);
        }]];
        [BOZPresenter() presentViewController:a animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Send current log" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { BOZUpload(BOZLogPath, YES); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Share local log" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:BOZLogPath]] applicationActivities:nil];
        UIViewController *presenter=BOZPresenter();
        share.popoverPresentationController.sourceView=presenter.view;
        share.popoverPresentationController.sourceRect=CGRectMake(20,20,1,1);
        [presenter presentViewController:share animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Disconnect GitHub" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { SecItemDelete((__bridge CFDictionaryRef)BOZKeyQuery()); }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:menu animated:YES completion:nil];
}
@end

static void BOZInstallLogButton(void) {
    UIViewController *vc=BOZPresenter();
    if (!vc || [vc.view viewWithTag:734215]) return;
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.tag=734215;
    [button setTitle:@"Logs" forState:UIControlStateNormal];
    button.backgroundColor=[UIColor colorWithWhite:0 alpha:0.65];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.layer.cornerRadius=8;
    button.translatesAutoresizingMaskIntoConstraints=NO;
    [button addTarget:BOZDiagnosticsController.class action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[[button.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-8],[button.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:8],[button.widthAnchor constraintEqualToConstant:52],[button.heightAnchor constraintEqualToConstant:32]]];
    BOZDiagnosticLog(@"diagnostic-button=ready");
}

__attribute__((constructor)) static void BOZDiagnosticsStart(void) {
    @autoreleasepool {
        NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSString *dir=[docs stringByAppendingPathComponent:@"BOZDiagnostics"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
        BOZLogPath=[dir stringByAppendingPathComponent:@"session.log"];
        BOZCrashPath=[dir stringByAppendingPathComponent:@"crash.marker"];
        NSString *marker=[NSString stringWithContentsOfFile:BOZCrashPath encoding:NSUTF8StringEncoding error:nil];
        NSString *lastSession=[NSString stringWithContentsOfFile:BOZLogPath encoding:NSUTF8StringEncoding error:nil];
        if (lastSession.length) [lastSession writeToFile:[dir stringByAppendingPathComponent:@"previous-session.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (marker.length) {
            NSString *previous=[NSString stringWithContentsOfFile:BOZLogPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
            NSString *pending=[dir stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"pending.log"]];
            [[previous stringByAppendingString:marker] writeToFile:pending atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [@"" writeToFile:BOZLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        BOZCrashFD=open(BOZCrashPath.fileSystemRepresentation,O_CREAT|O_WRONLY|O_TRUNC,0600);
        BOZPreviousException=NSGetUncaughtExceptionHandler(); NSSetUncaughtExceptionHandler(BOZException);
        int signals[]={SIGABRT,SIGSEGV,SIGBUS,SIGILL,SIGFPE};
        for (unsigned i=0;i<sizeof(signals)/sizeof(signals[0]);i++) {
            struct sigaction action={0}; action.sa_sigaction=BOZSignal;
            sigemptyset(&action.sa_mask);action.sa_flags=SA_SIGINFO;
            sigaction(signals[i],&action,&BOZPreviousSignals[signals[i]]);
        }
        BOZDiagnosticLog([NSString stringWithFormat:@"diagnostics=v2 iOS=%@ ARM64 guest-image-fix=enabled",UIDevice.currentDevice.systemVersion]);
        NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            BOZDiagnosticLog(@"lifecycle=active");

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ BOZInstallLogButton();
                for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) if ([file hasSuffix:@".pending.log"]) { BOZUpload([dir stringByAppendingPathComponent:file],NO); break; }
            });
        }];
        [nc addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { BOZDiagnosticLog(@"lifecycle=memory-warning"); }];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { BOZDiagnosticLog(@"lifecycle=background"); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,4*NSEC_PER_SEC),dispatch_get_main_queue(),^{ BOZInstallLogButton(); });
    }
}
