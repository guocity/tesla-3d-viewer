import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sceneMaterial } from '../src/vehicle-materials.js';
import { advanceToggle, advanceCharging } from '../src/showroom-animation.js';
import { createVehicleBridge } from '../src/gpu-vehicle-bridge.js';

test('shared APK headlight material maps to red on rear brake meshes', () => {
  assert.equal(sceneMaterial('headlight__Illumination','Brake_Lights_Left'),'LightRed');
  assert.equal(sceneMaterial('headlight__Illumination','Brake_Lights_Trunk2'),'LightRed');
  assert.equal(sceneMaterial('headlight__Lights1','Lights_Trunk2'),'GlassWhite');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights',false),'Light');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights',true),'LightRed');
  assert.equal(sceneMaterial('headlight__Lights1','Lights2',true),'GlassWhite');
  assert.equal(sceneMaterial('glass_clear__Glass_Lights','Lights_Glass',true),'GlassWhite');
  assert.equal(sceneMaterial('glass_clear__Glass_Lights','Lights_Glass',false),'GlassWhite');
  assert.equal(sceneMaterial('interior_white__Suede_Light','Interior_Body',true),'BottomCar');
  assert.equal(sceneMaterial('trim__Light','Brake_Lights_On'),'LightRed');
  assert.equal(sceneMaterial('trim__Light_Off','Brake_Lights_Off'),'GlassWhite');
  assert.equal(sceneMaterial('trim__Lights','Charge_Cap',true),'MetallicBlack02');
  assert.equal(sceneMaterial('trim__Lights','Charge_Cap_Right',true),'MetallicBlack02');
  assert.equal(sceneMaterial('trim__Lights','Lights',true),'GlassWhite');
  assert.equal(sceneMaterial('trim__Light','Brake_Light',true),'LightRed');
  assert.equal(sceneMaterial('trim__TurnSignalUS_Brakes','Brake_Lights_CHMSL_On',true),'LightRed');
  assert.equal(sceneMaterial('trim__Light','DRL_Left',false),'Light');
  assert.equal(sceneMaterial('trim__Light','Headlights_On',false),'Light');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights_Trunk'),'LightRed');
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

test('charging waits for the open port, animates connection and reverses on disconnect', () => {
  assert.equal(advanceCharging(0, true, .5, .4), 0);
  assert.equal(advanceCharging(0, true, 1, .4), .5);
  assert.equal(advanceCharging(.5, true, 1, .4), 1);
  assert.equal(advanceCharging(1, false, 1, .4), .5);
  assert.equal(advanceCharging(.5, false, 1, .4), 0);
});

test('roof light bar is hidden by default and animates independently', async () => {
  const { createShowroomAnimation } = await import('../src/showroom-animation.js');
  const previous = { document: globalThis.document, requestAnimationFrame: globalThis.requestAnimationFrame, cancelAnimationFrame: globalThis.cancelAnimationFrame };
  const element = () => ({ dataset:{},children:[],attributes:{},append(child){this.children.push(child);},replaceChildren(){this.children=[];},setAttribute(k,v){this.attributes[k]=v;} });
  const list=element(), status=element(), close=element();
  const panel={dataset:{},querySelector(s){return s==='.motion-switches'?list:s==='[data-status]'?status:close;}};
  let tick;
  globalThis.document={hidden:false,createElement:element};
  globalThis.requestAnimationFrame=callback=>{tick=callback;return 1;};
  globalThis.cancelAnimationFrame=()=>{};
  try {
    const identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
    const rest=new Uint8Array(20);new DataView(rest.buffer).setInt16(0,10000,true);
    const part={name:'Metal',rest,current:rest.slice()};
    const controller=createShowroomAnimation({ready:true,upload(){},reset(){}},panel);
    controller.bind({normalize:identity,quant:[1,1,1],nodes:[{name:'Roof_Lightbar',parent:-1,matrix:identity}],segments:[{node:0,material:'Metal',first:0,count:1}],animations:[]},[part]);
    controller.refresh();
    const button=list.children[0];
    assert.equal(button.children[0].textContent,'Roof light bar');
    assert.equal(button.attributes['aria-checked'],'false');
    assert.equal(new DataView(part.current.buffer).getInt16(0,true),0);
    button.onclick();tick(1000);for(let t=1100;t<=1800;t+=100)tick(t);
    assert.equal(button.attributes['aria-checked'],'true');
    assert.equal(new DataView(part.current.buffer).getInt16(0,true),10000);
    button.onclick();for(let t=1900;t<=2700;t+=100)tick(t);
    assert.equal(new DataView(part.current.buffer).getInt16(0,true),0);
    controller.bind({normalize:identity,quant:[1,1,1],nodes:[],segments:[],animations:[]},[]);
    assert.equal(list.children.length,0);
    controller.dispose();
  } finally { Object.assign(globalThis,previous); }
});

test('Cybertruck axis tracks open the cap before connecting and reverse on disconnect', async () => {
  const { createShowroomAnimation } = await import('../src/showroom-animation.js');
  const previous={document:globalThis.document,requestAnimationFrame:globalThis.requestAnimationFrame,cancelAnimationFrame:globalThis.cancelAnimationFrame};
  const element=()=>({dataset:{},children:[],append(c){this.children.push(c);},replaceChildren(){this.children=[];},setAttribute(){}});
  const list=element(), status=element(), close=element();
  const panel={dataset:{},querySelector:s=>s==='.motion-switches'?list:s==='[data-status]'?status:close};
  let tick;
  globalThis.document={hidden:false,createElement:element};
  globalThis.requestAnimationFrame=callback=>{tick=callback;return 1;};globalThis.cancelAnimationFrame=()=>{};
  try {
    const identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
    const rest=new Uint8Array(20);new DataView(rest.buffer).setInt16(0,10000,true);
    const cap={name:'Metal',rest,current:rest.slice()};
    const controller=createShowroomAnimation({ready:true,upload(){},reset(){}},panel);
    controller.bind({normalize:identity,quant:[1,1,1],nodes:[{name:'Charge_Cap_Spatial',parent:-1,matrix:identity},{name:'APK_ChargeCable',parent:-1,matrix:identity}],segments:[{node:0,material:'Metal',first:0,count:1}],animations:[{name:'ChargeportAnimation',duration:1,tracks:[{target:'Charge_Cap_Spatial:rotation_degrees:y',type:'bezier',interpolation:1,times:[0,1],values:[0,90],handles:[[0,0,1/3,30],[-1/3,-30,0,0]]}]}]},[cap]);
    assert.equal(controller.setCharging(true),true);
    tick(1000);tick(1100);
    assert.equal(controller.getChargingState().connection,0);
    for(let t=1200;t<=3400;t+=100)tick(t);
    assert.equal(controller.getChargingState().connection,1);
    assert.ok(Math.abs(new DataView(cap.current.buffer).getInt16(0,true))<2);
    assert.ok(Math.abs(new DataView(cap.current.buffer).getInt16(4,true))>9990);
    controller.setCharging(false);
    for(let t=3500;t<=6000;t+=100)tick(t);
    assert.equal(controller.getChargingState().connection,0);
    assert.equal(controller.getChargingState().portOpen,0);
    assert.equal(new DataView(cap.current.buffer).getInt16(0,true),10000);
    controller.dispose();
  } finally {Object.assign(globalThis,previous);}
});

test('Cybertruck wheel covers use matte plastic while other metal rims stay metallic', () => {
  assert.equal(sceneMaterial('wheel_rim__Premium_Wheel','Premium_Wheel'),'BottomCar');
  assert.equal(sceneMaterial('wheel_rim__Arachnid','Wheel'),'MetallicGray');
});
