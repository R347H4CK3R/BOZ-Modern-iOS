"""Run the pinned game's real credit mutation code; observe its save call.

Does not establish that filesystem serialization or UIKit works on a phone.
"""
import struct
import sys
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm64_const import UC_ARM64_REG_X0,UC_ARM64_REG_X1

blob=Path(sys.argv[1]).read_bytes()
assert blob[0x1d7434:0x1d744c].hex()=='022040b94100012b21509f1a012000b9010080524effff17'
base=0x10c800000
for initial,added,wanted in [(0,1000,1000),(1500,1000,2500),
                              (0,10000,10000),(990000,10000,1000000),
                              (100,-200,0)]:
    uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
    uc.mem_map(base,0x200000);uc.mem_write(base,blob[:0x200000])
    object=0x200000000
    uc.mem_map(object,0x1000);uc.mem_write(object+32,struct.pack('<i',initial))
    uc.reg_write(UC_ARM64_REG_X0,object);uc.reg_write(UC_ARM64_REG_X1,added&0xffffffff)
    saves=[]
    def save(uc,address,size,data):
        saves.append((uc.reg_read(UC_ARM64_REG_X0),uc.reg_read(UC_ARM64_REG_X1)))
        uc.emu_stop()
    uc.hook_add(UC_HOOK_CODE,save,begin=base+0x1d7180,end=base+0x1d7180)
    uc.emu_start(base+0x1d7434,base+0x1d7500,count=50)
    assert struct.unpack('<i',uc.mem_read(object+32,4))[0]==wanted
    assert saves==[(object,0)], 'must invoke original store serialization exactly once'
    print('PASS: balance',initial,'+',added,'=',wanted,'and original save routine called once')
