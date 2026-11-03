#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <pthread.h>
#import <stdatomic.h>
#import <math.h>
#import <fcntl.h>
#import <unistd.h>
#import "BOZControlsBridge.h"

static uintptr_t B;
static IMP OriginalShow;
static _Atomic(uintptr_t) EngineThread;
static _Atomic(unsigned) Requested;
static _Atomic(int) Enabled,Active,Editing,InputReady,Gameplay,ProfileDirty,YieldInstalled;
static unsigned Sent;
static uintptr_t LastManager;
static _Atomic(float) Sensitivity=0.60f;
static _Atomic(int) InsideYield;
static UIView *Overlay;
static UIButton *MenuButton;
static NSMutableArray<UIButton *> *Buttons;
static NSString *const Pref=@"BOZ.TouchControls.";

static BOOL Read(uintptr_t address,void *out,size_t size) {
    vm_size_t count=0;
    return vm_read_overwrite(mach_task_self(),address,size,(vm_address_t)out,&count)==KERN_SUCCESS && count==size;
}
static BOOL Write(uintptr_t address,const void *value,size_t size) {
    return vm_write(mach_task_self(),address,(vm_offset_t)value,(mach_msg_type_number_t)size)==KERN_SUCCESS;
}
static void Log(NSString *message) {
    NSString *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    if(!docs) return;
    NSString *folder=[docs stringByAppendingPathComponent:@"BOZDiagnostics"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *line=[[NSString stringWithFormat:@"%@ controls-v2 %@\n",NSDate.date,message] dataUsingEncoding:NSUTF8StringEncoding];
    for(NSString *name in @[@"controls.log",@"session.log"]) {
        int fd=open([[folder stringByAppendingPathComponent:name] fileSystemRepresentation],O_WRONLY|O_APPEND|O_CREAT,0600);
        if(fd>=0) { write(fd,line.bytes,line.length);close(fd); }
    }
}
static UIWindow *Window(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive)
            for(UIWindow *window in ((UIWindowScene *)scene).windows) if(window.isKeyWindow&&!window.hidden) return window;
    for(UIWindow *window in UIApplication.sharedApplication.windows) if(window.isKeyWindow&&!window.hidden) return window;
    return nil;
}
static UIViewController *Presenter(void) {
    UIViewController *vc=Window().rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    return vc;
}
static BOOL Manager(uintptr_t *manager) {
    uintptr_t p=0,v=0;
    if(!B || !Read(B+0x644bd0,&p,8) || !p || !Read(p,&v,8) || v!=B+0x5e5d90) return NO;
    *manager=p;return YES;
}
static BOOL InGame(void) {
    uintptr_t client=0,player=0,vtable=0;
    if(!Read(B+0x637218,&client,8) || !client || !Read(client+0x1f0,&player,8) || !player || !Read(player,&vtable,8) || !vtable) return NO;
    // CIwGameStateManager: the native activate/deactivate routines maintain
    // an array of state-name pointers at +0xa0, with its count at +0xa8.
    uintptr_t states=0,names=0;uint32_t count=0;unsigned flags=0;
    if(!Read(B+0x637230,&states,8) || !states || !Read(states+0xa0,&names,8) || !Read(states+0xa8,&count,4) || !names || count>64) return NO;
    for(uint32_t i=0;i<count;i++) {
        uintptr_t name=0;char value[32]={0};
        if(!Read(names+i*8,&name,8) || !name || !Read(name,value,sizeof(value)-1)) return NO;
        flags|=BOZControlsStateFlag(value);
    }
    return BOZControlsStatesPlayable(flags);
}
static BOOL ApplyProfile(void) {
    uintptr_t config=0;int16_t mode=-1;float xy[2]={0};
    if(!Read(B+0x637228,&config,8) || !config || !Read(config+0x12e,&mode,2) || mode<0 || mode>2 || !Read(config+0x124,xy,8) || !isfinite(xy[0]) || !isfinite(xy[1]) || xy[0]<0 || xy[0]>1 || xy[1]<0 || xy[1]>1) return NO;
    int16_t touch=1;
    float sensitivity=atomic_load(&Sensitivity);
    float values[2]={sensitivity,sensitivity};
    BOOL okay=Write(config+0x12e,&touch,2) && Write(config+0x124,values,sizeof(values));
    if(okay) { Log([NSString stringWithFormat:@"touch-profile applied manual-fire=1 sensitivity=%.2f next-round-layout=1",(double)sensitivity]); }
    return okay;
}
static void TickControls(void) {
    uintptr_t manager=0;
    BOOL ready=Manager(&manager);
    atomic_store(&InputReady,ready);
    BOOL gameplay=ready&&InGame();atomic_store(&Gameplay,gameplay);
    if(ready && atomic_load(&Enabled) && atomic_exchange(&ProfileDirty,0) && !ApplyProfile()) atomic_store(&ProfileDirty,1);
    if(!ready) { Sent=0;LastManager=0;return; }
    if(manager!=LastManager) { Sent=0;LastManager=manager;Log(@"input-manager ready"); }
    unsigned target=BOZControlsTarget(atomic_load(&Requested),atomic_load(&Enabled),atomic_load(&Active),gameplay,atomic_load(&Editing));
    unsigned masks[]={BOZFire,BOZAim,BOZReload,BOZSwap};
    uintptr_t functions[]={0x1ef2c4,0x1ef384,0x1ef344,0x1ef314};
    unsigned fields[]={0x79,0x7c,0x7b,0x7a};
    for(int i=0;i<4;i++) {
        BOOL down=(target&masks[i])!=0;uint8_t native=0;
        if(!Read(manager+fields[i],&native,1)) continue;
        BOOL changed=((Sent^target)&masks[i])!=0;
        // Reassert held fire/ADS only while the corresponding physical button
        // is held. Reload and swap remain edges, not an automatic repeated command.
        BOOL reassert=i<2 && down && !native;
        if(!changed&&!reassert) continue;
        if(changed) Log([NSString stringWithFormat:@"button=%u down=%d",masks[i],down]);
        if(i==0) ((void (*)(void *,int,int))(B+functions[i]))((void *)manager,down,0);
        else ((void (*)(void *,int))(B+functions[i]))((void *)manager,down);
    }
    Sent=target;
}
static uint64_t ControlsYield(int32_t milliseconds) {
    uint64_t (*original)(int32_t)=(void *)(B+0x85768);
    BOOL engine=!pthread_main_np() && (uintptr_t)pthread_self()==atomic_load(&EngineThread);
    BOOL outer=engine && !atomic_exchange(&InsideYield,1);
    uint64_t result=original(milliseconds);
    if(outer) { @autoreleasepool { TickControls(); } atomic_store(&InsideYield,0); }
    return result;
}
static void Frame(id self,SEL selector) {
    if(!pthread_main_np()) atomic_store(&EngineThread,(uintptr_t)pthread_self());
    ((void (*)(id,SEL))OriginalShow)(self,selector);
}
static BOOL InstallYield(void) {
    uint32_t code[0x4000/4];
    if(!Read(B+0xf4000,code,sizeof(code))) return NO;
    for(size_t n=0;n+4<=sizeof(code)/sizeof(*code);n++) {
        uintptr_t slot=BOZControlsThunkSlot(code+n,B+0xf4000+n*4);
        if(slot<B+0x5b8000 || slot>=B+0x6dc000 || (slot&7)) continue;
        uintptr_t value=0;if(!Read(slot,&value,8)) continue;
        if(value==(uintptr_t)ControlsYield) return YES;
        if(value!=B+0x85768) continue;
        // This is a validated import cell in the game's writable S3E data,
        // not executable code. An aligned atomic swap avoids a torn callback.
        uintptr_t expected=value;
        if(atomic_compare_exchange_strong((_Atomic(uintptr_t) *)slot,&expected,(uintptr_t)ControlsYield)) {
            Log([NSString stringWithFormat:@"yield-import hooked slot-offset=%llx",(unsigned long long)(slot-B)]);return YES;
        }
    }
    return NO;
}

@interface BOZControlsOverlay : UIView @end
@implementation BOZControlsOverlay
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for(UIView *view in self.subviews) if(!view.hidden&&view.userInteractionEnabled&&[view pointInside:[view convertPoint:point fromView:self] withEvent:event]) return YES;
    return NO;
}
@end
@interface BOZControls : NSObject
+ (void)menu;
+ (void)down:(UIButton *)button;
+ (void)up:(UIButton *)button;
+ (void)pan:(UIPanGestureRecognizer *)gesture;
@end
static CGRect SafeRect(void) { return UIEdgeInsetsInsetRect(Window().bounds,Window().safeAreaInsets); }
static void Layout(void) {
    UIWindow *window=Window();if(!window||!Overlay) return;
    Overlay.frame=window.bounds;CGRect safe=SafeRect();
    MenuButton.frame=CGRectMake(safe.origin.x+130,safe.origin.y+12,100,42);
    double defaults[4][2]={{0.90,0.71},{0.78,0.82},{0.66,0.90},{0.66,0.68}};
    for(NSUInteger i=0;i<Buttons.count;i++) {
        UIButton *button=Buttons[i];double x=defaults[i][0],y=defaults[i][1];
        NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:[Pref stringByAppendingFormat:@"Position.%lu",(unsigned long)i]];
        if(saved.count==2 && [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) { x=[saved[0] doubleValue];y=[saved[1] doubleValue]; }
        if(!isfinite(x)||!isfinite(y)||x<0||x>1||y<0||y>1) { x=defaults[i][0];y=defaults[i][1]; }
        CGFloat diameter=i==0?84:62;
        button.bounds=CGRectMake(0,0,diameter,diameter);
        button.center=CGPointMake(fmax(CGRectGetMinX(safe)+diameter/2,fmin(CGRectGetMaxX(safe)-diameter/2,safe.origin.x+x*safe.size.width)),fmax(CGRectGetMinY(safe)+diameter/2,fmin(CGRectGetMaxY(safe)-diameter/2,safe.origin.y+y*safe.size.height)));
        button.layer.cornerRadius=diameter/2;
    }
}
@implementation BOZControls
+ (void)down:(UIButton *)button { if(!atomic_load(&Editing)) atomic_fetch_or(&Requested,(unsigned)button.tag); }
+ (void)up:(UIButton *)button { atomic_fetch_and(&Requested,~(unsigned)button.tag); }
+ (void)pan:(UIPanGestureRecognizer *)gesture {
    if(!atomic_load(&Editing)) return;
    UIButton *button=(UIButton *)gesture.view;CGPoint movement=[gesture translationInView:Overlay];
    CGRect safe=SafeRect();CGFloat radius=button.bounds.size.width/2;
    button.center=CGPointMake(fmax(CGRectGetMinX(safe)+radius,fmin(CGRectGetMaxX(safe)-radius,button.center.x+movement.x)),fmax(CGRectGetMinY(safe)+radius,fmin(CGRectGetMaxY(safe)-radius,button.center.y+movement.y)));
    [gesture setTranslation:CGPointZero inView:Overlay];
    if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled) {
        NSUInteger index=[Buttons indexOfObject:button];
        [NSUserDefaults.standardUserDefaults setObject:@[@((button.center.x-safe.origin.x)/safe.size.width),@((button.center.y-safe.origin.y)/safe.size.height)] forKey:[Pref stringByAppendingFormat:@"Position.%lu",(unsigned long)index]];
    }
}
+ (void)menu {
    atomic_store(&Requested,0);
    UIViewController *presenter=Presenter();if(!presenter||[presenter isKindOfClass:UIAlertController.class]) return;
    NSString *status=atomic_load(&YieldInstalled)&&atomic_load(&InputReady)?@"Input bridge ready":@"Waiting for the game input bridge";
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Touch Controls" message:[status stringByAppendingString:@"\nDT2-style touch preset with manual fire. Enable at the main menu, then start a new round for the native swipe-aim layout. FIRE and ADS are hold buttons. No target-based auto-fire is added."] preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:atomic_load(&Enabled)?@"Hide combat buttons":@"Enable touch preset" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        BOOL on=!atomic_load(&Enabled);atomic_store(&Enabled,on);atomic_store(&Requested,0);
        [NSUserDefaults.standardUserDefaults setBool:on forKey:[Pref stringByAppendingString:@"Enabled"]];
        if(on) atomic_store(&ProfileDirty,1);
        Log([NSString stringWithFormat:@"enabled=%d",on]);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:atomic_load(&Editing)?@"Finish moving buttons":@"Move buttons" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        BOOL edit=!atomic_load(&Editing);atomic_store(&Editing,edit);atomic_store(&Requested,0);
        for(UIButton *button in Buttons) for(UIGestureRecognizer *recognizer in button.gestureRecognizers) recognizer.enabled=edit;
    }]];
    for(NSNumber *value in @[@0.35,@0.50,@0.65]) [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Aim sensitivity: %.2f",value.floatValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        Sensitivity=value.floatValue;[NSUserDefaults.standardUserDefaults setFloat:Sensitivity forKey:[Pref stringByAppendingString:@"Sensitivity"]];atomic_store(&ProfileDirty,1);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Reset button positions" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        for(int i=0;i<4;i++) [NSUserDefaults.standardUserDefaults removeObjectForKey:[Pref stringByAppendingFormat:@"Position.%d",i]];
        Layout();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:menu animated:YES completion:nil];
}
@end
static void Install(void) {
    if(!B) {
        Method accessor=class_getInstanceMethod(objc_getClass("s3eAppDelegate"),sel_registerName("m_View"));Dl_info info={0};
        if(!accessor||!dladdr((void *)method_getImplementation(accessor),&info)||!info.dli_fbase) return;
        uintptr_t base=(uintptr_t)info.dli_fbase;uint32_t code[2];
        if(!Read(base+0x1ef2c4,code,sizeof(code)) || code[0]!=0x53001c42 || code[1]!=0x53001c21) return;
        Method show=class_getInstanceMethod(objc_getClass("GLView"),sel_registerName("show"));if(!show) return;
        B=base;OriginalShow=method_getImplementation(show);method_setImplementation(show,(IMP)Frame);
        Log(@"loaded supported-guest=1 manual-fire-only=1");
    }
    if(!atomic_load(&YieldInstalled)) atomic_store(&YieldInstalled,InstallYield());
    UIWindow *window=Window();if(!window) return;
    if(!Overlay) {
        Overlay=[[BOZControlsOverlay alloc] initWithFrame:window.bounds];Buttons=[NSMutableArray array];
        MenuButton=[UIButton buttonWithType:UIButtonTypeSystem];[MenuButton setTitle:@"Controls" forState:UIControlStateNormal];
        MenuButton.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.75];MenuButton.layer.cornerRadius=9;[MenuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [MenuButton addTarget:BOZControls.class action:@selector(menu) forControlEvents:UIControlEventTouchUpInside];[Overlay addSubview:MenuButton];
        NSArray *titles=@[@"FIRE",@"ADS",@"RELOAD",@"SWAP"];int bits[]={BOZFire,BOZAim,BOZReload,BOZSwap};
        for(int i=0;i<4;i++) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.tag=bits[i];[button setTitle:titles[i] forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont boldSystemFontOfSize:i==0?19:12];button.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.45];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];button.layer.borderWidth=2;button.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:0.75].CGColor;
            [button addTarget:BOZControls.class action:@selector(down:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
            [button addTarget:BOZControls.class action:@selector(up:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
            UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:BOZControls.class action:@selector(pan:)];pan.enabled=NO;[button addGestureRecognizer:pan];
            [Buttons addObject:button];[Overlay addSubview:button];
        }
    }
    if(Overlay.superview!=window) [window addSubview:Overlay];
    BOOL show=atomic_load(&Enabled) && (atomic_load(&Gameplay)||atomic_load(&Editing)) && window.bounds.size.width>window.bounds.size.height;
    for(UIButton *button in Buttons) button.hidden=!show;
    if(!atomic_load(&Editing)) Layout();
    [window bringSubviewToFront:Overlay];
}
__attribute__((constructor)) static void Start(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        atomic_store(&Enabled,[NSUserDefaults.standardUserDefaults boolForKey:[Pref stringByAppendingString:@"Enabled"]]);
        float saved=[NSUserDefaults.standardUserDefaults floatForKey:[Pref stringByAppendingString:@"Sensitivity"]];if(isfinite(saved)&&saved>=0.1&&saved<=1) Sensitivity=saved;
        atomic_store(&ProfileDirty,1);atomic_store(&Active,UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ atomic_store(&Active,0);atomic_store(&Requested,0); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ atomic_store(&Active,1); }];
        Install();[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){Install();}];
    });
}
