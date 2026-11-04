#include "BOZTouchCore.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static int near(float a,float b) { return fabsf(a-b)<0.0001f; }
int main(void) {
    BOZAxis a=BOZStick(2,2,64,0.12f);assert(a.x==0&&a.y==0);
    a=BOZStick(64,0,64,0.12f);assert(near(a.x,1)&&a.y==0);
    a=BOZStick(64,64,64,0.12f);assert(near(hypotf(a.x,a.y),1));assert(a.x>0&&a.y>0);
    a=BOZStick(NAN,1,64,0.12f);assert(a.x==0&&a.y==0);
    a=BOZStick(1,1,0,0.12f);assert(a.x==0&&a.y==0);
    BOZLook l={0};BOZAccumulateLook(&l,6,-4);BOZAccumulateLook(&l,4,-6);
    a=BOZConsumeLook(&l,0.02f);assert(near(a.x,0.2f)&&near(a.y,-0.2f));
    a=BOZConsumeLook(&l,0.02f);assert(a.x==0&&a.y==0);
    BOZAccumulateLook(&l,1000000,1000000);a=BOZConsumeLook(&l,1);assert(near(hypotf(a.x,a.y),1));
    BOZAccumulateLook(&l,NAN,5);a=BOZConsumeLook(&l,1);assert(a.x==0&&a.y==0);
    BOZAccumulateLook(&l,10,10);BOZResetLook(&l);a=BOZConsumeLook(&l,1);assert(a.x==0&&a.y==0);
    assert(near(BOZDirection((BOZAxis){0,1}),1.57079632679f));
    BOZLookChannels streams={0};
    BOZAddLookChannel(&streams,BOZSurfaceLook,6,-4);
    BOZAddLookChannel(&streams,BOZFireLook,4,-6);
    BOZCancelLookChannel(&streams,BOZSurfaceLook);
    a=BOZTakeLookChannels(&streams,0.02f);assert(near(a.x,0.08f)&&near(a.y,-0.12f));
    BOZAddLookChannel(&streams,BOZSurfaceLook,10,10); // ended gesture remains queued until consumed
    a=BOZTakeLookChannels(&streams,0.02f);assert(near(a.x,0.2f)&&near(a.y,0.2f));
    a=BOZTakeLookChannels(&streams,0.02f);assert(a.x==0&&a.y==0);
    BOZAddLookChannel(&streams,BOZSurfaceLook,10,10);BOZAddLookChannel(&streams,BOZFireLook,10,10);
    BOZResetLookChannels(&streams);a=BOZTakeLookChannels(&streams,1);assert(a.x==0&&a.y==0);
    BOZFingerOwners owners={0};
    assert(BOZClaimFinger(&owners,1,100,400)==BOZMoveLane);
    assert(BOZClaimFinger(&owners,2,200,400)==0); // second left finger cannot steal stick
    assert(BOZClaimFinger(&owners,3,600,400)==BOZLookLane);
    assert(BOZClaimFinger(&owners,4,700,400)==0);
    BOZReleaseFinger(&owners,2);assert(owners.move==1&&owners.look==3);
    BOZReleaseFinger(&owners,1);assert(owners.move==0&&owners.look==3);
    BOZReleaseFinger(&owners,3);assert(owners.look==0);
    assert(!BOZClaimFinger(&owners,0,100,400));assert(!BOZClaimFinger(&owners,5,NAN,400));
    puts("PASS: dead zone, bounded diagonals, invalid input, relative look consumption and cancellation");
}
