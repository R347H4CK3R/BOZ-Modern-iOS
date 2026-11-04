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
#import "BOZTouchCore.h"

static uintptr_t B;
static IMP OriginalShow;
static _Atomic(unsigned) EngineFrames;
static _Atomic(int) SawMainFrame;
static _Atomic(unsigned) Requested,PendingTaps;
static _Atomic(int) Enabled,Active,Editing,InputReady,Gameplay,ProfileDirty;
static _Atomic(int) SuppressNative=0;
static unsigned Sent;
static _Atomic(int) UseAvailable;
static _Atomic(float) UseX=0.5f,UseY=0.55f;
static uintptr_t LastManager;
static _Atomic(float) Sensitivity=0.60f;
static _Atomic(int) InsideFrame,MenuOpen,ManualAimReady,ExternalConflict;
static pthread_mutex_t AxisLock=PTHREAD_MUTEX_INITIALIZER;
static BOZAxis Movement;
static BOZLook RelativeLook;
static void Install(void);
static void ResetAxes(void) {
    pthread_mutex_lock(&AxisLock);Movement=(BOZAxis){0,0};BOZResetLook(&RelativeLook);pthread_mutex_unlock(&AxisLock);
}
static void AddLook(float dx,float dy) {
    pthread_mutex_lock(&AxisLock);BOZAccumulateLook(&RelativeLook,dx,dy);pthread_mutex_unlock(&AxisLock);
}
static UIView *Overlay;
static UIButton *MenuButton;
static NSMutableArray<UIButton *> *Buttons;
static NSString *const Pref=@"BOZ.ModernInput.";

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
    NSData *line=[[NSString stringWithFormat:@"%@ integrated-input-v1 %@\n",NSDate.date,message] dataUsingEncoding:NSUTF8StringEncoding];
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
    if(!B || !Read(B+0x644bd0,&p,8) || !p || !Read(p,&v,8)) return NO;
    if(v!=B+0x5e5d90) {
        static uintptr_t previous=0;
        if(v!=previous) { previous=v;Log([NSString stringWithFormat:@"input-manager rejected vtable-offset=%llx expected=5e5d90",(unsigned long long)(v-B)]); }
        return NO;
    }
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
    uint8_t off=0;
    BOOL okay=Write(config+0x12e,&touch,2) && Write(config+0x124,values,sizeof(values)) && Write(config+0x132,&off,1);
    if(okay) { Log([NSString stringWithFormat:@"touch-profile applied manual-fire=1 sensitivity=%.2f next-round-layout=1",(double)sensitivity]); }
    return okay;
}
// Native UI operations run only on the recorded engine thread. Re-resolve
// elements from the current UI tree; never dereference saved element pointers.
typedef struct { const char *name;int scope; } HiddenWidget;
static const HiddenWidget NativeWidgets[]={
    {"IronSight_img",1},{"IronSight_Btn",1},{"IronSight_img_lefty",1},{"IronSight_Btn_lefty",1},
    {"Reload_img",1},{"Reload_SwapWeapon_Btn",1},{"Reload_img_lefty",1},{"Reload_SwapWeapon_Btn_lefty",1},
    {"grenade_button",1},{"grenade_button_lefty",1},
    {"Crouch_blood",0},{"crouch_element",0},{"Crouch_Btn",0},
    {"Crouch_blood_lefty",0},{"crouch_element_lefty",0},{"Crouch_Btn_lefty",0},
    {"melee",0},{"melee_lefty",0},{"Melee_Btn",0},{"Melee_Btn_lefty",0},
    {"Button",2},{"Image",2}
};
typedef struct { uintptr_t identity;size_t templateIndex;unsigned flags; } WidgetSnapshot;
static WidgetSnapshot SavedWidgets[512];
typedef struct { uintptr_t identity;int32_t position[2]; } PromptSnapshot;
static PromptSnapshot SavedPrompts[64];
static BOOL HUDWasEnabled;
static void ProcessNativeWidget(size_t index,uintptr_t element,BOOL replace) {
    if(!element) return;
    WidgetSnapshot *record=NULL,*empty=NULL;
    for(size_t i=0;i<512;i++) {
        if(SavedWidgets[i].identity==element&&SavedWidgets[i].templateIndex==index) { record=SavedWidgets+i;break; }
        if(!SavedWidgets[i].identity&&!empty) empty=SavedWidgets+i;
    }
    if(replace) {
        if(!record) {
            if(!empty) return; // Fail open rather than hide without restoration data.
            record=empty;record->identity=element;record->templateIndex=index;
            unsigned visible=((int (*)(uintptr_t,unsigned))(B+0x4cc0dc))(element,2);
            record->flags=visible?2:0;
        }
        ((void (*)(uintptr_t,int))(B+0x4cdaf8))(element,0);
        // Visibility alone excludes the native button from hit testing.
        // Keep its geometry and enabled state intact for game-side updates.
    } else if(record) {
        BOOL permit=NativeWidgets[index].scope!=2||atomic_load(&UseAvailable);
        ((void (*)(uintptr_t,int))(B+0x4cdaf8))(element,permit&&!!(record->flags&2));
        record->identity=0;
    }
}
static BOOL NativeUseReady(uintptr_t manager) {
    uint8_t available=0;uintptr_t client=0,context=0;
    return Read(manager+0x98,&available,1) && available && Read(B+0x637218,&client,8) && client && Read(client+0x2c0,&context,8) && context;
}
static void SyncNativeHUD(BOOL replace) {
    BOOL restorePending=NO;
    for(size_t i=0;i<512;i++) restorePending|=SavedWidgets[i].identity!=0;
    for(size_t i=0;i<64;i++) restorePending|=SavedPrompts[i].identity!=0;
    if(!replace&&!HUDWasEnabled&&!restorePending) return;
    uintptr_t ui=0,vtable=0;
    if(!Read(B+0x63ce38,&ui,8)||!ui||!Read(ui,&vtable,8)||vtable<B+0x5b8000||vtable>=B+0x6dc000) return;
    uintptr_t (*find)(uintptr_t,const char *,int)=(void *)(B+0x283d54);
    uintptr_t (*child)(uintptr_t,const char *,int,int)=(void *)(B+0x4ca68c);
    uintptr_t group=find(ui,"control_Schemes",0),poi=find(ui,"ig_poi",0);
    uintptr_t schemes[32]={0};uint32_t selected=0,count=0;
    if(group) {
        uintptr_t children=0;
        if(!Read(group+0x170,&selected,4)||!Read(group+0x40,&count,4)||count>32||!Read(group+0x38,&children,8)||!children||!Read(children,schemes,count*8)) count=0;
    }
    unsigned hidden=0;
    for(size_t i=0;i<sizeof(NativeWidgets)/sizeof(*NativeWidgets);i++) {
        const HiddenWidget *entry=NativeWidgets+i;
        if(entry->scope==1) {
            for(uint32_t j=0;j<count;j++) {
                if(replace&&j!=selected) continue;
                uintptr_t element=schemes[j]?child(schemes[j],entry->name,1,0):0;
                ProcessNativeWidget(i,element,replace);hidden+=element!=0;
            }
        } else {
            uintptr_t element=entry->scope==2?(poi?child(poi,entry->name,1,0):0):find(ui,entry->name,0);
            ProcessNativeWidget(i,element,replace);hidden+=element!=0;
        }
    }
    if(poi) {
        PromptSnapshot *record=NULL,*empty=NULL;
        for(size_t i=0;i<64;i++) {
            if(SavedPrompts[i].identity==poi) { record=SavedPrompts+i;break; }
            if(!SavedPrompts[i].identity&&!empty) empty=SavedPrompts+i;
        }
        int32_t geometry[4]={0};uintptr_t parent=0;
        if(Read(poi+0xa0,geometry,sizeof(geometry))) {
            if(replace&&!record&&empty) { record=empty;record->identity=poi;record->position[0]=geometry[0];record->position[1]=geometry[1]; }
            if(record) {
                int32_t position[2]={record->position[0],record->position[1]},size[2]={0};
                if(replace&&Read(poi+0x30,&parent,8)&&parent&&Read(parent+0xa8,size,sizeof(size))&&size[0]>0&&size[0]<16384&&size[1]>0&&size[1]<16384&&geometry[2]>0&&geometry[2]<=size[0]&&geometry[3]>0&&geometry[3]<=size[1]) {
                    position[0]=(int32_t)fmax(0,fmin(size[0]-geometry[2],size[0]*atomic_load(&UseX)-geometry[2]/2));
                    position[1]=(int32_t)fmax(0,fmin(size[1]-geometry[3],size[1]*fmin(0.95,atomic_load(&UseY)+0.11)-geometry[3]/2));
                }
                if(position[0]!=geometry[0]||position[1]!=geometry[1]) ((void (*)(uintptr_t,const int32_t *,int))(B+0x4cb010))(poi,position,0);
                if(!replace) record->identity=0;
            }
        }
    }
    if(replace!=HUDWasEnabled) Log([NSString stringWithFormat:@"native-controls replacement=%d matched=%u transparent-buy=1",replace,hidden]);
    HUDWasEnabled=replace;
}
static void EnforceManualAim(void) {
    uint8_t off=0,value=1;uintptr_t config=0,hud=0,player=0,vtable=0;
    BOOL configReady=Read(B+0x637228,&config,8)&&config&&Read(config+0x132,&value,1);
    if(configReady&&value) Write(config+0x132,&off,1);
    configReady=configReady&&Read(config+0x132,&value,1)&&value==0;
    BOOL playerReady=Read(B+0x639ad8,&hud,8)&&hud&&Read(hud,&vtable,8)&&vtable>=B+0x5b8000&&vtable<B+0x6dc000&&Read(hud+0x78,&player,8)&&player&&Read(player+0x145,&value,1);
    if(playerReady&&value) Write(player+0x145,&off,1);
    playerReady=playerReady&&Read(player+0x145,&value,1)&&value==0;
    BOOL ready=configReady&&playerReady;
    if(atomic_exchange(&ManualAimReady,ready)!=ready) Log([NSString stringWithFormat:@"native-aim-assist verified-off=%d",ready]);
}
static void DispatchAxes(uintptr_t manager,BOOL allowed) {
    static BOOL sent=NO;
    BOZAxis move={0},look={0};
    pthread_mutex_lock(&AxisLock);
    if(allowed) { move=Movement;look=BOZConsumeLook(&RelativeLook,0.02f*atomic_load(&Sensitivity)/0.60f); }
    else { Movement=(BOZAxis){0,0};BOZResetLook(&RelativeLook); }
    pthread_mutex_unlock(&AxisLock);
    if(!allowed&&!sent) return;
    void (*analog)(void *,int,float,float,float,float,float)=(void *)(B+0x1ef214);
    analog((void *)manager,1,BOZDirection(move),hypotf(move.x,move.y),3.5f,move.x,move.y);
    analog((void *)manager,0,BOZDirection(look),hypotf(look.x,look.y),3.5f,look.x,look.y);
    if(allowed&&!sent) Log(@"owned-touch input=active aim-assist=off manual-fire=1");
    sent=allowed;
}
static void TickControls(void) {
    uintptr_t manager=0;
    BOOL ready=Manager(&manager);
    atomic_store(&InputReady,ready);
    BOOL gameplay=ready&&InGame();
    int oldGameplay=atomic_exchange(&Gameplay,gameplay);
    if(oldGameplay!=gameplay) {
        if(!gameplay) { ResetAxes();atomic_store(&Requested,0);atomic_store(&PendingTaps,0); }
        Log([NSString stringWithFormat:@"gameplay-state active=%d",gameplay]);
        dispatch_async(dispatch_get_main_queue(),^{Install();});
    }
    if(ready && atomic_load(&Enabled) && atomic_exchange(&ProfileDirty,0) && !ApplyProfile()) atomic_store(&ProfileDirty,1);
    if(!ready) { atomic_store(&UseAvailable,0);Sent=0;LastManager=0;return; }
    EnforceManualAim();
    atomic_store(&UseAvailable,NativeUseReady(manager));
    SyncNativeHUD(atomic_load(&Enabled)&&atomic_load(&SuppressNative)&&atomic_load(&ManualAimReady)&&gameplay&&atomic_load(&Active));
    static unsigned readyFrames=0;
    if(gameplay) { readyFrames++;if(readyFrames<=3||readyFrames==60) Log([NSString stringWithFormat:@"ready-frame=%u native-hiding=%d",readyFrames,atomic_load(&SuppressNative)]); }
    else readyFrames=0;
    if(manager!=LastManager) { Sent=0;LastManager=manager;Log(@"input-manager ready"); }
    BOOL allowed=BOZControlsTarget(BOZAll,atomic_load(&Enabled),atomic_load(&Active),gameplay,atomic_load(&Editing)||atomic_load(&MenuOpen))!=0&&atomic_load(&ManualAimReady)&&!atomic_load(&ExternalConflict);
    DispatchAxes(manager,allowed);
    unsigned pending=atomic_exchange(&PendingTaps,0);
    unsigned target=BOZControlsQueuedTarget(atomic_load(&Requested),pending,Sent,allowed);
    if(allowed) atomic_fetch_or(&PendingTaps,pending & Sent & BOZDiscrete);
    unsigned masks[]={BOZFire,BOZAim,BOZReload,BOZSwap,BOZMelee,BOZGrenade,BOZCrouch,BOZTactical};
    uintptr_t functions[]={0x1ef2c4,0x1ef384,0x1ef344,0x1ef314,0x1ef444,0x1ef484,0x1ef3c4,0x1ef4c4};
    unsigned fields[]={0x79,0x7c,0x7b,0x7a,0x7f,0x80,0x7d,0x81};
    for(int i=0;i<8;i++) {
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
    if((target&BOZUse)&&!(Sent&BOZUse)&&allowed&&NativeUseReady(manager)) {
        uint32_t event=0;
        if(Read(B+0x645898,&event,4)) {
            ((void (*)(uintptr_t,uint32_t,uintptr_t,uintptr_t,uintptr_t))(B+0x3be184))(manager+0x38,event,0,0,0);
            Log(@"buy-use pressed native-poi-action=1");
        }
    }
    Sent=target;
}
static void Frame(id self,SEL selector) {
    // Present first, then dispatch queued commands on the same engine thread.
    // Do not require s3eDeviceYield: that import may not run during gameplay.
    ((void (*)(id,SEL))OriginalShow)(self,selector);
    if(pthread_main_np()) {
        if(!atomic_exchange(&SawMainFrame,1)) Log(@"frame-hook main-thread=1 input-dispatch=blocked");
        return;
    }
    if(atomic_fetch_add(&EngineFrames,1)==0) Log(@"frame-hook engine-thread=1 first-frame=1");
    if(atomic_exchange(&InsideFrame,1)) return;
    @autoreleasepool { TickControls(); }
    atomic_store(&InsideFrame,0);
}

@interface BOZModernSurface : UIView { BOZFingerOwners _owners; }
@property(nonatomic,strong) UITouch *moveTouch;
@property(nonatomic,strong) UITouch *lookTouch;
@property(nonatomic) CGPoint moveOrigin;
@property(nonatomic) CGPoint lookLast;
@property(nonatomic) CGSize lastSize;
- (void)resetTouches;
@end
@implementation BOZModernSurface
- (void)resetTouches {
    self.moveTouch=nil;self.lookTouch=nil;_owners=(BOZFingerOwners){0};ResetAxes();
    atomic_store(&Requested,0);atomic_store(&PendingTaps,0);[self setNeedsDisplay];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(!CGSizeEqualToSize(self.lastSize,self.bounds.size)) { self.lastSize=self.bounds.size;[self resetTouches]; }
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for(UIView *view in self.subviews) if(!view.hidden&&view.userInteractionEnabled&&[view pointInside:[view convertPoint:point fromView:self] withEvent:event]) return YES;
    return !atomic_load(&ExternalConflict)&&atomic_load(&Enabled)&&atomic_load(&Gameplay)&&atomic_load(&ManualAimReady)&&atomic_load(&Active)&&!atomic_load(&Editing)&&!atomic_load(&MenuOpen)&&point.y>self.safeAreaInsets.top+64&&CGRectContainsPoint(self.bounds,point);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for(UITouch *touch in touches) {
        if(touch.view!=self) continue;
        CGPoint p=[touch locationInView:self];
        int lane=BOZClaimFinger(&_owners,(uintptr_t)(__bridge void *)touch,p.x,self.bounds.size.width*0.43);
        if(lane==BOZMoveLane) { self.moveTouch=touch;self.moveOrigin=p; }
        if(lane==BOZLookLane) { self.lookTouch=touch;self.lookLast=p; }
    }
    [self setNeedsDisplay];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for(UITouch *touch in touches) {
        CGPoint p=[touch locationInView:self];
        if(touch==self.moveTouch) {
            BOZAxis a=BOZStick(p.x-self.moveOrigin.x,p.y-self.moveOrigin.y,64,0.12f);
            pthread_mutex_lock(&AxisLock);Movement=a;pthread_mutex_unlock(&AxisLock);
        } else if(touch==self.lookTouch) {
            AddLook(p.x-self.lookLast.x,p.y-self.lookLast.y);self.lookLast=p;
        }
    }
    [self setNeedsDisplay];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    for(UITouch *touch in touches) {
        BOZReleaseFinger(&_owners,(uintptr_t)(__bridge void *)touch);
        if(touch==self.moveTouch) { self.moveTouch=nil;pthread_mutex_lock(&AxisLock);Movement=(BOZAxis){0,0};pthread_mutex_unlock(&AxisLock); }
        if(touch==self.lookTouch) { self.lookTouch=nil;pthread_mutex_lock(&AxisLock);BOZResetLook(&RelativeLook);pthread_mutex_unlock(&AxisLock); }
    }
    [self setNeedsDisplay];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self touchesEnded:touches withEvent:event]; }
- (void)drawRect:(CGRect)rect {
    (void)rect;if(!self.moveTouch) return;
    pthread_mutex_lock(&AxisLock);BOZAxis a=Movement;pthread_mutex_unlock(&AxisLock);
    CGPoint c=self.moveOrigin;
    [[UIColor.whiteColor colorWithAlphaComponent:0.4] setStroke];
    UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x-64,c.y-64,128,128)];ring.lineWidth=1.5;[ring stroke];
    [[UIColor.whiteColor colorWithAlphaComponent:0.22] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x+a.x*42-20,c.y+a.y*42-20,40,40)] fill];
}
@end
// Original vector icons; no game artwork or fixed display-size assumptions.
@interface BOZModernButton : UIButton
@property(nonatomic) CGPoint aimPrevious;
@end
@implementation BOZModernButton
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    self.aimPrevious=[touch locationInView:self.superview];return [super beginTracking:touch withEvent:event];
}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    if(self.tag==BOZFire&&!atomic_load(&Editing)) {
        CGPoint p=[touch locationInView:self.superview];AddLook(p.x-self.aimPrevious.x,p.y-self.aimPrevious.y);self.aimPrevious=p;return YES;
    }
    return [super continueTracking:touch withEvent:event];
}
- (CGRect)titleRectForContentRect:(CGRect)contentRect {
    return CGRectMake(4,contentRect.size.height-19,contentRect.size.width-8,15);
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:highlighted?0.12:0.0];
    self.layer.borderColor=(highlighted?[UIColor colorWithRed:1 green:0.83 blue:0.24 alpha:1]:[UIColor.whiteColor colorWithAlphaComponent:0.8]).CGColor;
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGFloat x=CGRectGetMidX(self.bounds),y=(self.bounds.size.height-16)/2;
    UIColor *ink=self.highlighted?[UIColor colorWithRed:1 green:0.83 blue:0.24 alpha:1]:UIColor.whiteColor;
    [ink setStroke];[ink setFill];
    UIBezierPath *p=[UIBezierPath bezierPath];p.lineWidth=2;p.lineCapStyle=kCGLineCapRound;p.lineJoinStyle=kCGLineJoinRound;
    if(self.tag==BOZFire || self.tag==BOZAim) {
        if(self.tag==BOZFire) [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x-11,y-11,22,22)]];
        else {
            for(int a=0;a<4;a++) {
                CGFloat sx=(a&1)?1:-1,sy=(a&2)?1:-1;
                [p moveToPoint:CGPointMake(x+sx*6,y+sy*13)];[p addLineToPoint:CGPointMake(x+sx*13,y+sy*13)];[p addLineToPoint:CGPointMake(x+sx*13,y+sy*6)];
            }
        }
        [p moveToPoint:CGPointMake(x-17,y)];[p addLineToPoint:CGPointMake(x-8,y)];
        [p moveToPoint:CGPointMake(x+8,y)];[p addLineToPoint:CGPointMake(x+17,y)];
        [p moveToPoint:CGPointMake(x,y-17)];[p addLineToPoint:CGPointMake(x,y-8)];
        [p moveToPoint:CGPointMake(x,y+8)];[p addLineToPoint:CGPointMake(x,y+17)];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x-2,y-2,4,4)] fill];
    } else if(self.tag==BOZReload) {
        [p addArcWithCenter:CGPointMake(x,y) radius:12 startAngle:-0.65 endAngle:4.5 clockwise:YES];
        [p moveToPoint:CGPointMake(x-8,y-13)];[p addLineToPoint:CGPointMake(x-2,y-13)];[p addLineToPoint:CGPointMake(x-2,y-7)];
    } else if(self.tag!=BOZSwap) {
        NSDictionary *icons=@{@(BOZMelee):@"bolt.horizontal.fill",@(BOZGrenade):@"flame",@(BOZCrouch):@"figure.walk",@(BOZTactical):@"smoke",@(BOZUse):@"hand.tap"};
        UIImage *icon=[UIImage systemImageNamed:icons[@(self.tag)]?:@"circle"];
        [[icon imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:CGRectMake(x-13,y-13,26,26)];
    } else {
        [p moveToPoint:CGPointMake(x-22,y-5)];[p addLineToPoint:CGPointMake(x+22,y-5)];
        [p addLineToPoint:CGPointMake(x+16,y-11)];[p moveToPoint:CGPointMake(x+22,y-5)];[p addLineToPoint:CGPointMake(x+16,y+1)];
        [p moveToPoint:CGPointMake(x+22,y+7)];[p addLineToPoint:CGPointMake(x-22,y+7)];
        [p addLineToPoint:CGPointMake(x-16,y+1)];[p moveToPoint:CGPointMake(x-22,y+7)];[p addLineToPoint:CGPointMake(x-16,y+13)];
    }
    [p stroke];
}
@end
@interface BOZModernControls : NSObject
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
    double defaults[9][2]={{0.88,0.57},{0.91,0.25},{0.78,0.83},{0.52,0.88},{0.80,0.36},{0.70,0.60},{0.92,0.86},{0.63,0.78},{0.50,0.55}};
    for(NSUInteger i=0;i<Buttons.count;i++) {
        UIButton *button=Buttons[i];double x=defaults[i][0],y=defaults[i][1];
        NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:[Pref stringByAppendingFormat:@"CODReplacement.Position.%lu",(unsigned long)i]];
        if(saved.count==2 && [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) { x=[saved[0] doubleValue];y=[saved[1] doubleValue]; }
        if(!isfinite(x)||!isfinite(y)||x<0||x>1||y<0||y>1) { x=defaults[i][0];y=defaults[i][1]; }
        CGFloat width=i==8?160:(i==3?120:(i==0?88:58)),height=i==8?54:(i==3?54:width);
        button.bounds=CGRectMake(0,0,width,height);
        button.center=CGPointMake(fmax(CGRectGetMinX(safe)+width/2,fmin(CGRectGetMaxX(safe)-width/2,safe.origin.x+x*safe.size.width)),fmax(CGRectGetMinY(safe)+height/2,fmin(CGRectGetMaxY(safe)-height/2,safe.origin.y+y*safe.size.height)));
        button.layer.cornerRadius=(i==3||i==8)?7:width/2;
        if(i==8) { atomic_store(&UseX,button.center.x/window.bounds.size.width);atomic_store(&UseY,button.center.y/window.bounds.size.height); }
    }
}
@implementation BOZModernControls
+ (void)down:(UIButton *)button {
    if(atomic_load(&Editing)) return;
    unsigned bit=(unsigned)button.tag,previous=atomic_fetch_or(&Requested,bit);
    if(!(previous&bit) && (bit&BOZAll)) atomic_fetch_or(&PendingTaps,bit);
}
+ (void)up:(UIButton *)button { atomic_fetch_and(&Requested,~(unsigned)button.tag); }
+ (void)pan:(UIPanGestureRecognizer *)gesture {
    if(!atomic_load(&Editing)) return;
    UIButton *button=(UIButton *)gesture.view;CGPoint movement=[gesture translationInView:Overlay];
    CGRect safe=SafeRect();CGFloat radius=button.bounds.size.width/2,verticalRadius=button.bounds.size.height/2;
    button.center=CGPointMake(fmax(CGRectGetMinX(safe)+radius,fmin(CGRectGetMaxX(safe)-radius,button.center.x+movement.x)),fmax(CGRectGetMinY(safe)+verticalRadius,fmin(CGRectGetMaxY(safe)-verticalRadius,button.center.y+movement.y)));
    if(button.tag==BOZUse) { atomic_store(&UseX,button.center.x/Overlay.bounds.size.width);atomic_store(&UseY,button.center.y/Overlay.bounds.size.height); }
    [gesture setTranslation:CGPointZero inView:Overlay];
    if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled) {
        NSUInteger index=[Buttons indexOfObject:button];
        [NSUserDefaults.standardUserDefaults setObject:@[@((button.center.x-safe.origin.x)/safe.size.width),@((button.center.y-safe.origin.y)/safe.size.height)] forKey:[Pref stringByAppendingFormat:@"CODReplacement.Position.%lu",(unsigned long)index]];
    }
}
+ (void)menu {
    [(BOZModernSurface *)Overlay resetTouches];atomic_store(&MenuOpen,1);
    UIViewController *presenter=Presenter();if(!presenter||[presenter isKindOfClass:UIAlertController.class]) { atomic_store(&MenuOpen,0);return; }
    NSString *status;
    if(atomic_load(&ExternalConflict)) status=@"Remove external BOZControls.dylib from the Strata tweak folder, then relaunch";
    else if(!atomic_load(&EngineFrames)) status=atomic_load(&SawMainFrame)?@"Frame hook is on the UI thread; engine input blocked":@"Waiting for the first engine frame";
    else if(!atomic_load(&InputReady)) status=@"Engine frame connected; native input manager not ready";
    else if(!atomic_load(&Gameplay)) status=@"Input bridge connected; waiting for active gameplay";
    else if(!atomic_load(&ManualAimReady)) status=@"Native aim-assist disable verification pending";
    else status=@"Integrated input connected; native aim assist OFF";
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Integrated Controls" message:[status stringByAppendingString:@"\nCOD Mobile-inspired HUD with manual fire. Enable at the main menu, then start a new round for the native swipe-aim layout. Native hiding is optional and experimental. Movement and look are owned by this app. Aim assist is disabled. BUY / USE appears near the center when an interaction is available. FIRE and ADS are hold buttons. Manual aim and manual fire only."] preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:atomic_load(&Enabled)?@"Disable integrated input":@"Enable integrated input" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0);
        if(atomic_load(&ExternalConflict)) return;
        BOOL on=!atomic_load(&Enabled);atomic_store(&Enabled,on);atomic_store(&Requested,0);atomic_store(&PendingTaps,0);
        [NSUserDefaults.standardUserDefaults setBool:on forKey:[Pref stringByAppendingString:@"Enabled"]];
        if(on) atomic_store(&ProfileDirty,1);
        Log([NSString stringWithFormat:@"enabled=%d",on]);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:atomic_load(&SuppressNative)?@"Native button hiding: ON":@"Native button hiding: OFF" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0);
        BOOL hide=!atomic_load(&SuppressNative);atomic_store(&SuppressNative,hide);
        [NSUserDefaults.standardUserDefaults setBool:hide forKey:[Pref stringByAppendingString:@"SuppressNative"]];
        Log([NSString stringWithFormat:@"native-hiding selected=%d",hide]);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:atomic_load(&Editing)?@"Finish moving buttons":@"Move buttons" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0);
        BOOL edit=!atomic_load(&Editing);atomic_store(&Editing,edit);atomic_store(&Requested,0);atomic_store(&PendingTaps,0);
        for(UIButton *button in Buttons) for(UIGestureRecognizer *recognizer in button.gestureRecognizers) recognizer.enabled=edit;
    }]];
    for(NSNumber *value in @[@0.35,@0.50,@0.65]) [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Aim sensitivity: %.2f",value.floatValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0);
        Sensitivity=value.floatValue;[NSUserDefaults.standardUserDefaults setFloat:Sensitivity forKey:[Pref stringByAppendingString:@"Sensitivity"]];atomic_store(&ProfileDirty,1);
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Reset button positions" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0);
        for(int i=0;i<9;i++) [NSUserDefaults.standardUserDefaults removeObjectForKey:[Pref stringByAppendingFormat:@"CODReplacement.Position.%d",i]];
        Layout();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ atomic_store(&MenuOpen,0); }]];
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
    UIWindow *window=Window();if(!window) return;
    if(!Overlay) {
        Overlay=[[BOZModernSurface alloc] initWithFrame:window.bounds];Overlay.multipleTouchEnabled=YES;Overlay.opaque=NO;Overlay.backgroundColor=UIColor.clearColor;Buttons=[NSMutableArray array];
        MenuButton=[UIButton buttonWithType:UIButtonTypeSystem];[MenuButton setTitle:@"Controls" forState:UIControlStateNormal];
        MenuButton.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.75];MenuButton.layer.cornerRadius=9;[MenuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [MenuButton addTarget:BOZModernControls.class action:@selector(menu) forControlEvents:UIControlEventTouchUpInside];[Overlay addSubview:MenuButton];
        NSArray *titles=@[@"FIRE",@"ADS",@"RELOAD",@"SWAP",@"MELEE",@"GRENADE",@"CROUCH",@"TACTICAL",@"BUY / USE"];int bits[]={BOZFire,BOZAim,BOZReload,BOZSwap,BOZMelee,BOZGrenade,BOZCrouch,BOZTactical,BOZUse};
        for(int i=0;i<9;i++) {
            UIButton *button=[[BOZModernButton alloc] initWithFrame:CGRectZero];button.tag=bits[i];button.contentMode=UIViewContentModeRedraw;[button setTitle:titles[i] forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont boldSystemFontOfSize:10];button.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.0];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];button.layer.borderWidth=1.5;button.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:0.75].CGColor;
            [button addTarget:BOZModernControls.class action:@selector(down:) forControlEvents:UIControlEventTouchDown|UIControlEventTouchDragEnter];
            [button addTarget:BOZModernControls.class action:@selector(up:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|(i==0?0:UIControlEventTouchDragExit)];
            UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:BOZModernControls.class action:@selector(pan:)];pan.enabled=NO;[button addGestureRecognizer:pan];
            [Buttons addObject:button];[Overlay addSubview:button];
        }
    }
    if(Overlay.superview!=window) [window addSubview:Overlay];
    BOOL show=atomic_load(&Enabled) && ((atomic_load(&Gameplay)&&atomic_load(&ManualAimReady))||atomic_load(&Editing)) && window.bounds.size.width>window.bounds.size.height;
    if(!show) [(BOZModernSurface *)Overlay resetTouches];
    for(UIButton *button in Buttons) button.hidden=!show||(button.tag==BOZUse&&!atomic_load(&UseAvailable)&&!atomic_load(&Editing));
    if(!atomic_load(&Editing)) Layout();
    [window bringSubviewToFront:Overlay];
}
__attribute__((constructor)) static void Start(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        BOOL hasPreference=[NSUserDefaults.standardUserDefaults objectForKey:[Pref stringByAppendingString:@"Enabled"]]!=nil;
        atomic_store(&Enabled,hasPreference?[NSUserDefaults.standardUserDefaults boolForKey:[Pref stringByAppendingString:@"Enabled"]]:YES);
        if(objc_getClass("BOZControls")) { atomic_store(&ExternalConflict,1);atomic_store(&Enabled,0);Log(@"external-controls-addon detected remove BOZControls.dylib before enabling integrated input"); }
        float saved=[NSUserDefaults.standardUserDefaults floatForKey:[Pref stringByAppendingString:@"Sensitivity"]];if(isfinite(saved)&&saved>=0.1&&saved<=1) Sensitivity=saved;
        if([NSUserDefaults.standardUserDefaults objectForKey:[Pref stringByAppendingString:@"SuppressNative"]]) atomic_store(&SuppressNative,[NSUserDefaults.standardUserDefaults boolForKey:[Pref stringByAppendingString:@"SuppressNative"]]);
        atomic_store(&ProfileDirty,1);atomic_store(&Active,UIApplication.sharedApplication.applicationState==UIApplicationStateActive);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ atomic_store(&Active,0);[(BOZModernSurface *)Overlay resetTouches]; }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ atomic_store(&Active,1); }];
        Install();[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){Install();}];
    });
}

