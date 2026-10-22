import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

test('all prepared Cybertruck wheel covers use the matte plastic preset', () => {
  const base=new URL('../site-assets/',import.meta.url);
  const manifest=JSON.parse(readFileSync(new URL('manifest.json',base)));
  const vehicle=manifest.vehicles.find(v=>v.id==='cybertruck');
  const rig=JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file,base))));
  const covers=rig.segments.filter(s=>rig.nodes[s.node].name.startsWith('Wheel_Cybertruck_Premium'));
  assert.ok(covers.length>=4,'All four wheel assemblies must retain cover geometry');
  for(const cover of covers)assert.equal(cover.material,'BottomCar',`${rig.nodes[cover.node].name} should be matte plastic`);
});
