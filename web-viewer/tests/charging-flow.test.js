import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import { chargingFlowAmount, createChargingFlow, patchChargingFlowShader } from '../src/charging-flow.js';

test('pulse travels toward the port, repeats every 1.5 seconds and wraps smoothly', () => {
  assert.ok(chargingFlowAmount(.42,.3) > .8);
  assert.ok(chargingFlowAmount(.82,.7) > .8);
  assert.ok(chargingFlowAmount(.42,.7) < .1);
  assert.ok(Math.abs(chargingFlowAmount(1.92,.3)-chargingFlowAmount(.42,.3))<1e-10);
  assert.ok(chargingFlowAmount(.3 - .00001,.3)<.00001);
  assert.ok(chargingFlowAmount(.3 + .00001,.3)<.00001);
});

test('flow tags preserve source cable UV while excluding the plug and body', () => {
  const base=new URL('../site-assets/',import.meta.url);
  const manifest=JSON.parse(readFileSync(new URL('manifest.json',base)));
  const vehicle=manifest.vehicles.find(v=>v.id==='cybertruck');
  const rig=JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file,base))));
  const packed=gunzipSync(readFileSync(new URL(vehicle.packed.file,base)));
  const offsets=new Map();let at=112;
  for(let i=0;i<packed.readUInt32LE(4);i++) {
    const name=packed.subarray(at,at+32).toString().replace(/\0.*$/,'');
    offsets.set(name,at+64);
    at+=64+packed.readUInt32LE(at+36)*20+packed.readUInt32LE(at+40)*4;
  }
  let flowVertices=0;
  for(const segment of rig.segments) {
    const cable=rig.nodes[segment.node].name.startsWith('Charger_Cable');
    const uv=[];
    for(let i=segment.first;i<segment.first+segment.count;i++) {
      const offset=offsets.get(segment.material)+i*20;
      assert.equal(packed[offset+18],cable?0:255);
      if(cable) {uv.push(packed[offset+17]/255);flowVertices++;}
    }
    if(cable) {assert.ok(Math.min(...uv)<.03);assert.ok(Math.max(...uv)>.97);}
  }
  assert.ok(flowVertices>100);
});

test('shader flow uses dedicated cable coordinates independently of material UV transforms', () => {
  const vertex='precision highp int; void main(){ CarIn v = CarIn(p,n,uv,ao); gl_Position=vec4(0.0); }';
  const fragment='precision highp int; void main(){ VOut i = VOut(gl_FragCoord,n,uv,ao); vec3 outputColor = c;\n vec4 result = exposureOut(outputColor); }';
  const v=patchChargingFlowShader(vertex),f=patchChargingFlowShader(fragment);
  assert.ok(v.includes('v.ao.z < 0.5 ? v.ao.y : -1.0'));
  assert.ok(f.includes('vShowroomChargeUV >= 0.0 && uShowroomChargeActive > 0.5'));
  assert.ok(f.includes('vec3(0.0, 1.0, 0.0)'));
  assert.ok(f.includes('smoothstep(0.0, 0.08, chargePhase)'));
  assert.ok(f.indexOf('float chargeFlow')<f.indexOf('exposureOut(outputColor)'));
  assert.equal(patchChargingFlowShader(v),v);
  assert.equal(patchChargingFlowShader(f),f);
  assert.equal(patchChargingFlowShader('unrelated shader'),'unrelated shader');
});

test('charging phase resets on disconnect and reconnect without changing other uniforms', () => {
  let now=0;
  const flow=createChargingFlow(()=>now),program={},values={};
  const gl={CURRENT_PROGRAM:1,getParameter:()=>program,getUniformLocation:(_,name)=>name,uniform1f:(name,value)=>values[name]=value};
  flow.setActive(true);now=400;flow.beforeDraw(gl);
  assert.equal(values.uShowroomChargeTime,.4);assert.equal(values.uShowroomChargeActive,1);
  flow.setActive(false);flow.beforeDraw(gl);
  assert.equal(values.uShowroomChargeTime,0);assert.equal(values.uShowroomChargeActive,0);
  flow.setActive(true);flow.beforeDraw(gl);assert.equal(values.uShowroomChargeTime,0);
  now=425;flow.beforeDraw(gl);assert.equal(values.uShowroomChargeTime,.025);
});
