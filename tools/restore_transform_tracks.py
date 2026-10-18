#!/usr/bin/env python3
"""Restore exported Transform-valued source tracks without rebuilding meshes/textures."""
import hashlib
import json
from pathlib import Path
import struct
from convert_assets import REA_GODOT_ROOT, parse_tscn_metadata

repo = Path(__file__).resolve().parents[1]
report = []
track_counts = {}
for vehicle in json.loads((repo / 'models/catalog.json').read_text())['vehicles']:
    path = repo / 'models' / (vehicle['id'] + '.glb')
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+length])
    nodes = gltf['nodes']
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    def node_path(i):
        return (node_path(parents[i]) + '/' if i in parents else '') + nodes[i]['name']
    paths = [node_path(i) for i in range(len(nodes))]
    source_cache = {}
    added = []
    for clip in gltf.get('extras', {}).get('sourceAnimations', []):
        source = REA_GODOT_ROOT / clip['source']
        if source not in source_cache:
            source_cache[source] = parse_tscn_metadata(source)['animations']
        authored = next(a for a in source_cache[source] if a['name'] == clip['name'])
        existing = {t['target'] for t in clip['tracks']}
        for track in authored['tracks']:
            if track.get('valueType') != 'Transform' or track['target'] in existing:
                continue
            target = track['target'].split(':')[0]
            matches = [i for i, p in enumerate(paths) if p == target or p.endswith('/' + target)]
            if len(matches) != 1:
                raise ValueError(f'{path.name}: ambiguous/missing transform target {target}')
            clip['tracks'].append(dict(track, node=matches[0]))
            added.append(dict(clip=clip['name'], target=track['target'], keys=len(track['times']),
                              source=str(source.relative_to(REA_GODOT_ROOT)),
                              sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest()))
    track_counts[vehicle["id"]] = sum(len(a["tracks"]) for a in gltf.get("extras", {}).get("sourceAnimations", []))
    if added:
        # Retain the BIN chunk byte for byte, including all geometry and textures.
        binary_chunk = data[20+length:]
        payload = json.dumps(gltf, separators=(',', ':')).encode()
        payload += b' ' * (-len(payload) % 4)
        updated = (struct.pack('<4sII', b'glTF', 2, 20+len(payload)+len(binary_chunk))
                   + struct.pack('<I4s', len(payload), b'JSON') + payload + binary_chunk)
        assert updated[20+len(payload):] == binary_chunk
        path.write_bytes(updated)
        report.append(dict(vehicle=vehicle['id'], tracks=added,
                           binaryChunkSHA256=hashlib.sha256(binary_chunk).hexdigest()))
        print(vehicle['id'], len(added), 'Transform property tracks restored', flush=True)
if report:
    (repo / 'evidence/liftgate-strut-source-tracks.json').write_text(json.dumps(report, indent=2) + '\n')
else:
    print('All Transform property tracks are already present.')

audit_path = repo / 'models/source-audit.json'
if audit_path.exists():
    audit = json.loads(audit_path.read_text())
    changed = False
    for entry in audit:
        count = track_counts.get(entry['vehicle'])
        if count is not None and entry['tracks'] != count:
            entry['tracks'] = count
            changed = True
    if changed:
        audit_path.write_text(json.dumps(audit, indent=2) + '\n')
