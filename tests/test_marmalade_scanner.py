"""Execute the real pinned ARM64 scanners against Strata-style Mach-O headers.

Usage: python tests/test_marmalade_scanner.py path/to/blackops
Requires unicorn. Only OS dladdr, string comparison, errors and clock are stubbed.
"""
import struct
import sys
from pathlib import Path
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import (UC_ARM64_REG_X0, UC_ARM64_REG_X1,
    UC_ARM64_REG_SP, UC_ARM64_REG_LR, UC_ARM64_REG_PC)

BASE = 0x10c800000  # Nonzero slide matching the uploaded failing launch.
SLIDE = BASE - 0x100000000
STACK = 0x200000000

def read_string(uc, address):
    result = bytearray()
    while True:
        value = uc.mem_read(address + len(result), 1)[0]
        if not value:
            return bytes(result)
        result.append(value)
        assert len(result) < 4096

def with_command(blob, index):
    data = bytearray(blob)
    count, size = struct.unpack_from('<II', data, 16)
    pos = 32
    for _ in range(index):
        pos += struct.unpack_from('<I', data, pos + 4)[0]
    command = struct.pack('<6I', 13, 32, 24, 2, 0x10000, 0x10000) + b'blackops'
    data[pos+32:32+size+32] = data[pos:32+size]
    data[pos:pos+32] = command
    struct.pack_into('<II', data, 16, count+1, size+32)
    return data

def run(blob, function):
    uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
    uc.mem_map(BASE, 0x1000000)
    uc.mem_write(BASE, bytes(blob))
    uc.mem_map(0x118031000+SLIDE, 0x1000)
    # Engine's embedded-code pointer, normally initialized before these scans.
    uc.mem_write(0x118031bb0+SLIDE, struct.pack('<Q', BASE+0xf4000))
    uc.mem_map(STACK, 0x10000)
    uc.reg_write(UC_ARM64_REG_SP, STACK+0xf000)
    uc.reg_write(UC_ARM64_REG_LR, BASE+0xff0000)
    uc.reg_write(UC_ARM64_REG_X0, STACK+0x100)
    uc.reg_write(UC_ARM64_REG_X1, STACK+0x200)
    uc.mem_write(STACK+0x100, b'__text\0')
    errors = []
    def hook(uc, address, size, data):
        if address == BASE+0xc6df8:  # dladdr
            out = uc.reg_read(UC_ARM64_REG_X1)
            uc.mem_write(out, struct.pack('<4Q', 0, BASE, 0, 0))
            uc.reg_write(UC_ARM64_REG_X0, 1)
        elif address == BASE+0x61fc4:  # IwStrcmp
            a = read_string(uc, uc.reg_read(UC_ARM64_REG_X0))
            b = read_string(uc, uc.reg_read(UC_ARM64_REG_X1))
            uc.reg_write(UC_ARM64_REG_X0, 0 if a == b else 1)
        elif address == BASE+0x75220:  # IwDebugErrorShow
            errors.append(read_string(uc, uc.reg_read(UC_ARM64_REG_X0)))
            uc.reg_write(UC_ARM64_REG_X0, 0)
        elif address == BASE+0xae2b8:  # s3eTimerGetMs
            uc.reg_write(UC_ARM64_REG_X0, 0)
        elif address == BASE+0xff0000:
            uc.emu_stop()
            return
        else:
            return
        uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_LR))
    for offset in (0xc6df8, 0x61fc4, 0x75220, 0xae2b8, 0xff0000):
        uc.hook_add(UC_HOOK_CODE, hook, begin=BASE+offset, end=BASE+offset)
    uc.emu_start(BASE+function, BASE+0xff0004, count=80000000)
    assert uc.reg_read(UC_ARM64_REG_PC) == BASE+0xff0000, 'scanner did not return'
    return uc.reg_read(UC_ARM64_REG_X0), bytes(uc.mem_read(STACK+0x100, 16)), errors

def main():
    blob = Path(sys.argv[1]).read_bytes()
    for name, data in [('original-order', blob), ('Strata-ID-first', with_command(blob, 0)),
                       ('ID-between-segments', with_command(blob, 1))]:
        value, _, errors = run(data, 0x6ab84)
        assert value != 0 and not errors, (name, 'section lookup failed', errors)
        for function, description in [(0x6ac58, 'load displacement'), (0x6ad64, 'data address')]:
            value, _, errors = run(data, function)
            assert value == 0 and not errors, (name, description, errors)
        value, output, errors = run(data, 0x6a92c)
        assert value == 0 and not errors, (name, 'code hash failed', errors)
        expected = 1234
        for byte in blob[0x76b8:0x5b8000]:
            expected = (byte + 31 * expected) & 0xffffffff
        assert struct.unpack_from('<I', output)[0] == expected, 'runtime hash differs from package seed'
        print('PASS:', name, 'section lookup, displacement, data address and code-hash seed')

if __name__ == '__main__':
    main()
