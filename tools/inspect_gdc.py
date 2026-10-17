#!/usr/bin/env python3
"""Inspect shipped Godot v13 token streams; never executes APK code.
Format reference: godotengine/godot 3.2 modules/gdscript/gdscript_tokenizer.cpp.
"""
import json
import struct
import sys
from pathlib import Path

def inspect(path):
    data=Path(path).read_bytes();assert data[:4]==b'GDSC'
    version,ident_count,const_count,line_count,token_count=struct.unpack_from('<5I',data,4)
    assert version==13
    offset=24;identifiers=[]
    for _ in range(ident_count):
        n=struct.unpack_from('<I',data,offset)[0];offset+=4
        identifiers.append(bytes(x^0xb6 for x in data[offset:offset+n]).rstrip(b'\0').decode());offset+=n
    def variant():
        nonlocal offset
        t=struct.unpack_from('<I',data,offset)[0];offset+=4
        kind=t&0xffff;wide=bool(t&(1<<16))
        if kind==0:return None
        if kind==1:
            x=struct.unpack_from('<I',data,offset)[0];offset+=4;return bool(x)
        if kind in (2,3):
            fmt=('q' if wide else 'i') if kind==2 else ('d' if wide else 'f')
            x=struct.unpack_from('<'+fmt,data,offset)[0];offset+=8 if wide else 4;return x
        if kind==4:
            n=struct.unpack_from('<I',data,offset)[0];offset+=4
            x=data[offset:offset+n].decode();offset+=(n+3)&~3;return x
        if kind in (5,7,14):
            n={5:2,7:3,14:4}[kind];x=struct.unpack_from('<'+str(n)+'f',data,offset);offset+=n*4;return x
        raise ValueError(f'unsupported variant {kind} at {offset}')
    constants=[variant() for _ in range(const_count)]
    offset+=line_count*8;tokens=[]
    for _ in range(token_count):
        if data[offset]&0x80:
            token=struct.unpack_from('<I',data,offset)[0]&~0x80;offset+=4
        else:token=data[offset];offset+=1
        kind=token&255;index=token>>8
        if kind==1:value=identifiers[index]
        elif kind==2:value=json.dumps(constants[index])
        else:value=f'<{kind}:{index}>'
        tokens.append(value)
    return {'path':str(path),'version':version,'identifiers':identifiers,'constants':constants,'tokens':tokens}
if __name__=='__main__':
    result=inspect(sys.argv[1]); print(json.dumps(result,indent=2))
