import { isRoadWheelNode } from '../src/vehicle-materials.js';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

test('all prepared road wheel covers use the matte plastic preset', () => {
  const base=new URL('../site-assets/',import.meta.url);
  const manifest=JSON.parse(readFileSync(new URL('manifest.json',base)));
  for (const vehicle of manifest.vehicles) {
    const rig=JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file,base))));
    const covers=rig.segments.filter(s=>isRoadWheelNode(rig.nodes[s.node].name));
    assert.ok(covers.length>=4, `${vehicle.id}: all road wheel assemblies retain geometry`);
    for(const cover of covers)assert.equal(cover.material,'BottomCar',`${vehicle.id}: ${rig.nodes[cover.node].name} should be matte`);
  }
});

test('matte cover override excludes body panels and steering wheels', async () => {
  const { sceneMaterial, wheelCoverMaterial } = await import('../src/vehicle-materials.js');
  assert.equal(wheelCoverMaterial('wheel_rim__Premium_Wheel', 'Wheel_Cybertruck_Premium_FL'), 'BottomCar');
  for (const node of ['Body', 'Door_Left', 'Steering_Wheel_Standard', 'Static_Exterior', 'Interior_Body', '']) {
    assert.equal(wheelCoverMaterial('wheel_rim__Premium_Wheel', node), null);
  }
  assert.equal(wheelCoverMaterial('paint__Paint', 'Wheel_Cybertruck_Premium_FL'), null);
  assert.equal(wheelCoverMaterial('wheel_rim__Trim', 'Static_Exterior'), null);
  assert.equal(wheelCoverMaterial('wheel_rim__Arachnid21', 'Wheel_Arachnid22'), 'BottomCar');
  assert.equal(wheelCoverMaterial('wheel_rim__Halo_Cap', 'Halo_22'), 'BottomCar');
  assert.equal(sceneMaterial('wheel_rim__Premium_Wheel', 'Body'), 'MetallicGray');
  assert.equal(sceneMaterial('paint__Paint', 'Body'), 'CarPaint');
});
