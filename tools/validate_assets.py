#!/usr/bin/env python3
"""Validate all exported vehicle surfaces and animation targets without a GPU."""
import json
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[1]
report = []
for item in json.loads((root/'models/catalog.json').read_text())['vehicles']:
    p = root/'models'/f"{item['id']}.glb"
    data = p.read_bytes()
    assert data[:4] == b'glTF' and struct.unpack_from('<I',data,8)[0] == len(data)
    n = struct.unpack_from('<I',data,12)[0]
    gltf = json.loads(data[20:20+n])
    nodes = gltf['nodes']; parents = {c:i for i,node in enumerate(nodes) for c in node.get('children',[])}
    def path(i): return (path(parents[i])+'/' if i in parents else '')+nodes[i]['name']
    paths = [path(i) for i in range(len(nodes))]
    def has_geometry(index):
        return 'mesh' in nodes[index] or any(has_geometry(c) for c in nodes[index].get('children',[]))
    omitted = list(gltf.get('extras',{}).get('omittedAnimationTracks',[])); clips = []
    for clip in gltf.get('extras',{}).get('sourceAnimations',[]):
        tracks = []
        for track in clip['tracks']:
            target = track['target'].split(':')[0]
            matches = [i for i,p in enumerate(paths) if p == target or p.endswith('/'+target)]
            if target == '.': matches = gltf['scenes'][0]['nodes'][:1]
            if len(matches) != 1 or not has_geometry(matches[0]):
                omitted.append({'clip':clip['name'],'target':target,'reason':'no exported geometry in this variant'})
                continue
            assert len(track['times']) == len(track['values']) and track['times'] == sorted(track['times'])
            track['node'] = matches[0]
            tracks.append(track)
        if tracks: clips.append(dict(clip,tracks=tracks))
    # Store explicit node IDs so runtime does not depend on ambiguous short names.
    gltf.setdefault('extras',{})['sourceAnimations'] = clips
    gltf['extras']['omittedAnimationTracks'] = omitted
    binary = data[28+n:]
    payload = json.dumps(gltf,separators=(',',':')).encode();payload += b' '*((-len(payload))%4)
    p.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(payload)+len(binary))+struct.pack('<I4s',len(payload),b'JSON')+payload+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
    materials=[]
    for m in gltf['materials']:
        assert m['extras'].get('sourcePath'), m
        pbr=m['pbrMetallicRoughness'];assert 0 <= pbr['roughnessFactor'] <= 1 and 0 <= pbr['metallicFactor'] <= 1
        materials.append({'name':m['name'],'source':m['extras']['sourcePath'],'category':m['extras']['category']})
    for mesh in gltf['meshes']:
        for prim in mesh['primitives']:
            count=gltf['accessors'][prim['attributes']['POSITION']]['count']
            ia=gltf['accessors'][prim['indices']];view=gltf['bufferViews'][ia['bufferView']]
            offset=view.get('byteOffset',0)+ia.get('byteOffset',0)
            indices=struct.unpack_from('<'+str(ia['count'])+('I' if ia['componentType']==5125 else 'H'),binary,offset)
            assert len(indices)%3==0 and max(indices)<count
            trim=prim.get('extras',{}).get('windowTrimTriangles',[])
            assert len(trim)==len(set(trim)) and all(0<=t<len(indices)//3 for t in trim)
    components=[]
    for index,node in enumerate(nodes):
        if 'mesh' not in node: continue
        for surface,prim in enumerate(gltf['meshes'][node['mesh']]['primitives']):
            material=gltf['materials'][prim['material']]
            components.append({'node':index,'path':paths[index],'surface':surface,'material':material['extras']['sourcePath'],'windowTrimTriangles':len(prim.get('extras',{}).get('windowTrimTriangles',[]))})
    report.append({'components':components,'vehicle':item['id'],'clips':len(clips),'tracks':sum(len(c['tracks']) for c in clips),'omitted':omitted,'materials':materials})
(root/'models/source-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"Validated {len(report)} vehicles, {sum(x['clips'] for x in report)} clips, {sum(x['tracks'] for x in report)} tracks")
