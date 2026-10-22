import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sceneMaterial } from '../src/vehicle-materials.js';
import { advanceToggle } from '../src/showroom-animation.js';
import { createVehicleBridge } from '../src/gpu-vehicle-bridge.js';

test('shared APK headlight material maps to red on rear brake meshes', () => {
  assert.equal(sceneMaterial('headlight__Illumination','Brake_Lights_Left'),'LightRed');
  assert.equal(sceneMaterial('headlight__Illumination','Brake_Lights_Trunk2'),'LightRed');
  assert.equal(sceneMaterial('headlight__Lights1','Lights_Trunk2'),'LightRed');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights'),'Light');
  assert.equal(sceneMaterial('trim__Light','Brake_Lights_On'),'LightRed');
  assert.equal(sceneMaterial('trim__Light_Off','Brake_Lights_Off'),'GlassRed');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights_Trunk'),'MetallicWhite');
});
test('toggles reverse continuously and independently from their current pose', () => {
  const left = advanceToggle(0,1,0.4,1), trunk = advanceToggle(0,1,0.4,2);
  assert.equal(left,0.4); assert.equal(trunk,0.2);
  assert.equal(advanceToggle(left,0,0.1,1),0.30000000000000004);
  assert.equal(advanceToggle(trunk,1,2,2),1);
  assert.equal(advanceToggle(0.1,0,1,1),0);
});
test('GPU bridge captures only matching vehicle bytes and preserves buffer binding', () => {
  const nativeBuffer={},otherBuffer={},calls=[];
  let bound=nativeBuffer;
  const gl={ COPY_WRITE_BUFFER:36663,COPY_WRITE_BUFFER_BINDING:36663,bufferSubData(...args){calls.push(args);},getParameter(){return bound;},bindBuffer(target,buffer){bound=buffer;},isContextLost(){return false;} };
  const canvas={getContext(){return gl;}};
  const bridge=createVehicleBridge(canvas), ctx=canvas.getContext('webgl2');
  const buffer=new ArrayBuffer(112+64+20);const bytes=new Uint8Array(buffer);const view=new DataView(buffer);
  view.setUint32(4,1,true);bytes.set(new TextEncoder().encode('CarPaint'),112);view.setUint32(148,1,true);bytes.fill(17,176);
  const [part]=bridge.setVehicle(buffer);
  ctx.bufferSubData(36663,0,new Uint8Array(20));assert.equal(bridge.ready,false);
  ctx.bufferSubData(36663,0,part.rest);assert.equal(bridge.ready,true);
  part.current[0]=25;bound=otherBuffer;assert.equal(bridge.upload(part),true);assert.equal(bound,otherBuffer);assert.equal(calls.at(-1)[2][0],25);
});
