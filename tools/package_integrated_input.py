#!/usr/bin/env python3
"""Embed the native input module into the verified, unsigned BOZ baseline."""
import copy,hashlib,json,pathlib,plistlib,struct,sys,zipfile
BASELINE_SHA='4afd45ed923807c5f02e63cba23ee6e9fd27a01abd7fc4db6232cb3c0cefae0c'
DEPENDENCY='@loader_path/Frameworks/BOZModernInput.dylib'
ROOT='Payload/blackops.app/'
def digest(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        while data:=f.read(1024*1024):h.update(data)
    return h.hexdigest()
def commands(blob):
    if len(blob)<32:raise ValueError('Truncated Mach-O')
    magic,cpu,_,kind,count,total,_,_=struct.unpack_from('<8I',blob)
    if magic!=0xfeedfacf or cpu!=0x100000c:raise ValueError('Expected thin ARM64 Mach-O')
    if kind not in (2,6):raise ValueError('Expected executable or dylib')
    end=32+total
    if end>len(blob) or count>1000:raise ValueError('Invalid command extent')
    pos=32;result=[]
    for _ in range(count):
        if pos+8>end:raise ValueError('Truncated load command')
        cmd,size=struct.unpack_from('<II',blob,pos)
        if size<8 or size%8 or pos+size>end:raise ValueError('Invalid load command size')
        if cmd==29:raise ValueError('Input must not contain a code signature')
        result.append((cmd,pos,size));pos+=size
    if pos!=end:raise ValueError('Command byte count mismatch')
    return result

def add_dependency(blob):
    parsed=commands(blob)
    if struct.unpack_from('<I',blob,12)[0]!=2:raise ValueError('Expected executable')
    first=len(blob)
    for cmd,pos,size in parsed:
        if cmd==12:
            name_offset=struct.unpack_from('<I',blob,pos+8)[0]
            if not 24<=name_offset<size:raise ValueError('Invalid dylib name offset')
            if blob[pos+name_offset:pos+size].split(b'\0',1)[0]==DEPENDENCY.encode():raise ValueError('Already integrated')
        if cmd==25:
            if size<72:raise ValueError('Invalid segment')
            count=struct.unpack_from('<I',blob,pos+64)[0]
            if size<72+80*count:raise ValueError('Invalid sections')
            for n in range(count):
                offset=struct.unpack_from('<I',blob,pos+72+n*80+48)[0]
                if offset:first=min(first,offset)
    payload=DEPENDENCY.encode()+b'\0';size=(24+len(payload)+7)&~7
    count,total=struct.unpack_from('<II',blob,16);end=32+total
    if end+size>first or any(blob[end:end+size]):raise ValueError('No verified zero header padding')
    result=bytearray(blob)
    result[end:end+size]=struct.pack('<6I',12,size,24,0,0,0)+payload+b'\0'*(size-24-len(payload))
    struct.pack_into('<II',result,16,count+1,total+size)
    commands(result)
    if result[first:]!=blob[first:]:raise ValueError('Native code/data changed')
    return bytes(result)

def package(baseline,module,output):
    if digest(baseline)!=BASELINE_SHA:raise ValueError('Baseline checksum mismatch')
    library=pathlib.Path(module).read_bytes();commands(library)
    if struct.unpack_from('<I',library,12)[0]!=6:raise ValueError('Input module must be dylib')
    output=pathlib.Path(output);output.parent.mkdir(parents=True,exist_ok=True)
    tmp=output.with_suffix('.building.ipa');preserved={}
    with zipfile.ZipFile(baseline) as src:
        entries=src.infolist();names=[i.filename for i in entries]
        if len(names)!=len(set(names)):raise ValueError('Duplicate baseline members')
        if ROOT+'Frameworks/BOZModernInput.dylib' in names:raise ValueError('Baseline already includes module')
        original=src.read(ROOT+'blackops');binary=add_dependency(original)
        info=plistlib.loads(src.read(ROOT+'Info.plist'))
        if info.get('CFBundleExecutable')!='blackops':raise ValueError('Unexpected executable')
        bundle_id=info['CFBundleIdentifier'];info['CFBundleVersion']='135.20';info['BOZIntegratedInputVersion']='1.0-test'
        replacements={ROOT+'blackops':binary,ROOT+'Info.plist':plistlib.dumps(info,fmt=plistlib.FMT_BINARY)}
        with zipfile.ZipFile(tmp,'w',allowZip64=True) as dst:
            for entry in entries:
                if '/_CodeSignature/' in entry.filename or entry.filename.endswith('/embedded.mobileprovision'):continue
                if entry.filename in replacements:
                    dst.writestr(copy.copy(entry),replacements[entry.filename]);continue
                h=hashlib.sha256()
                with src.open(entry) as read,dst.open(copy.copy(entry),'w') as write:
                    while chunk:=read.read(1024*1024):h.update(chunk);write.write(chunk)
                preserved[entry.filename]=h.hexdigest()
            dst.writestr(ROOT+'Frameworks/BOZModernInput.dylib',library,compress_type=zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(tmp) as check:
        names=check.namelist()
        if len(names)!=len(set(names)):raise ValueError('Duplicate output members')
        for name,wanted in preserved.items():
            h=hashlib.sha256()
            with check.open(name) as read:
                while chunk:=read.read(1024*1024):h.update(chunk)
            if h.hexdigest()!=wanted:raise ValueError('Asset changed: '+name)
        if check.read(ROOT+'blackops')!=binary:raise ValueError('Executable mismatch')
        if check.read(ROOT+'Frameworks/BOZModernInput.dylib')!=library:raise ValueError('Module mismatch')
        if plistlib.loads(check.read(ROOT+'Info.plist'))['CFBundleIdentifier']!=bundle_id:raise ValueError('Bundle ID changed')
    tmp.replace(output)
    manifest={'baseline_sha256':BASELINE_SHA,'module_sha256':digest(module),'ipa_sha256':digest(output),'bundle_id':bundle_id,'build':'135.20','preserved_members':len(preserved),'code_and_data_unchanged':True}
    output.with_suffix('.verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest))
if __name__=='__main__':package(*sys.argv[1:])
