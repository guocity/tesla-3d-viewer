#!/usr/bin/env python3
"""Exercise the actual Metal renderer: scene isolation, dry controls and weather motion."""
import argparse
from pathlib import Path
import subprocess
from PIL import Image, ImageChops, ImageStat

repo = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--binary', type=Path, default=repo/'TeslaMetalViewer/.build/release/TeslaMetalViewer')
p.add_argument('--output', type=Path, default=Path('/tmp/tesla-weather-qa'))
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)

def render(name, scene, rain=0, wetness=0, time=2):
    target = a.output/(name+'.png')
    subprocess.run([str(a.binary), '--model', 'model3_high', '--paint', 'ultra_red',
                    '--lighting', scene, '--rain', str(rain), '--wetness', str(wetness),
                    '--effect-time', str(time), '--samples', '32', '--render-out', str(target)], check=True)
    image = Image.open(target).convert('RGB')
    assert image.size == (1400, 900), name + ': wrong output size'
    assert sum(ImageStat.Stat(image).stddev) > 12, name + ': blank image'
    return image

def difference(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean)

studio = render('studio', 'studio')
assert difference(studio, render('studio-weather-controls', 'studio', 1, 1, 9)) == 0, 'Weather leaked into studio'
dry = render('neon-dry', 'neon-rain')
assert difference(dry, render('neon-dry-later', 'neon-rain', time=9)) == 0, 'Dry scene changes with weather time'
wet = render('neon-wet', 'neon-rain', 0.8, 0.9)
assert difference(dry, wet) > 1, 'Wet road/rain controls have no visible effect'
assert difference(wet, render('neon-wet-later', 'neon-rain', 0.8, 0.9, 9)) > 0.05, 'Weather does not animate'
coast = render('coastal-storm', 'coastal-storm', 0.6, 0.8)
assert difference(coast, wet) > 10, 'Scene presets are indistinguishable'
print('PASS: Metal renders are nonblank; studio isolation, dry stability, wetness, rain motion and scene changes verified.')
