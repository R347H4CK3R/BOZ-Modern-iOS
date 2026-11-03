import struct,sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
magic,cpu,_,_,n,_,_,_=struct.unpack_from("<8I",b)
assert magic==0xfeedfacf and cpu==0x100000c, "Expected ARM64"
p=32
sdk=None
for _ in range(n):
    command,size=struct.unpack_from("<II",b,p)
    assert size>=8 and p+size<=len(b)
    if command==0x24:
        minimum,sdk=struct.unpack_from("<II",b,p+8)
    elif command==0x32:
        _,minimum,sdk=struct.unpack_from("<III",b,p+8)
    p+=size
assert sdk==0x000c0000, f"Expected iOS 12 linked SDK for legacy dylib layout, got {sdk}"
print("Verified ARM64 and iOS 12 linked SDK compatibility epoch")
