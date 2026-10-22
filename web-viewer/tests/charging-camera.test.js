import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Matrix4, Vector3 } from 'three';
import { cameraFromProjection, createSceneCamera, patchSceneCameraShader } from '../src/scene-camera.js';

function projection(){return new Matrix4().makePerspective(-.15,.15,.1,-.1,.2,1000);}
function view(eye,up=new Vector3(0,1,0)){return new Matrix4().lookAt(eye,new Vector3(0,.8,0),up).setPosition(eye).invert();}
function closeMatrix(actual,expected){actual.elements.forEach((n,i)=>assert.ok(Math.abs(n-expected.elements[i])<1e-8));}

test('camera extraction preserves perspective for normal and reflected scene passes',()=>{
  for(const [eye,up]of [[new Vector3(6,2,8),new Vector3(0,1,0)],[new Vector3(6,-2,8),new Vector3(0,-1,0)]])for(const flip of [1,-1]){
    const v=view(eye,up),p=new Matrix4().makePerspective(-.05,.25,.14,-.06,.2,1000);
    p.elements[0]*=flip;
    const vp=p.clone().multiply(v),camera=cameraFromProjection(vp);
    assert.ok(camera.eye.distanceTo(eye)<1e-8);
    closeMatrix(camera.projection,p);
    closeMatrix(camera.projection.clone().multiply(v),vp);
  }
  assert.equal(cameraFromProjection(new Matrix4().makeOrthographic(-1,1,1,-1,.1,10)),null);
});

test('camera shader updates geometry, inverse ray projection, and eye while preserving exposure',()=>{
  const source='precision highp int; void main(){ mat4 vp=_group_0_binding_0_vs.mvp; mat4 inverse=_group_0_binding_0_fs.ivp; vec4 eye=_group_0_binding_0_fs.eye; vec4 camera=_group_0_binding_0_fs.cam; }';
  const patched=patchSceneCameraShader(source);
  assert.ok(patched.includes('showroomCameraMVP(_group_0_binding_0_vs.mvp)'));
  assert.ok(patched.includes('showroomCameraInverse(_group_0_binding_0_fs.ivp)'));
  assert.ok(patched.includes('original * uShowroomCameraInverse'));
  assert.ok(patched.includes('vec4(uShowroomCameraEye, original.w)'));
  assert.equal(patchSceneCameraShader(patched),patched);
  assert.equal(patchSceneCameraShader('unrelated UI shader'),'unrelated UI shader');
});

test('charging transition completes once and orbit input stays free afterwards',t=>{
  let now=0;t.mock.method(performance,'now',()=>now);
  const events={},windowBefore=globalThis.window;globalThis.window={addEventListener(){}};t.after(()=>{if(windowBefore===undefined)delete globalThis.window;else globalThis.window=windowBefore;});
  const canvas={addEventListener:(type,callback)=>events[type]=callback,getBoundingClientRect:()=>({width:1100,height:760})};
  const camera=createSceneCamera(canvas),program={},buffer={},values=new Float32Array(32);
  values.set(projection().multiply(view(new Vector3(6,2,8))).elements);values.set(new Matrix4().elements,16);
  const gl={CURRENT_PROGRAM:1,ACTIVE_UNIFORMS:2,UNIFORM_OFFSET:3,UNIFORM_BLOCK_INDEX:4,UNIFORM_BLOCK_BINDING:5,UNIFORM_BUFFER_BINDING:6,UNIFORM_BUFFER_START:7,COPY_READ_BUFFER_BINDING:8,COPY_READ_BUFFER:9,
    getParameter:key=>key===1?program:null,getUniformLocation:(_,name)=>name,getProgramParameter:()=>2,getActiveUniform:(_,i)=>({name:['_group_0_binding_0_vs.mvp','_group_0_binding_0_vs.model'][i]}),getUniformIndices:()=>[0,1],getActiveUniforms:(_,indices,key)=>key===3?indices.map(i=>i*64):[0],getActiveUniformBlockParameter:()=>0,getIndexedParameter:key=>key===6?buffer:0,bindBuffer(){},getBufferSubData:(_,offset,target)=>target.set(values),uniform1f(){},uniform3f(){},uniformMatrix4fv(){}};
  camera.beforeDraw(gl);let completed=0;camera.focus(new Vector3(-1,1,2),()=>completed++);
  now=700;camera.beforeDraw(gl);assert.equal(completed,1);assert.ok(camera.current.eye.x<0);
  const focused=camera.current.eye.clone();now=1500;camera.beforeDraw(gl);assert.ok(focused.distanceTo(camera.current.eye)<1e-8);assert.equal(completed,1);
  const event=(x,y)=>({button:0,clientX:x,clientY:y,preventDefault(){},stopImmediatePropagation(){}});
  events.mousedown(event(150,350));events.mousemove(event(230,350));events.mouseup(event(230,350));camera.beforeDraw(gl);
  assert.ok(focused.distanceTo(camera.current.eye)>1);
  const rotated=camera.current.eye.clone();now=5000;camera.beforeDraw(gl);assert.ok(rotated.distanceTo(camera.current.eye)<1e-8);
});

test('PBR fragment eye follows the camera even without a matrix uniform',()=>{
  const fragment='precision highp int; void main(){ vec3 v=normalize(_group_0_binding_0_fs.eye.xyz-position); vec4 color=exposureOut(albedo); }';
  const patched=patchSceneCameraShader(fragment);
  assert.ok(patched.includes('showroomCameraEye(_group_0_binding_0_fs.eye).xyz'));
  assert.ok(patched.includes('vec4 color=exposureOut(albedo)'));
  assert.equal(patchSceneCameraShader(patched),patched);
});
