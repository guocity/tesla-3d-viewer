import { Matrix4, Vector3, Vector4 } from 'three';

export function cameraFromProjection(vp) {
  const inverse=vp.clone().invert(), origin=new Vector4(0,0,1,0).applyMatrix4(inverse);
  if(Math.abs(origin.w)<1e-8)return null;
  const eye=new Vector3(origin.x,origin.y,origin.z).divideScalar(origin.w);
  const e=vp.elements,back=new Vector3(-e[3],-e[7],-e[11]).normalize();
  // Preserve the renderer's signed clip axes rather than absorbing their
  // flips into the view rotation. The authored camera has no roll.
  const right=new Vector3(0,eye.y<0?-1:1,0).cross(back).normalize();
  const up=new Vector3().crossVectors(back,right).normalize();
  const world=new Matrix4().makeBasis(right,up,back).setPosition(eye);
  return {eye,projection:vp.clone().multiply(world),inverse,forward:back.clone().negate()};
}

export function patchSceneCameraShader(source) {
  if(source.includes('uShowroomCameraEnabled'))return source;
  if(!/_group_\w+\.(?:mvp|ivp)/.test(source))return source;
  source=source.replace(/(_group_\w+\.mvp)\b/g,'showroomCameraMVP($1)')
    .replace(/(_group_\w+\.ivp)\b/g,'showroomCameraInverse($1)')
    .replace(/(_group_\w+\.(?:eye|cam))\b/g,'showroomCameraEye($1)');
  return source.replace('precision highp int;',`precision highp int;
uniform float uShowroomCameraEnabled;
uniform mat4 uShowroomCameraDelta;
uniform mat4 uShowroomCameraInverse;
uniform vec3 uShowroomCameraEye;
mat4 showroomCameraMVP(mat4 original) { return uShowroomCameraEnabled > 0.5 ? uShowroomCameraDelta * original : original; }
mat4 showroomCameraInverse(mat4 original) { return uShowroomCameraEnabled > 0.5 ? original * uShowroomCameraInverse : original; }
vec4 showroomCameraEye(vec4 original) { return uShowroomCameraEnabled > 0.5 ? vec4(uShowroomCameraEye, original.w) : original; }
`);
}

export function createSceneCamera(canvas) {
  const programs=new WeakMap(),buffers=new WeakMap();
  let sourceCamera=null,current=null,enabled=false,yaw=0,pitch=.2,radius=10,physicalLimit=10,target=new Vector3(0,.8,0),transition=null;
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const angle=v=>Math.atan2(Math.sin(v),Math.cos(v));
  function initialize(){
    if(enabled)return true;if(!sourceCamera)return false;
    const distance=(target.y-sourceCamera.eye.y)/sourceCamera.forward.y;
    if(Number.isFinite(distance)&&distance>0)target.copy(sourceCamera.eye).addScaledVector(sourceCamera.forward,distance);
    const offset=sourceCamera.eye.clone().sub(target);radius=offset.length();physicalLimit=radius;yaw=Math.atan2(offset.x,offset.z);pitch=Math.asin(clamp(offset.y/radius,-1,1));enabled=true;return true;
  }
  function pose(now=performance.now()) {
    if(transition){const t=clamp((now-transition.start)/700,0,1),s=t*t*(3-2*t);
      yaw=transition.yaw+transition.dyaw*s;pitch=transition.pitch+(.12-transition.pitch)*s;physicalLimit=transition.physicalLimit+(8.5-transition.physicalLimit)*s;radius=transition.radius+(transition.endRadius-transition.radius)*s;
      target.copy(transition.target).lerp(transition.endTarget,s);
      if(t===1){const done=transition.done;transition=null;done?.();}
    }
    return new Vector3(Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),Math.cos(yaw)*Math.cos(pitch)).multiplyScalar(Math.min(radius,physicalLimit)).add(target);
  }
  const cancel=()=>{if(transition){const done=transition.done;transition=null;done?.('interrupted');}};
  function rotate(dx,dy){if(!initialize())return;cancel();yaw-=dx*.006;pitch=clamp(pitch+dy*.006,.06,1.25);}
  function zoom(delta){if(!initialize())return;cancel();radius=clamp(radius*Math.exp(-delta*.0012),4,28);}
  let mouse=null,touches=new Map();
  canvas.addEventListener?.('mousedown',event=>{if(event.button!==0)return;initialize();cancel();mouse={x:event.clientX,y:event.clientY};event.preventDefault();event.stopImmediatePropagation();},true);
  canvas.addEventListener?.('mousemove',event=>{if(mouse){rotate(event.clientX-mouse.x,event.clientY-mouse.y);mouse={x:event.clientX,y:event.clientY};}event.stopImmediatePropagation();},true);
  canvas.addEventListener?.('mouseup',event=>{mouse=null;event.stopImmediatePropagation();},true);
  globalThis.window?.addEventListener('mouseup',()=>{mouse=null;});
  const touchState=()=>{const p=[...touches.values()];return p.length>1?{distance:Math.hypot(p[0].x-p[1].x,p[0].y-p[1].y)}:p[0];};
  for(const type of ['touchstart','touchmove','touchend','touchcancel'])canvas.addEventListener?.(type,event=>{
    event.preventDefault();event.stopImmediatePropagation();const before=touchState();
    if(type==='touchstart'){initialize();cancel();}
    for(const point of event.changedTouches){if(type==='touchend'||type==='touchcancel')touches.delete(point.identifier);else touches.set(point.identifier,{x:point.clientX,y:point.clientY});}
    const after=touchState();
    if(type==='touchmove'&&before&&after){if(before.distance&&after.distance)zoom(Math.log(after.distance/before.distance)/.0012);else if(!before.distance&&!after.distance)rotate(after.x-before.x,after.y-before.y);}
  },{capture:true,passive:false});
  canvas.addEventListener?.('wheel',event=>{event.preventDefault();event.stopImmediatePropagation();zoom(event.deltaY);},{capture:true,passive:false});
  return {
    get current(){return current;},
    reset(){sourceCamera=current=null;enabled=false;transition=null;mouse=null;touches.clear();target.set(0,.8,0);},
    cancel,
    focus(point,done){
      if(!initialize()||!point)return false;cancel();
      const rect=canvas.getBoundingClientRect(),heading=Math.atan2(point.chargeSide||-1,Math.sign(point.z)||1);
      transition={start:performance.now(),yaw,dyaw:angle(heading-yaw),pitch,radius,physicalLimit,target:target.clone(),endTarget:new Vector3(0,.8,.5),endRadius:rect.width/rect.height<.8?15:10.5,done};return true;
    },
    observeUpload(gl,kind,destination,source,sourceOffset=0,length){
      if(!ArrayBuffer.isView(source))return;
      const binding=kind===gl.UNIFORM_BUFFER?gl.UNIFORM_BUFFER_BINDING:kind===gl.COPY_WRITE_BUFFER?gl.COPY_WRITE_BUFFER_BINDING:null;if(binding===null)return;
      const ranges=buffers.get(gl.getParameter(binding));if(!ranges)return;
      const unit=source.BYTES_PER_ELEMENT||1,size=(length??(source.byteLength/unit-sourceOffset))*unit;
      if(size>1024*1024)return;
      for(let i=ranges.length-1;i>=0;i--)if(ranges[i].start<destination+size&&ranges[i].start+ranges[i].bytes.length>destination)ranges.splice(i,1);
      ranges.unshift({start:destination,bytes:new Uint8Array(source.buffer,source.byteOffset+sourceOffset*unit,size).slice()});ranges.length=Math.min(ranges.length,12);
    },
    beforeDraw(gl){
      const program=gl.getParameter(gl.CURRENT_PROGRAM);if(!program)return;
      let data=programs.get(program);
      if(data===undefined){
        data=null;const active=gl.getUniformLocation(program,'uShowroomCameraEnabled');
        if(active!==null){
          const names=Array.from({length:gl.getProgramParameter(program,gl.ACTIVE_UNIFORMS)},(_,i)=>gl.getActiveUniform(program,i).name);
          const name=names.find(n=>n.endsWith('_fs.ivp'))||names.find(n=>n.endsWith('.ivp'))||names.find(n=>n.endsWith('_vs.mvp'))||names.find(n=>n.endsWith('.mvp')); 
          if(name){const prefix=name.slice(0,name.lastIndexOf('.')),modelName=`${prefix}.model`,indices=gl.getUniformIndices(program,[name,...(names.includes(modelName)?[modelName]:[])]),offsets=gl.getActiveUniforms(program,indices,gl.UNIFORM_OFFSET),block=gl.getActiveUniforms(program,[indices[0]],gl.UNIFORM_BLOCK_INDEX)[0];
            data={active,delta:gl.getUniformLocation(program,'uShowroomCameraDelta'),inverse:gl.getUniformLocation(program,'uShowroomCameraInverse'),eye:gl.getUniformLocation(program,'uShowroomCameraEye'),binding:gl.getActiveUniformBlockParameter(program,block,gl.UNIFORM_BLOCK_BINDING),offset:offsets[0],model:offsets[1],isInverse:name.endsWith('.ivp'),values:new Float32Array(Math.max(...offsets)+64>>2)};
          }
        }programs.set(program,data);
      }
      if(!data)return;
      gl.uniform1f(data.active,0);
      const buffer=gl.getIndexedParameter(gl.UNIFORM_BUFFER_BINDING,data.binding);if(!buffer)return;
      const start=gl.getIndexedParameter(gl.UNIFORM_BUFFER_START,data.binding);
      let ranges=buffers.get(buffer);if(!ranges){ranges=[];buffers.set(buffer,ranges);}
      const size=data.values.byteLength,cached=ranges.find(r=>r.start<=start&&r.start+r.bytes.length>=start+size);
      if(cached)new Uint8Array(data.values.buffer).set(cached.bytes.subarray(start-cached.start,start-cached.start+size));
      else {const previous=gl.getParameter(gl.COPY_READ_BUFFER_BINDING);gl.bindBuffer(gl.COPY_READ_BUFFER,buffer);gl.getBufferSubData(gl.COPY_READ_BUFFER,start,data.values);gl.bindBuffer(gl.COPY_READ_BUFFER,previous);}
      const vp=new Matrix4().fromArray(data.values,data.offset/4),model=data.model===undefined?null:new Matrix4().fromArray(data.values,data.model/4);
      if(data.isInverse)vp.invert();else if(model)vp.multiply(model.clone().invert());
      const source=cameraFromProjection(vp);if(!source||!Number.isFinite(source.eye.length())||source.eye.length()<1)return;
      // Keep 90-degree environment cubemap captures in their authored views.
      if(Math.abs(source.projection.elements[5])<1.2)return;
      const reflected=source.eye.y<0;
      if(!reflected){sourceCamera=source;if(!enabled)current={eye:source.eye,mvp:vp};}
      if(!enabled)return;
      const worldEye=pose(),eye=worldEye.clone(),look=target.clone();if(reflected){eye.y=-eye.y;look.y=-look.y;}
      const view=new Matrix4().lookAt(eye,look,new Vector3(0,reflected?-1:1,0)).setPosition(eye).invert();
      // Widen the lens for distant framing while keeping the eye on the
      // showroom platform rather than passing through its surrounding rocks.
      const projection=source.projection.clone(),wide=Math.min(1,physicalLimit/radius);
      projection.elements[0]*=wide;projection.elements[5]*=wide;
      const replacement=projection.multiply(view),delta=replacement.clone().multiply(source.inverse);
      gl.uniform1f(data.active,1);if(data.delta)gl.uniformMatrix4fv(data.delta,false,delta.elements);if(data.inverse)gl.uniformMatrix4fv(data.inverse,false,delta.clone().invert().elements);if(data.eye)gl.uniform3f(data.eye,eye.x,eye.y,eye.z);
      if(!reflected)current={eye:worldEye,mvp:replacement,zoom:radius};
    },
  };
}
