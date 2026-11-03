"""Execute real pinned ARM64 button handlers and an import thunk under ASLR."""
import struct,sys
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm64_const import UC_ARM64_REG_X0,UC_ARM64_REG_X1,UC_ARM64_REG_X2,UC_ARM64_REG_X3,UC_ARM64_REG_X4,UC_ARM64_REG_PC,UC_ARM64_REG_LR

b=Path(sys.argv[1]).read_bytes();base=0x10c800000;obj=0x200000000
for name,offset,field,event_offset in [('fire',0x1ef2c4,0x79,0xc),('aim',0x1ef384,0x7c,0x14),('reload',0x1ef344,0x7b,0x10)]:
    for down in (0,1):
        uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(base,0x400000);uc.mem_write(base,b[:0x400000]);uc.mem_map(obj,0x1000);uc.mem_map(base+0x645000,0x1000)
        uc.mem_write(base+0x645840+event_offset,struct.pack('<I',123))
        uc.mem_write(obj+field,bytes([1-down]));uc.reg_write(UC_ARM64_REG_X0,obj);uc.reg_write(UC_ARM64_REG_X1,down);uc.reg_write(UC_ARM64_REG_X2,0)
        events=[]
        def event(uc,address,size,data):
            events.append([uc.reg_read(r) for r in (UC_ARM64_REG_X0,UC_ARM64_REG_X1,UC_ARM64_REG_X2,UC_ARM64_REG_X3,UC_ARM64_REG_X4)]);uc.emu_stop()
        uc.hook_add(UC_HOOK_CODE,event,begin=base+0x3be184,end=base+0x3be184)
        uc.emu_start(base+offset,base+0x3be188,count=100)
        assert bytes(uc.mem_read(obj+field,1))==bytes([down])
        assert events==[[obj+0x38,123,down,0,0]],(name,down,events)
        print('PASS:',name,'pressed='+str(down),'native field and action event match')

uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(base,0x100000);uc.mem_write(base,b[:0x100000]);uc.mem_map(base+0x61b000,0x1000)
slot=base+0x61b3b8;hook=base+0xff000;uc.mem_write(slot,struct.pack('<Q',hook));uc.reg_write(UC_ARM64_REG_X0,42)
calls=[]
def imported(uc,address,size,data):
    calls.append(uc.reg_read(UC_ARM64_REG_X0));uc.emu_stop()
uc.hook_add(UC_HOOK_CODE,imported,begin=hook,end=hook)
uc.emu_start(base+0xf4c8c,hook+4,count=20)
assert calls==[42]
print('PASS: real Marmalade import thunk dispatches through the replaced data cell under ASLR')

# Execute the real active-state removal routine used by the native pause
# transition, confirming its pointer-array/count layout instead of inferring
# pause from the continued existence of a player object.
from unicorn.arm64_const import UC_ARM64_REG_SP
uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(base,0x400000);uc.mem_write(base,b[:0x400000]);uc.mem_map(obj,0x4000)
vector=obj+0xa0;array=obj+0x1000;arg=obj+0x2000
playing=obj+0x2100;paused=obj+0x2140
uc.mem_write(vector,struct.pack('<QII',array,2,8))
uc.mem_write(array,struct.pack('<QQ',playing,paused));uc.mem_write(arg,struct.pack('<Q',paused))
uc.mem_write(playing,b'GameStateIngame\0');uc.mem_write(paused,b'GameStatePaused\0')
uc.reg_write(UC_ARM64_REG_X0,vector);uc.reg_write(UC_ARM64_REG_X1,arg)
uc.reg_write(UC_ARM64_REG_LR,base+0xff000);uc.reg_write(UC_ARM64_REG_SP,obj+0x3ff0)
uc.emu_start(base+0x3e2564,base+0xff000,count=200)
assert uc.reg_read(UC_ARM64_REG_X0)==1
assert struct.unpack('<I',uc.mem_read(vector+8,4))[0]==1
assert struct.unpack('<Q',uc.mem_read(array,8))[0]==playing
assert b[0x3e2c0c:0x3e2c10]==bytes.fromhex('60820291'), 'native deactivate must use manager+0xa0'
print('PASS: native active-state vector removes pause while retaining in-game state')
