#!/usr/bin/env python3
"""Compare actual tonneau/spoiler geometry bounds with independently evaluated APK tracks."""
import argparse
import json
from pathlib import Path
import re
import struct
import subprocess
import numpy as np
from convert_assets import REA_GODOT_ROOT, parse_tscn_metadata

repo = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=Path, default=repo/'TeslaMetalViewer/.build/release/TeslaMetalViewer')
a = p.parse_args()
for model, clip_name, source_path, times in [
    ('cybertruck', 'TonneauAnimation', 'Ego/Cybertruck/Tonneau.tscn', [0, 2.5, 5, 7.5, 10, 5, 0]),
    ('modelx_legacy', 'SpoilerAnimation', 'Ego/X/Model_X.tscn', [0, .25, .5, .75, 1, .5, 0]),
]:
    data = (repo/'models'/f'{model}.glb').read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20+length]); raw = data[28+length:]
    nodes = doc['nodes']; parents = {c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    def path(i): return (path(parents[i])+'/' if i in parents else '')+nodes[i]['name']
    paths = [path(i) for i in range(len(nodes))]
    exported = next(c for c in doc['extras']['sourceAnimations'] if c['name'] == clip_name)
    source = next(c for c in parse_tscn_metadata(REA_GODOT_ROOT/source_path)['animations'] if c['name'] == clip_name)
    tracks = [t for t in source['tracks'] if not t['target'].startswith('TonneauCover:')]
    assert len(tracks) == (28 if model == 'cybertruck' else 2)
    assert len(exported['tracks']) == len(tracks)
    speed = exported.get('playbackSpeed', 1)
    assert speed == (3 if model == 'cybertruck' else 1)
    bindings = []
    for original, track in zip(tracks, exported['tracks']):
        assert original['values'] == track['values'] and original['times'] == track['times']
        target = original['target']
        if model == 'cybertruck': target = 'Tonneau_Cover/Tonneau/'+target
        assert track['target'] == target
        target, prop = target.split(':')
        matches = [i for i,pth in enumerate(paths) if pth.endswith('/'+target)]
        assert matches == [track['node']]
        bindings.append((matches[0],prop,original))
    if model == 'modelx_legacy':
        assert any(n['name']=='Spoiler_Active' and 'mesh' in n for n in nodes)
        assert not any(n['name']=='Spoiler_Static' and 'mesh' in n for n in nodes)
    def positions(index):
        ac = doc['accessors'][index]; view = doc['bufferViews'][ac['bufferView']]
        offset = view.get('byteOffset',0)+ac.get('byteOffset',0)
        return np.ndarray((ac['count'],3),dtype='<f4',buffer=raw,offset=offset,
                          strides=(view.get('byteStride',12),4)).copy()
    def bounds(time):
        local = [np.asarray(n.get('matrix',np.eye(4).flatten().tolist())).reshape(4,4).T.copy() for n in nodes]
        for index,prop,track in bindings:
            values=np.asarray(track['values']); ts=track['times']
            v=np.array([np.interp(time*speed,ts,values[:,axis]) for axis in range(3)])
            if prop == 'translation': local[index][:3,3]=v
            else:
                x,y,z=np.deg2rad(v)
                rx=np.array([[1,0,0],[0,np.cos(x),-np.sin(x)],[0,np.sin(x),np.cos(x)]])
                ry=np.array([[np.cos(y),0,np.sin(y)],[0,1,0],[-np.sin(y),0,np.cos(y)]])
                rz=np.array([[np.cos(z),-np.sin(z),0],[np.sin(z),np.cos(z),0],[0,0,1]])
                local[index][:3,:3]=ry@rx@rz
        def world(i): return world(parents[i])@local[i] if i in parents else local[i]
        result={}
        for i,node in enumerate(nodes):
            target = '/Tonneau_Cover/' in paths[i] if model=='cybertruck' else '/Spoiler_Spatial/' in paths[i]
            if not target or 'mesh' not in node: continue
            for prim in doc['meshes'][node['mesh']]['primitives']:
                pos=positions(prim['attributes']['POSITION'])
                pts=np.einsum('ij,nj->ni',world(i),np.c_[pos,np.ones(len(pos))])[:,:3]
                material=doc['materials'][prim['material']]['extras']['sourcePath']
                result[(paths[i],material)]=np.stack([pts.min(0),pts.max(0)])
        return result
    def actual(time):
        run=subprocess.run([str(a.binary),'--model',model,'--animation',clip_name,'--animation-time',str(time),
                            '--dump-components','--dump-components-only','--render-out','/tmp/unused-accessory-probe.png'],
                           text=True,capture_output=True,check=True)
        result={}
        for line in run.stdout.splitlines():
            match=re.fullmatch(r'(\S+) (\S+) SIMD3<Float>\(([^)]+)\) SIMD3<Float>\(([^)]+)\)',line)
            if match:
                name,material,lo,hi=match.groups()
                result[(name,material)]=np.array([[float(v) for v in xyz.split(',')] for xyz in [lo,hi]])
        return result
    zero=bounds(0); closed=actual(0)
    offsets={key:zero[key][0]-closed[key][0] for key in zero}
    maximum=0
    for time in times:
        reference=bounds(time); posed=actual(time)
        for key,expected in reference.items():
            error=np.abs(expected-offsets[key]-posed[key]).max()
            maximum=max(maximum,error)
            assert error < .0002, (model,time,key,error)
    assert len(zero)>=28 if model=='cybertruck' else len(zero)>=2
    print(model, 'source tracks, geometry, endpoints and intermediate/reversed poses pass; max error',maximum,'m',flush=True)
print('PASS: tonneau and active spoiler source animation geometry')
