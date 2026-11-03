"""Order legacy Marmalade segments without moving any virtual address.

Repack file bytes, remap dyld segment indices and nlist section ordinals.
Fail closed on relocation/fixup formats this legacy-only tool does not support.
"""
import importlib.util
import struct
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('macho_helpers', 'repair/tools/macho_merge_data_segments.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def normalize(path):
    original = Path(path).read_bytes()
    header, commands, segments = m.parse_macho(original)
    expected = {'__PAGEZERO','__TEXT','__DATA','__S3E_META','__S3E_DATA','__LINKEDIT'}
    assert {s['name'] for s in segments} == expected
    assert not any(x['nreloc'] for s in segments for x in s['sections'])
    assert not any(c['command'] == 0x80000034 for c in commands), 'Chained fixups unsupported'
    ordered = sorted(segments, key=lambda s:s['vmaddr'])
    assert ordered[-1]['name'] == '__LINKEDIT'
    for a,b in zip(ordered,ordered[1:]):
        assert a['vmaddr']+a['vmsize'] <= b['vmaddr'], 'Overlapping VM ranges'
    mappings=[]
    cursor=0
    for s in ordered:
        start=0 if s['name'] in ('__PAGEZERO','__TEXT') else m.align_up(cursor,m.PAGE_SIZE)
        s['new_fileoff']=start
        if s['filesize']:
            mappings.append((s['fileoff'],s['fileoff']+s['filesize'],start))
            cursor=start+s['filesize']
    def translate(value):
        if not value:return 0
        for lo,hi,new in mappings:
            if lo<=value<hi:return new+value-lo
        raise ValueError('Unmapped file offset '+hex(value))
    out=bytearray(cursor)
    for lo,hi,new in mappings:out[new:new+hi-lo]=original[lo:hi]
    old_index={s['name']:i for i,s in enumerate(segments)}
    segmap={old_index[s['name']]:(i,s['vmaddr']) for i,s in enumerate(ordered)}
    sectionmap={}
    ordinal=1
    segment_commands=[]
    for s in ordered:
        c=bytearray(s['bytes'])
        struct.pack_into('<Q',c,40,s['new_fileoff'])
        for i,section in enumerate(s['sections']):
            sectionmap[section['old_ordinal']]=ordinal;ordinal+=1
            if section['offset']:struct.pack_into('<I',c,72+i*80+48,translate(section['offset']))
        segment_commands.append(c)
    next_segment=iter(segment_commands)
    newcommands=[]
    for c in commands:
        kind=c['command']
        if kind==0x19:newcommands.append(next(next_segment));continue
        data=bytearray(c['bytes'])
        if kind in (0x22,0x80000022):
            fields=list(struct.unpack_from('<10I',data,8))
            for j in range(0,8,2):
                off,size=fields[j:j+2]
                if not size:continue
                oldstream=original[off:off+size]
                transform=m.transform_rebase_stream if j==0 else m.transform_bind_stream
                newstream=transform(oldstream,segments,segmap)
                assert len(newstream)==size, 'Unexpected fixup stream size change'
                newoff=translate(off);out[newoff:newoff+size]=newstream;fields[j]=newoff
            fields[8]=translate(fields[8])
            struct.pack_into('<10I',data,8,*fields)
        elif kind==2:
            symoff,count,stroff,strsize=struct.unpack_from('<4I',data,8)
            symoff=translate(symoff)
            struct.pack_into('<4I',data,8,symoff,count,translate(stroff),strsize)
            for i in range(count):
                pos=symoff+i*16
                if out[pos+4]&0x0e==0x0e and out[pos+5]:out[pos+5]=sectionmap[out[pos+5]]
        elif kind==0xb:
            fields=list(struct.unpack_from('<18I',data,8))
            assert fields[15]==0 and fields[17]==0, 'Dynamic relocations unsupported'
            for i in (6,8,10,12,14,16):fields[i]=translate(fields[i])
            struct.pack_into('<18I',data,8,*fields)
        elif kind in (0x1d,0x1e,0x26,0x29,0x2b,0x2e,0x80000033):
            offset=struct.unpack_from('<I',data,8)[0]
            struct.pack_into('<I',data,8,translate(offset))
        elif kind in (0x21,0x2c):
            offset=struct.unpack_from('<I',data,8)[0]
            struct.pack_into('<I',data,8,translate(offset))
        elif kind==0x80000028:
            offset=struct.unpack_from('<Q',data,8)[0]
            struct.pack_into('<Q',data,8,translate(offset))
        elif kind==0x31:
            offset=struct.unpack_from('<Q',data,24)[0]
            struct.pack_into('<Q',data,24,translate(offset))
        newcommands.append(data)
    newblob=b''.join(newcommands)
    assert len(newblob)==header[5]
    out[32:32+len(newblob)]=newblob
    _,_,result=m.parse_macho(out)
    assert [s['name'] for s in result]==[s['name'] for s in ordered]
    for s in result:
        before=next(x for x in segments if x['name']==s['name'])
        assert s['vmaddr']==before['vmaddr'] and s['vmsize']==before['vmsize']
        for a,b in zip(s['sections'],before['sections']):
            assert a['addr']==b['addr'] and a['size']==b['size']
        # Encrypted Marmalade sections must be byte-identical after repacking.
        if s['name'] in ('__S3E_DATA','__S3E_META'):
            assert out[s['fileoff']:s['fileoff']+s['filesize']]==original[before['fileoff']:before['fileoff']+before['filesize']]
    assert all(a['vmaddr']<=b['vmaddr'] and a['fileoff']<=b['fileoff'] for a,b in zip(result,result[1:]))
    Path(path).write_bytes(out)
    print('Verified ordered VM/file segments, preserved VM addresses and encrypted payloads, remapped fixups and section ordinals')

if __name__=='__main__':normalize(sys.argv[1])
