#!/usr/bin/env python3
"""Render Juniper's curved rear recess and check both ends and lights-off spill."""
import argparse
from pathlib import Path
import subprocess
import numpy as np
from PIL import Image

repo = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, default=Path('/tmp/tesla-rear-panel'))
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
binary = repo / 'TeslaMetalViewer/.build/release/TeslaMetalViewer'
for model in ['bayberry', 'bayberry_e80']:
    for paint in ['deep_blue', 'pearl_white']:
        frames = []
        for on in [True, False]:
            target = a.output / f'{model}-{paint}-{"on" if on else "off"}.png'
            subprocess.run([str(binary), '--model', model, '--preset', 'rear',
                            '--rear-straight', '--zoom', '0.55', '--paint', paint,
                            '--samples', '16', '--render-out', str(target),
                            *([] if on else ['--lights-off'])], check=True, capture_output=True)
            frames.append(np.asarray(Image.open(target).convert('RGB')).astype(float))
        on, off = frames
        # Fixed camera: sample the recessed receiver, excluding the upper lamp,
        # lettering and lower lip. The old straight source fails both end probes.
        def redness(im):
            return im[:, :, 0] - np.maximum(im[:, :, 1], im[:, :, 2])
        wash = redness(on) - redness(off)
        band = slice(374, 393) if model == 'bayberry' else slice(391, 410)
        probes = [wash[band, x:x+40].mean() for x in [330, 600, 1030]]
        assert min(probes) > 70, f'{model}/{paint}: dark panel section {probes}'
        assert min(probes[0], probes[2]) > probes[1]*0.65, f'{model}/{paint}: dark curved ends {probes}'
        assert redness(off)[band, 330:1070].mean() < 15, f'{model}/{paint}: panel lit with lamps off'
        assert wash[450:550, 400:1000].mean() < 15, f'{model}/{paint}: red wash spills onto lower tailgate'
        print(model, paint, 'left/center/right red wash:', [round(v, 1) for v in probes], flush=True)
print('PASS: curved rear panel, both ends, lamps off and lower-tailgate spill')
