"""Trace pinned ARM64 Marmalade startup calls without changing their results.

Uses zero-filled executable header padding for ABI-preserving trampolines.
Re-encrypts S3E data after modifying hashed instructions. Run after normalization.
"""
import importlib.util
import struct
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('s3e_data', 'repair/tools/s3e_data.py')
s3e = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = s3e
spec.loader.exec_module(s3e)

CALLS = [
    (0x66f8c, 0x92894, 'memory-bootstrap'),
    (0x66f94, 0x64248, 'exec-init'),
    (0x642e0, 0x84cfc, 'device-init-early'),
    (0x642e8, 0x6ab04, 'setup-paths'),
    (0x6ab20, 0xbd548, 'installed-location'),
    (0x6ab3c, 0xbd5ac, 'data-location'),
    (0x64308, 0x64ba4, 'read-config'),
    (0x64324, 0x86018, 'physical-memory-kb'),
    (0x643ac, 0x84cfc, 'device-init-late'),
    (0x6440c, 0x62b1c, 'embedded-executable'),
    (0x64424, 0x6a92c, 'code-hash'),
    (0x66fc4, 0x64a7c, 'get-executable'),
    (0x66fe4, 0x63e48, 'push-executable'),
    (0x66ff4, 0x64620, 'execute-loop'),
]

def branch(pc, target):
    delta = target - pc
    assert delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27)
    return 0x94000000 | ((delta // 4) & 0x3ffffff)

def adr(pc, target):
    delta = target - pc
    assert -(1 << 20) <= delta < (1 << 20)
    return 0x10000000 | ((delta & 3) << 29) | (((delta >> 2) & 0x7ffff) << 5)

def trampoline(start, target, name):
    # Stack slot 0 holds Darwin's variadic argument; the saved frame is at +16.
    words = [0xd101c3ff, 0xa9017bfd, 0x910043fd,
             0xa90207e0, 0xa9030fe2, 0xa90417e4, 0xa9051fe6, 0xa90627e8,
             0, 0,
             0xa94207e0, 0xa9430fe2, 0xa94417e4, 0xa9451fe6, 0xa94627e8,
             0, 0xf90013e0, 0xf90003e0, 0, 0,
             0xf94013e0, 0xa9417bfd, 0x9101c3ff, 0xd65f03c0]
    first = ('BOZ-stage=' + name + ' enter\n\0').encode()
    second = ('BOZ-stage=' + name + ' result=%d\n\0').encode()
    strings = start + len(words) * 4
    words[8] = adr(start + 8 * 4, strings)
    words[9] = branch(start + 9 * 4, 0x84180)
    words[15] = branch(start + 15 * 4, target)
    words[18] = adr(start + 18 * 4, strings + len(first))
    words[19] = branch(start + 19 * 4, 0x84180)
    result = struct.pack('<' + 'I' * len(words), *words) + first + second
    return result + bytes((-len(result)) % 16)

def patch(path):
    data = bytearray(Path(path).read_bytes())
    sections = s3e.parse_sections(data)
    assert sections['__TEXT', '__text'].file_offset == 0x76b8
    command_end = 32 + struct.unpack_from('<I', data, 20)[0]
    assert command_end < 0x4000, 'No safe executable header padding'
    seed = s3e.calculate_code_seed(data, sections)
    payload = sections['__S3E_DATA', 's3e_data']
    plain = s3e.decode_s3e_data(data[payload.file_offset:payload.file_offset+payload.size], seed)
    cursor = 0x4000
    for site, target, name in CALLS:
        expected = branch(site, target)
        assert struct.unpack_from('<I', data, site)[0] == expected, name + ': unexpected instruction'
        code = trampoline(cursor, target, name)
        assert cursor + len(code) <= 0x7000
        assert not any(data[cursor:cursor+len(code)]), 'Padding contains data'
        data[cursor:cursor+len(code)] = code
        struct.pack_into('<I', data, site, branch(site, cursor))
        cursor += len(code)
    new_seed = s3e.calculate_code_seed(data, sections)
    data[payload.file_offset:payload.file_offset+payload.size] = s3e.encode_s3e_data(plain, new_seed)
    assert s3e.decode_s3e_data(data[payload.file_offset:payload.file_offset+payload.size], new_seed) == plain
    Path(path).write_bytes(data)
    print(f'Traced {len(CALLS)} startup boundaries; preserved S3E plaintext; seed {seed:08x}->{new_seed:08x}')

if __name__ == '__main__':
    patch(sys.argv[1])
