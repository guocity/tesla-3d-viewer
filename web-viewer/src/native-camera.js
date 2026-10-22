import { Matrix4, Vector3 } from 'three';
import { cameraFromProjection } from './scene-camera.js';

// Observe the authored camera without changing shaders, matrices or input handlers.
// Charging sends one short native drag, then releases the pointer completely.
export function createNativeCamera(canvas) {
  const programs=new WeakMap();let current=null,lastRead=0,stop;
  const angle=v=>Math.atan2(Math.sin(v),Math.cos(v));
  const mouse=(type,x,y,buttons)=>canvas.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window,clientX:x,clientY:y,button:0,buttons}));
  function cancel(){stop?.('interrupted');}
  return {
    get current(){return current;},cancel,
    reset(){cancel();current=null;},
    observeUpload(){},
    beforeDraw(gl){
      if(performance.now()-lastRead<16)return;
      const program=gl.getParameter(gl.CURRENT_PROGRAM);if(!program)return;
      let data=programs.get(program);
      if(data===undefined){
        data=null;
        const names=Array.from({length:gl.getProgramParameter(program,gl.ACTIVE_UNIFORMS)},(_,i)=>gl.getActiveUniform(program,i).name);
        const name=names.find(n=>n.endsWith('_vs.mvp'))||names.find(n=>n.endsWith('.mvp'));
        if(name&&names.some(n=>n.endsWith('.base'))){
          const prefix=name.slice(0,name.lastIndexOf('.')),model=`${prefix}.model`,fields=[name,...(names.includes(model)?[model]:[])];
          const indices=gl.getUniformIndices(program,fields),offsets=gl.getActiveUniforms(program,indices,gl.UNIFORM_OFFSET),block=gl.getActiveUniforms(program,[indices[0]],gl.UNIFORM_BLOCK_INDEX)[0];
          data={offset:offsets[0],model:offsets[1],binding:gl.getActiveUniformBlockParameter(program,block,gl.UNIFORM_BLOCK_BINDING),values:new Float32Array((Math.max(...offsets)+64)/4)};
        }
        programs.set(program,data);
      }
      if(!data)return;
      const buffer=gl.getIndexedParameter(gl.UNIFORM_BUFFER_BINDING,data.binding);if(!buffer)return;
      const previous=gl.getParameter(gl.COPY_READ_BUFFER_BINDING),start=gl.getIndexedParameter(gl.UNIFORM_BUFFER_START,data.binding);
      gl.bindBuffer(gl.COPY_READ_BUFFER,buffer);gl.getBufferSubData(gl.COPY_READ_BUFFER,start,data.values);gl.bindBuffer(gl.COPY_READ_BUFFER,previous);
      const vp=new Matrix4().fromArray(data.values,data.offset/4);
      const source=cameraFromProjection(vp);
      if(!source||source.eye.y<=0||source.eye.length()<2||Math.abs(source.projection.elements[5])<1.2)return;
      current={...source,mvp:vp};lastRead=performance.now();
    },
    focus(point,done,instance){
      if(!current||!point)return false;
      cancel();
      const rect=canvas.getBoundingClientRect(),x=rect.left+rect.width*.5,y=rect.top+rect.height*.22;
      const machine=instance?.animator?.stateMachines.find(m=>m.stateMachine.name==='Garage')?.instance;
      const send=(type,px,py,buttons)=>{
        mouse(type,px,py,buttons);
        machine?.advanceAndApply(type==='mousemove'?.08:0);
      };
      canvas.focus?.({preventScroll:true});machine?.clearFocus();machine?.focusNext();instance?.play('Garage');
      const target=new Vector3(0,.8,0),startEye=current.eye.clone();
      const pose=eye=>{const d=eye.clone().sub(target);return{yaw:Math.atan2(d.x,d.z),pitch:Math.atan2(d.y,Math.hypot(d.x,d.z))};};
      const initial=pose(startEye),desired=Math.atan2(point.chargeSide||Math.sign(point.x)||-1,-.45*(Math.sign(point.z)||1));
      let frame,ended=false,cx=x,cy=y;
      const finish=state=>{if(ended)return;ended=true;cancelAnimationFrame(frame);send('mouseup',cx,cy,0);canvas.removeEventListener('pointerdown',interrupt,true);canvas.removeEventListener('wheel',interrupt,true);stop=undefined;done?.(state);};
      const interrupt=e=>{if(e.isTrusted)finish('interrupted');};
      stop=finish;canvas.addEventListener('pointerdown',interrupt,true);canvas.addEventListener('wheel',interrupt,true);
      send('mouseover',x,y,0);send('mousemove',x,y,0);send('mousedown',x,y,1);
      let steps=0;
      const clamp=(v,limit)=>Math.max(-limit,Math.min(limit,v));
      const move=now=>{
        if(ended)return;
        const actual=pose(current.eye),yawError=angle(desired-actual.yaw),pitchError=.08-actual.pitch;
        if(steps++>=10||(steps>3&&Math.abs(yawError)<.035&&Math.abs(pitchError)<.025)){
          // Two zero-delta input samples settle the native drag before release.
          send('mousemove',cx,cy,1);
          frame=requestAnimationFrame(()=>{send('mousemove',cx,cy,1);frame=requestAnimationFrame(()=>finish());});
          return;
        }
        const dx=clamp(yawError/-.006*.7,80),dy=clamp(pitchError/.006*.7,25);
        if(cx+dx<rect.left+8||cx+dx>(rect.left+rect.width)-8||cy+dy<rect.top+8||cy+dy>(rect.top+rect.height)-8){
          send('mouseup',cx,cy,0);cx=x;cy=y;send('mousemove',cx,cy,0);send('mousedown',cx,cy,1);
        }
        cx+=dx;cy+=dy;send('mousemove',cx,cy,1);frame=requestAnimationFrame(move);
      };
      frame=requestAnimationFrame(move);
      return true;
    },
  };
}
