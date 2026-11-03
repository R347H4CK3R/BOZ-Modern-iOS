"""Repair three pinned Marmalade scanners for non-segment load commands.

Strata prepends LC_ID_DYLIB. The original B.NE instructions skip cmdsize
advancement, repeatedly inspecting that command instead of the next segment.
Advance on every load command, preserving the original section-search logic.
"""
import importlib.util
import struct
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('s3e_data', 'repair/tools/s3e_data.py')
s3e = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = s3e
spec.loader.exec_module(s3e)

PATCHES = [(0x6abec, 0x6ac28, 0x6ac20),
           (0x6acc8, 0x6ad04, 0x6acfc),
           (0x6addc, 0x6ae18, 0x6ae10)]

def bne(site, destination):
    delta = destination - site
    assert delta % 4 == 0 and -(1 << 20) <= delta < (1 << 20)
    return 0x54000001 | (((delta // 4) & 0x7ffff) << 5)

def patch(path):
    blob = bytearray(Path(path).read_bytes())
    sections = s3e.parse_sections(blob)
    assert sections['__TEXT', '__text'].file_offset == 0x76b8
    seed = s3e.calculate_code_seed(blob, sections)
    payload = sections['__S3E_DATA', 's3e_data']
    begin, end = payload.file_offset, payload.file_offset + payload.size
    plaintext = s3e.decode_s3e_data(blob[begin:end], seed)
    for site, before, after in PATCHES:
        actual = struct.unpack_from('<I', blob, site)[0]
        assert actual == bne(site, before), f'Unexpected scanner instruction at {site:#x}'
        struct.pack_into('<I', blob, site, bne(site, after))
    new_seed = s3e.calculate_code_seed(blob, sections)
    blob[begin:end] = s3e.encode_s3e_data(plaintext, new_seed)
    assert s3e.decode_s3e_data(blob[begin:end], new_seed) == plaintext
    Path(path).write_bytes(blob)
    print(f'Repaired 3 load-command scanners; preserved S3E plaintext; seed {seed:08x}->{new_seed:08x}')

if __name__ == '__main__':
    patch(sys.argv[1])
