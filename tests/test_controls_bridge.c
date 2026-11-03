#include "BOZControlsBridge.h"
#include <assert.h>
#include <stdio.h>
int main(int argc,char **argv) {
    assert(BOZControlsTarget(0,1,1,1,0)==0);
    assert(BOZControlsTarget(BOZAim,1,1,1,0)==BOZAim); // aiming never creates fire
    assert(BOZControlsTarget(BOZFire|BOZAim,1,1,1,0)==3);
    assert(BOZControlsTarget(7,0,1,1,0)==0);
    assert(BOZControlsTarget(7,1,0,1,0)==0);
    assert(BOZControlsTarget(7,1,1,0,0)==0);
    assert(BOZControlsTarget(7,1,1,1,1)==0);
    uint32_t words[]={0x90000010,0xf941de11,0x910ee210,0xd61f0220};
    // offset 0x3b8 in both LDR (scaled) and ADD (unscaled).
    words[1]=0xf9400211u | ((0x3b8u/8)<<10);
    words[2]=0x91000210u | (0x3b8u<<10);
    assert(BOZControlsThunkSlot(words,0x100061234)==0x1000613b8);
    words[2]^=1u<<10;assert(!BOZControlsThunkSlot(words,0x100061234));
    words[2]^=1u<<10;words[3]=0;assert(!BOZControlsThunkSlot(words,0x100061234));
    if(argc>1) {
        FILE *file=fopen(argv[1],"rb");assert(file);
        assert(!fseek(file,0xf4c8c,SEEK_SET));assert(fread(words,4,4,file)==4);fclose(file);
        assert(BOZControlsThunkSlot(words,0x10c8f4c8c)==0x10ce1b3b8);
    }
    puts("PASS: manual-only fire, hold combinations, pause/disable/edit release targets and guarded ARM64 import decoding");
    return 0;
}
