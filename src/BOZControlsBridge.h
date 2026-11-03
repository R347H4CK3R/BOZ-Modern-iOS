#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
static inline unsigned BOZControlsStateFlag(const char *name) {
    if(!strcmp(name,"GameStateIngame")) return 1;
    if(!strcmp(name,"GameStatePaused")) return 2;
    return 0;
}
static inline int BOZControlsStatesPlayable(unsigned flags) { return (flags&3)==1; }
enum { BOZFire=1, BOZAim=2, BOZReload=4, BOZSwap=8 };
static inline unsigned BOZControlsTarget(unsigned requested,int enabled,int active,int gameplay,int editing) {
    return enabled && active && gameplay && !editing ? requested & 15u : 0;
}
// Marmalade's ARM64 import thunks: ADRP x16; LDR x17; ADD x16; BR x17.
static inline uintptr_t BOZControlsThunkSlot(const uint32_t *w,uintptr_t pc) {
    if((w[0]&0x9f00001fu)!=0x90000010u || (w[1]&0xffc003ffu)!=0xf9400211u ||
       (w[2]&0xffc003ffu)!=0x91000210u || w[3]!=0xd61f0220u) return 0;
    intptr_t imm=(intptr_t)((((w[0]>>5)&0x7ffffu)<<2)|((w[0]>>29)&3u));
    if(imm&(1<<20)) imm-=1<<21;
    uintptr_t load=((w[1]>>10)&0xfffu)*8u,add=(w[2]>>10)&0xfffu;
    if(load!=add) return 0;
    return (pc & ~(uintptr_t)0xfff)+(imm*4096)+load;
}
