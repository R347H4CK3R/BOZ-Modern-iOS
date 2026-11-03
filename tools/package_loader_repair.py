"""Apply the scanner repair to the verified unsigned v4 IPA without recompiling."""
import hashlib
import copy
import plistlib
import shutil
import struct
import sys
import zipfile
from pathlib import Path
from fix_marmalade_scanner import patch

EXPECTED = '3ca0cac43d70e806125ae2129c29f067cb9f3b32d40e34984a6e3f875c00d27e'
ROOT = 'Payload/blackops.app/'

def unsigned_arm64(data):
    assert data[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin 64-bit Mach-O'
    assert struct.unpack_from('<I', data, 4)[0] == 0x100000c, 'Expected ARM64'
    count, size = struct.unpack_from('<II', data, 16)
    pos = 32
    for _ in range(count):
        kind, length = struct.unpack_from('<II', data, pos)
        assert length >= 8 and pos + length <= 32 + size
        if kind == 0x1d:
            assert struct.unpack_from('<I', data, pos+12)[0] == 0, 'Unexpected embedded signature'
        pos += length
    assert pos == 32 + size

def main():
    source, target = map(Path, sys.argv[1:3])
    with source.open('rb') as file:
        assert hashlib.file_digest(file, 'sha256').hexdigest() == EXPECTED, 'Unexpected baseline IPA'
    verify = Path('verify')
    verify.mkdir(exist_ok=True)
    with zipfile.ZipFile(source) as original:
        names = original.namelist()
        assert len(names) == len(set(names)), 'Duplicate archive names'
        info = plistlib.loads(original.read(ROOT+'Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.activision.callofduty.blackopszombies'
        assert info['CFBundleVersion'] == '135.7', 'Expected v4 baseline'
        for name in [ROOT+'blackops', ROOT+'Frameworks/libstdc++.6.dylib',
                     ROOT+'Frameworks/BOZFullscreenFix.dylib']:
            unsigned_arm64(original.read(name))
        binary = verify/'blackops'
        binary.write_bytes(original.read(ROOT+'blackops'))
        patch(binary)
        unsigned_arm64(binary.read_bytes())
        info['CFBundleVersion'] = '135.8'
        info['CFBundleDisplayName'] = 'COD:BOZ Loader Fix v5'
        replacements = {ROOT+'blackops': binary.read_bytes(),
                        ROOT+'Info.plist': plistlib.dumps(info, fmt=plistlib.FMT_BINARY)}
        with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
            for item in original.infolist():
                if item.filename in replacements:
                    output.writestr(copy.copy(item), replacements[item.filename])
                else:
                    with original.open(item) as reader, output.open(copy.copy(item), 'w') as writer:
                        shutil.copyfileobj(reader, writer, length=1024*1024)
        with zipfile.ZipFile(target) as output:
            assert output.testzip() is None, 'Output archive corruption'
            assert output.namelist() == names
            for item in original.infolist():
                if item.filename not in replacements:
                    after = output.getinfo(item.filename)
                    assert (after.CRC, after.file_size) == (item.CRC, item.file_size), item.filename
    print('Verified unsigned ARM64 repair, unchanged assets/libraries and valid archive; build 135.8')

if __name__ == '__main__':
    main()
