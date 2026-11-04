#include "BOZTouchCore.h"
#include <math.h>
static BOZAxis Bound(float x,float y) {
    if(!isfinite(x)||!isfinite(y)) return (BOZAxis){0,0};
    float length=hypotf(x,y);
    if(length>1) { x/=length;y/=length; }
    return (BOZAxis){x,y};
}
BOZAxis BOZStick(float dx,float dy,float radius,float deadzone) {
    if(!isfinite(dx)||!isfinite(dy)||!isfinite(radius)||radius<=0||!isfinite(deadzone)||deadzone<0||deadzone>=1) return (BOZAxis){0,0};
    BOZAxis a=Bound(dx/radius,dy/radius);float length=hypotf(a.x,a.y);
    if(length<=deadzone) return (BOZAxis){0,0};
    float response=(length-deadzone)/(1-deadzone);
    return (BOZAxis){a.x*response/length,a.y*response/length};
}
float BOZDirection(BOZAxis a) { return a.x||a.y?atan2f(a.y,a.x):0; }
void BOZAccumulateLook(BOZLook *look,float dx,float dy) {
    if(!look||!isfinite(dx)||!isfinite(dy)) return;
    look->dx=fmaxf(-8192,fminf(8192,look->dx+dx));
    look->dy=fmaxf(-8192,fminf(8192,look->dy+dy));
}
void BOZResetLook(BOZLook *look) { if(look) look->dx=look->dy=0; }
BOZAxis BOZConsumeLook(BOZLook *look,float scale) {
    if(!look) return (BOZAxis){0,0};
    BOZAxis a=isfinite(scale)&&scale>=0?Bound(look->dx*scale,look->dy*scale):(BOZAxis){0,0};
    BOZResetLook(look);return a;
}
int BOZClaimFinger(BOZFingerOwners *owners,uintptr_t finger,float x,float split) {
    if(!owners||!finger||!isfinite(x)||!isfinite(split)||split<=0||owners->move==finger||owners->look==finger) return 0;
    if(x<split) { if(owners->move) return 0;owners->move=finger;return BOZMoveLane; }
    if(owners->look) return 0;
    owners->look=finger;return BOZLookLane;
}
void BOZReleaseFinger(BOZFingerOwners *owners,uintptr_t finger) {
    if(!owners) return;
    if(owners->move==finger) owners->move=0;
    if(owners->look==finger) owners->look=0;
}
