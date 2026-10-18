#!/usr/bin/env python3
"""Render source lighting and material review sheets for every vehicle using Metal."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw
import numpy as np

repo = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=Path, default=repo/'TeslaMetalViewer/.build/release/TeslaMetalViewer')
p.add_argument('--output', type=Path, default=Path('/tmp/tesla-lighting-review'))
a = p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
models = json.loads((repo/'models/catalog.json').read_text())['vehicles']
for preset in ['front','rear']:
    sheet = Image.new('RGB',(1600,1020),'#151b24')
    draw = ImageDraw.Draw(sheet)
    for i,model in enumerate(models):
        target = a.output/(model['id']+'-'+preset+'.png')
        subprocess.run([str(a.binary),'--model',model['id'],'--preset',preset,'--paint','pearl_white',
                        '--samples','64','--render-out',str(target)],check=True,capture_output=True,text=True)
        image = Image.open(target).convert('RGB')
        if preset == 'rear':
            rgb = np.asarray(image).astype(float)
            red = (rgb[:,:,0]>60) & (rgb[:,:,0]>2*rgb[:,:,1]+10) & (rgb[:,:,0]>2*rgb[:,:,2]+10)
            assert red.sum()>16, model['id'] + ': no visible red rear running lamps'
        # Crop empty framing for a legible material/lamp contact sheet.
        image = image.crop((280,230,1150,820)); image.thumbnail((400,300))
        x,y = i%4*400,i//4*340
        sheet.paste(image,(x,y+30))
        draw.text((x+12,y+8),model['name'],fill='white')
        print(model['id'],preset,flush=True)
    sheet.save(a.output/(preset+'-all-vehicles.png'))
