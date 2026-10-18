#!/usr/bin/env python3
"""Compare restored strut metadata with the preserved APK source animations."""
import hashlib
import json
from pathlib import Path
import struct
from convert_assets import REA_GODOT_ROOT, parse_tscn_metadata

repo = Path(__file__).resolve().parents[1]
report_path = repo / 'evidence/liftgate-strut-source-tracks.json'
reports = {m['vehicle']: m for m in json.loads(report_path.read_text())} if report_path.exists() else {}
for model in ['bayberry', 'bayberry_e41', 'bayberry_e80']:
    data = (repo / 'models' / (model + '.glb')).read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20+length])
    if model in reports:
        assert hashlib.sha256(data[20+length:]).hexdigest() == reports[model]['binaryChunkSHA256'], 'Geometry/textures changed'
    clip = next(a for a in gltf['extras']['sourceAnimations'] if a['name'] == 'TrunkAnimation')
    source = REA_GODOT_ROOT / clip['source']
    original = next(a for a in parse_tscn_metadata(source)['animations'] if a['name'] == clip['name'])
    tracks = [t for t in original['tracks'] if 'Strut_' in t['target']]
    assert len(tracks) == 4
    for authored in tracks:
        exported = next(t for t in clip['tracks'] if t['target'] == authored['target'])
        assert {k: v for k, v in exported.items() if k != 'node'} == authored, authored['target']
        assert gltf['nodes'][exported['node']]['name'] == authored['target'].split(':')[0].split('/')[-1]
    print(model, 'four exact source Transform tracks; node bindings verified')
print('PASS: strut source metadata and export preservation')
