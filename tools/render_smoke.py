#!/usr/bin/env python3
"""Render every vehicle through Metal and produce a visual QA contact sheet."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image,ImageDraw
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path('/tmp/tesla-renders'));a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
binary=repo/'TeslaMetalViewer/TeslaMetalViewer.app/Contents/MacOS/TeslaMetalViewer'
vehicles=json.loads((repo/'models/catalog.json').read_text())['vehicles'];sheet=Image.new('RGB',(1600,900),'#20252d');draw=ImageDraw.Draw(sheet)
for i,model in enumerate(vehicles):
    image_path=a.output/(model['id']+'.png')
    run=subprocess.run([str(binary),'--model',model['id'],'--render-out',str(image_path)],capture_output=True,text=True,check=True)
    if not image_path.exists():raise RuntimeError(run.stdout+run.stderr)
    im=Image.open(image_path).convert('RGB');im.thumbnail((400,300));x=(i%4)*400;y=(i//4)*300
    sheet.paste(im,(x,y+30));draw.text((x+10,y+8),model['name'],fill='white')
    print(model['id'],flush=True)
sheet.save(a.output/'all-models.png')
