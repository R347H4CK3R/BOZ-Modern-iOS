"""Exercise actual tracking overrides with host-side UIKit stand-ins.

The stand-ins do not establish UIKit event delivery. They verify the production
methods reject stale gestures after a reset, preserve fresh drags and cancel.
"""
import pathlib,subprocess,tempfile,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
source=pathlib.Path('src/BOZModernInput.m').read_text();a=source.index('- (BOOL)beginTrackingWithTouch:');e=source.index('- (CGRect)titleRectForContentRect:',a);methods=source[a:e]
guard='if(self.inputEpoch!=atomic_load(&InputEpoch)) return NO;'
assert guard in methods
prefix='''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <pthread.h>
#include <stdatomic.h>
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "BOZControlsBridge.h"
#include "BOZTouchCore.h"
@interface UIEvent : NSObject @end
@implementation UIEvent @end
@interface UITouch : NSObject
@property(nonatomic) CGPoint location;
- (CGPoint)locationInView:(id)view;
@end
@implementation UITouch
- (CGPoint)locationInView:(id)view { (void)view;return self.location; }
@end
@interface UIButton : NSObject
@property(nonatomic) NSInteger tag;
@property(nonatomic) BOOL highlighted;
@property(nonatomic,strong) id superview;
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
- (void)cancelTrackingWithEvent:(UIEvent *)event;
@end
@implementation UIButton
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)touch;(void)event;return YES; }
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)touch;(void)event;return YES; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; }
@end
static _Atomic(unsigned) InputEpoch,Requested,PendingTaps;
static _Atomic(int) Editing;
static pthread_mutex_t AxisLock=PTHREAD_MUTEX_INITIALIZER;
static BOZLookChannels LookStreams;
static void AddFireLook(float dx,float dy) { BOZAddLookChannel(&LookStreams,BOZFireLook,dx,dy); }
@interface BOZModernButton : UIButton
@property(nonatomic) CGPoint aimPrevious;
@property(nonatomic) unsigned inputEpoch;
@end
@implementation BOZModernButton
'''
suffix='''
@end
int main(void) {
    @autoreleasepool {
        atomic_store(&InputEpoch,1);
        BOZModernButton *button=[BOZModernButton new];button.tag=BOZFire;
        UITouch *touch=[UITouch new];touch.location=CGPointZero;
        assert([button beginTrackingWithTouch:touch withEvent:nil]);
        atomic_store(&Requested,BOZFire);touch.location=CGPointMake(10,0);
        assert([button continueTrackingWithTouch:touch withEvent:nil]);
        BOZAxis a=BOZTakeLookChannels(&LookStreams,0.02f);assert(fabsf(a.x-0.2f)<0.0001f);
        atomic_fetch_add(&InputEpoch,1);atomic_store(&Requested,0);BOZResetLookChannels(&LookStreams);
        touch.location=CGPointMake(20,0);
        assert(![button continueTrackingWithTouch:touch withEvent:nil]);
        a=BOZTakeLookChannels(&LookStreams,0.02f);assert(a.x==0&&a.y==0);
        assert([button beginTrackingWithTouch:touch withEvent:nil]);touch.location=CGPointMake(25,0);
        assert([button continueTrackingWithTouch:touch withEvent:nil]);
        atomic_store(&Requested,BOZFire);atomic_store(&PendingTaps,BOZFire);
        [button cancelTrackingWithEvent:nil];
        assert(!atomic_load(&Requested)&&!atomic_load(&PendingTaps));
        a=BOZTakeLookChannels(&LookStreams,0.02f);assert(a.x==0&&a.y==0);
    }
    puts("PASS: actual button tracking rejects stale reset gestures and accepts fresh gestures; cancellation clears its actions/look");
}
'''
with tempfile.TemporaryDirectory() as folder:
    root=pathlib.Path(folder);obj=root/'core.o'
    subprocess.run(['clang','-std=c11','-Isrc','-c','src/BOZTouchCore.c','-o',str(obj)],check=True)
    def run(body,name):
        path=root/(name+'.m');path.write_text(prefix+body+suffix);binary=root/name
        subprocess.run(['clang','-std=gnu11','-fobjc-arc','-Isrc','-framework','Foundation','-framework','CoreGraphics',str(path),str(obj),'-o',str(binary)],check=True)
        return subprocess.run([str(binary)],capture_output=True,text=True)
    negative=run(methods.replace(guard,''),'tracking-without-reset-guard')
    assert negative.returncode!=0,'Regression did not reproduce without production epoch guard'
    result=run(methods,'tracking');assert result.returncode==0,result.stderr
    print('PASS: regression reproduces stale-gesture bug when epoch guard is removed')
    print(result.stdout.strip())
