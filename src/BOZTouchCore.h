#pragma once
/* Screen axes: +x right, +y down. No target/aim/fire logic belongs here. */
typedef struct { float x,y; } BOZAxis;
typedef struct { float dx,dy; } BOZLook;
BOZAxis BOZStick(float dx,float dy,float radius,float deadzone);
float BOZDirection(BOZAxis axis);
void BOZAccumulateLook(BOZLook *look,float dx,float dy);
BOZAxis BOZConsumeLook(BOZLook *look,float scale);
void BOZResetLook(BOZLook *look);
#include <stdint.h>
typedef struct { uintptr_t move,look; } BOZFingerOwners;
enum { BOZMoveLane=1, BOZLookLane=2 };
int BOZClaimFinger(BOZFingerOwners *owners,uintptr_t finger,float x,float split);
void BOZReleaseFinger(BOZFingerOwners *owners,uintptr_t finger);
