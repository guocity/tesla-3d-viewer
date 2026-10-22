import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Matrix4, Vector3 } from 'three';
import { createNativeCamera } from '../src/native-camera.js';

test('charging native drag releases the pointer and removes every temporary input handler',t=>{
  const previous={window:globalThis.window,MouseEvent:globalThis.MouseEvent,requestAnimationFrame:globalThis.requestAnimationFrame,cancelAnimationFrame:globalThis.cancelAnimationFrame};
  t.after(()=>Object.assign(globalThis,previous));let now=1000;t.mock.method(performance,'now',()=>now);
  globalThis.window={};globalThis.MouseEvent=class{constructor(type,init){Object.assign(this,{type},init);}};
  const frames=new Map(),events=[],listeners=new Map();let id=0;
  globalThis.requestAnimationFrame=callback=>{frames.set(++id,callback);return id;};globalThis.cancelAnimationFrame=id=>frames.delete(id);
  const canvas={dispatchEvent:e=>events.push(e),addEventListener:(type,fn)=>listeners.set(type,fn),removeEventListener:type=>listeners.delete(type),getBoundingClientRect:()=>({left:0,top:0,width:1200,height:800})};
  const camera=createNativeCamera(canvas);assert.equal(listeners.size,0,'No replacement orbit handlers are installed');
  const eye=new Vector3(6,2,8),view=new Matrix4().lookAt(eye,new Vector3(0,.8,0),new Vector3(0,1,0)).setPosition(eye).invert();
  const values=new Float32Array(32);values.set(new Matrix4().makePerspective(-.15,.15,.1,-.1,.2,1000).multiply(view).elements);values.set(new Matrix4().elements,16);
  const program={},buffer={};
  const gl={CURRENT_PROGRAM:1,ACTIVE_UNIFORMS:2,UNIFORM_OFFSET:3,UNIFORM_BLOCK_INDEX:4,UNIFORM_BLOCK_BINDING:5,UNIFORM_BUFFER_BINDING:6,UNIFORM_BUFFER_START:7,COPY_READ_BUFFER_BINDING:8,COPY_READ_BUFFER:9,
    getParameter:key=>key===1?program:null,getProgramParameter:()=>3,getActiveUniform:(_,i)=>({name:['_group_0_binding_0_vs.mvp','_group_0_binding_0_vs.model','_group_0_binding_0_fs.base'][i]}),getUniformIndices:()=>[0,1],getActiveUniforms:(_,indices,key)=>key===3?indices.map(i=>i*64):[0],getActiveUniformBlockParameter:()=>0,getIndexedParameter:key=>key===6?buffer:0,bindBuffer(){},getBufferSubData:(_,offset,target)=>target.set(values)};
  camera.beforeDraw(gl);let completed=0;assert.equal(camera.focus(new Vector3(-1,1,2),()=>completed++),true);
  for(let i=0;i<25;i++){now+=16;const pending=[...frames.values()];frames.clear();camera.beforeDraw(gl);for(const fn of pending)fn(now);}
  assert.equal(completed,1);assert.equal(events.at(-1).type,'mouseup');assert.equal(listeners.size,0);assert.equal(frames.size,0);
  const count=events.length;now+=1000;camera.beforeDraw(gl);assert.equal(events.length,count,'No camera movement is sent after release');
  assert.equal(camera.focus(new Vector3(-1,1,2),()=>completed++),true);camera.cancel();assert.equal(events.at(-1).type,'mouseup');assert.equal(listeners.size,0);assert.equal(completed,2);
});
