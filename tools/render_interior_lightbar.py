#!/usr/bin/env python3
"""GPU checks that all interior lightbars have been removed."""
from pathlib import Path
import argparse
import subprocess
import numpy as np
from PIL import Image, ImageDraw
repo = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,default=Path('/tmp/tesla-single-lightbar'))
a = p.parse_args(); a.output.mkdir(parents=True,exist_ok=True)
binary = repo/'TeslaMetalViewer/.build/release/TeslaMetalViewer'
models = ['models_plaid','modelx_plaid','poppyseed','bayberry','bayberry_e41','bayberry_e80','cybertruck',
          'model3_high','modely_high','models_legacy','modelx_legacy','semi']
for model in models:
    target=a.output/(model+'-no-interior-lightbar.png')
    subprocess.run([str(binary),'--model',model,'--preset','cabin','--samples','16','--render-out',str(target)],
                   check=True,capture_output=True)
    rgb=np.asarray(Image.open(target).convert('RGB')).astype(float)
    blue=(rgb[:,:,2]>rgb[:,:,0]*1.8+30)&(rgb[:,:,2]>100)
    assert blue.sum()<150,model+': bright blue interior accent remains'
    print(model,'no interior lightbar',flush=True)
print('PASS: no visible interior lightbars on all 12 models.')
