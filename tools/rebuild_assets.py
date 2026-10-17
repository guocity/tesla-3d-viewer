#!/usr/bin/env python3
"""Rebuild the viewer assets directly from the supplied APKM, using REA extraction."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('apkm',type=Path)
args=parser.parse_args()
evidence=[]
def extract(path):
    result=subprocess.run(['rea','extract-artifact',str(path),'--format','json'],check=True,capture_output=True,text=True)
    item=json.loads(result.stdout);evidence.append(item)
    return Path(item['normalized_result']['output_root'])
archive=extract(args.apkm.resolve())
godot=extract(archive/'split_assets_pack.apk')/'assets/godot'
with tempfile.TemporaryDirectory(prefix='tesla-source-') as temp:
    source=Path(temp)
    for name in ['Ego','Energy']:
        if (godot/name).exists(): (source/name).symlink_to(godot/name,target_is_directory=True)
    os.environ['TESLA_GODOT_ROOT']=str(godot)
    os.environ['TESLA_EXTRACTED_ROOT']=str(source)
    import convert_assets as converter
    for original,compiled in converter.IMPORT_MAP.items():
        if compiled.suffix not in ('.scn','.mesh'): continue
        target=source/'models_by_vehicle'/Path(original.removeprefix('res://')).with_suffix(compiled.suffix)
        target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():target.symlink_to(compiled)
    converter.main()
    subprocess.run([sys.executable,str(repo/'tools/validate_assets.py')],check=True)
records=[]
for item in evidence:
    records.append({'evidence_id':item['evidence_id'],'provider':item['provider'],'operation':item['operation'],
                    'subject':{'name':item['subject']['name'],'digest':item['subject']['digest']},
                    'integrity_contradictions':item['normalized_result']['integrity_contradictions'],
                    'containment_verified':item['normalized_result']['containment_verified']})
(repo/'evidence/rea-extraction.json').write_text(json.dumps(records,indent=2)+'\n')
