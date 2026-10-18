#!/usr/bin/env python3
"""Actual-GPU regression for rear optics, blink phases and adjustable cabin LEDs."""
from pathlib import Path
import argparse, subprocess, json
import numpy as np
from PIL import Image
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,default=Path('/tmp/tesla-lamp-effects'))
p.add_argument('--circuits-only',action='store_true',help='Run circuit-specific checks without repeating the fleet render sweep')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
binary=repo/'TeslaMetalViewer/.build/release/TeslaMetalViewer'
def render(name,model='bayberry',preset='rear',extra=()):
    target=a.output/(name+'.png')
    subprocess.run([str(binary),'--model',model,'--preset',preset,*(['--paint','solid_black'] if '--paint' not in extra else []),
                    '--samples','16','--render-out',str(target),*(['--cabin-brightness','0'] if '--cabin-brightness' not in extra else []),*extra],check=True,capture_output=True,text=True)
    return np.asarray(Image.open(target).convert('RGB')).astype(float)
def amber(im):return ((im[:,:,0]>80)&(im[:,:,1]>35)&(im[:,:,0]>im[:,:,1]*1.2)&(im[:,:,2]<im[:,:,1]*0.5)).sum()
def red(im):return ((im[:,:,0]>90)&(im[:,:,0]>im[:,:,1]*2+10)&(im[:,:,0]>im[:,:,2]*2+10)).sum()
# Direct rear views ensure a visible front indicator cannot satisfy this test.
if not a.circuits_only:
    for model in json.loads((repo/'models/catalog.json').read_text())['vehicles']:
        for side in ['left','right']:
            common=['--rear-straight','--signal-'+side]
            on=render(model['id']+'-'+side+'-on',model['id'],extra=common+['--effect-time','0.1'])
            off=render(model['id']+'-'+side+'-off',model['id'],extra=common+['--effect-time','0.5'])
            delta=np.abs(on-off).max(axis=2)>15
            # Exclude the road reflection and use the actual rear fixture region.
            left=delta[300:650,450:700].sum();right=delta[300:650,700:950].sum()
            selected,other=(left,right) if side=='left' else (right,left)
            assert selected>30, f"{model['id']} {side}: no visible rear blink ({selected} pixels)"
            assert other<max(15,selected*0.12), f"{model['id']} {side}: opposite rear fixture also blinks"
            print(model['id'],side,int(selected),'rear pixels',flush=True)
    # Bayberry must illuminate the recessed panel continuously, with the source
    # hidden by its upper lip. White paint exposes excessive downward spill.
    for model in ['bayberry','bayberry_e80']:
        running=render(model+'-indirect-rear',model,extra=['--rear-straight','--paint','pearl_white'])
        dark=render(model+'-rear-off',model,extra=['--rear-straight','--paint','pearl_white','--lights-off'])
        panel=running[405:450,620:780];unlit=dark[405:450,620:780]
        assert red(panel)>80, model+': no red panel illumination'
        assert np.abs(panel-unlit).sum()>5000, model+': parking lamp has no effect on recessed panel'
# Shared US signals must not punch black holes through the steady S outline.
s_running=render('models-plaid-outline','models_plaid',extra=['--rear-straight'])
s_dark=render('models-plaid-outline-dark-phase','models_plaid',extra=['--rear-straight','--signal-left','--effect-time','0.5'])
def redmask(im):return (im[:,:,0]>90)&(im[:,:,0]>im[:,:,1]*2+10)&(im[:,:,0]>im[:,:,2]*2+10)
outline=redmask(s_running)[420:460,530:580]
assert (redmask(s_dark)[420:460,530:580]&outline).sum()>outline.sum()*0.97, 'Model S running outline disappears during dark blink phase'
for model in ['bayberry','bayberry_e80']:
    signal=render(model+'-red-rear-signal',model,extra=['--rear-straight','--signal-left','--effect-time','0.1'])
    region=signal[430:450,535:610]
    assert red(region)>50 and amber(region)<10, model+': rear turn signal must be red'
e41=render('e41-center-running','bayberry_e41',extra=['--rear-straight'])
assert red(e41[410:445,620:780])>100, 'E41 middle rear running strip missing'
ct_running=render('cybertruck-running-circuits','cybertruck',extra=['--rear-straight'])
ct_braking=render('cybertruck-brake-circuits','cybertruck',extra=['--rear-straight','--brake-lights'])
assert red(ct_running[393:402,610:790])>100, 'Cybertruck upper running bar missing'
assert red(ct_braking[393:402,610:790])<10, 'Cybertruck upper running bar stays lit during braking'
assert red(ct_braking[402:420,530:565])>30, 'Cybertruck lower brake fixture missing'
for model in ['models_plaid','model3_high']:
    first=render(model+'-brake-on',model,extra=['--brake-lights','--effect-time','0.1'])
    second=render(model+'-brake-later',model,extra=['--brake-lights','--effect-time','0.5'])
    assert np.array_equal(first,second),'Brake-only fixture incorrectly blinks: '+model
for model in ['bayberry','poppyseed']:
    blue=render(model+'-cabin-blue',model,'cabin',['--cabin-brightness','1.5','--cabin-color','0066ff'])
    pink=render(model+'-cabin-pink',model,'cabin',['--cabin-brightness','1.5','--cabin-color','ff0066'])
    assert ((blue[:,:,2]>blue[:,:,0]*1.8+30)&(blue[:,:,2]>100)).sum()>150,'Blue cabin strip not visible: '+model
    assert ((pink[:,:,0]>pink[:,:,1]*1.8+30)&(pink[:,:,0]>100)).sum()>150,'Pink cabin strip not visible: '+model
    assert np.abs(blue-pink).sum()>30000,'Cabin color control has no visible effect'
print('PASS: all 24 rear indicator/side checks, red Bayberry signals, complete Model S outline, E41 center strip, Cybertruck running/brake circuits, steady brakes, adjustable cabin LEDs.')
