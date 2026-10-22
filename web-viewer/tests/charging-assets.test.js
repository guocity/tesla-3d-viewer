import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

test('prepared Cybertruck includes its charge-port channels and renderable cable', () => {
  const base=new URL('../site-assets/',import.meta.url);
  const manifest=JSON.parse(readFileSync(new URL('manifest.json',base)));
  const vehicle=manifest.vehicles.find(v=>v.id==='cybertruck');
  const rig=JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file,base))));
  const clip=rig.animations.find(a=>a.name==='ChargeportAnimation');
  assert.ok(clip,'Cybertruck charge-port animation must survive export');
  assert.deepEqual(clip.tracks.map(t=>t.target).sort(),['x','y','z'].map(axis=>`Charge_Cap_Spatial:rotation_degrees:${axis}`));
  for(const track of clip.tracks){assert.equal(track.type,'bezier');assert.equal(track.handles.length,track.times.length);}
  const cable=rig.nodes.findIndex(n=>n.name==='APK_ChargeCable');
  assert.ok(cable>=0,'Cybertruck cable anchor must survive export');
  const cableSegments=rig.segments.filter(segment=>{
    for(let i=segment.node;i>=0;i=rig.nodes[i].parent)if(i===cable)return true;
    return false;
  });
  assert.ok(cableSegments.some(s=>s.count>0),'Cable must contain uploaded geometry');
});

for (const id of ['modely_high','bayberry','bayberry_e41','bayberry_e80']) {
  test(`${id}: charging cable has an anchor, handle and flow geometry`,()=>{
    const base=new URL('../site-assets/',import.meta.url);
    const manifest=JSON.parse(readFileSync(new URL('manifest.json',base)));
    const vehicle=manifest.vehicles.find(v=>v.id===id);
    const rig=JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file,base))));
    const anchor=rig.nodes.findIndex(n=>n.name==='APK_ChargeCable');
    assert.ok(anchor>=0,'Source charge-port marker must create a cable anchor');
    const cable=rig.segments.filter(s=>{for(let i=s.node;i>=0;i=rig.nodes[i].parent)if(i===anchor)return true;return false;});
    assert.ok(cable.some(s=>/^Charger_Handle/.test(rig.nodes[s.node].name)&&s.count>0));
    assert.ok(cable.some(s=>/^Charger_Cable/.test(rig.nodes[s.node].name)&&s.count>0));
  });
}
