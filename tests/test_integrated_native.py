"""Verify the retained engine's real analog event and native aim-assist flag ABI."""
import pathlib,struct,sys
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm64_const import *
b=pathlib.Path(sys.argv[1]).read_bytes();base=0x10c800000;obj=0x200000000
for left in (0,1):
    uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(base,0x400000);uc.mem_write(base,b[:0x400000]);uc.mem_map(base+0x645000,0x1000);uc.mem_map(obj,0x4000)
    uc.mem_write(base+0x645848,struct.pack('<I',123));uc.reg_write(UC_ARM64_REG_X0,obj);uc.reg_write(UC_ARM64_REG_X1,left);uc.reg_write(UC_ARM64_REG_SP,obj+0x3ff0)
    for reg,value in zip((UC_ARM64_REG_S0,UC_ARM64_REG_S1,UC_ARM64_REG_S2,UC_ARM64_REG_S3,UC_ARM64_REG_S4),(0.4,0.75,3.5,0.2,-0.3)):
        uc.reg_write(reg,struct.unpack('<I',struct.pack('<f',value))[0])
    calls=[]
    def publisher(uc,address,size,data):
        assert uc.reg_read(UC_ARM64_REG_X0)==obj+0x38
        assert uc.reg_read(UC_ARM64_REG_X1)==123
        packet=bytes(uc.mem_read(uc.reg_read(UC_ARM64_REG_X2),21))
        vals=struct.unpack('<5fB',packet)
        for actual,wanted in zip(vals[:5],(0.4,0.75,3.5,0.2,-0.3)):assert abs(actual-wanted)<1e-5
        assert vals[5]==left
        assert uc.reg_read(UC_ARM64_REG_X3)==uc.reg_read(UC_ARM64_REG_X4)==0
        calls.append(1);uc.emu_stop()
    uc.hook_add(UC_HOOK_CODE,publisher,begin=base+0x3be184,end=base+0x3be184)
    uc.emu_start(base+0x1ef214,base+0x3be188,count=100);assert calls==[1]
print('PASS: real left/right analog publisher preserves direction, magnitude, speed and raw axes')
for aim in (0,1):
    uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);uc.mem_map(base,0x200000);uc.mem_write(base,b[:0x200000]);uc.mem_map(base+0x637000,0x1000);uc.mem_map(obj,0x4000)
    uc.mem_write(obj+0x78,struct.pack('<Q',obj+0x1000));uc.mem_write(base+0x637228,struct.pack('<Q',obj+0x2000));uc.mem_write(obj+0x2132,bytes([aim]))
    uc.mem_write(obj+0x1145,bytes([1-aim]));uc.reg_write(UC_ARM64_REG_X0,obj);uc.reg_write(UC_ARM64_REG_LR,base+0xff000)
    uc.emu_start(base+0x1db158,base+0xff000,count=50);assert bytes(uc.mem_read(obj+0x1145,1))==bytes([aim])
print('PASS: real native aim-assist sync copies config+0x132 to HUD player+0x145; zero disables it')
