import { Matrix4, Matrix3, Vector3, Quaternion, Euler } from 'three';
import { sampleTrack } from '../public/legacy/source-animation.js';

export function advanceToggle(current, target, elapsedSeconds, duration) {
  const step = Math.max(0, elapsedSeconds) / Math.max(0.15, duration);
  return target > current ? Math.min(target, current + step) : Math.max(target, current - step);
}

const labels = { LRDoorAnimationComplete:'Rear left falcon door', RRDoorAnimationComplete:'Rear right falcon door', LRDoorAnimationTop:'Rear left upper hinge', RRDoorAnimationTop:'Rear right upper hinge', LRDoorAnimationBottom:'Rear left lower hinge', RRDoorAnimationBottom:'Rear right lower hinge', LRDoorSensorAnimation:'Rear left door sensor', RRDoorSensorAnimation:'Rear right door sensor', RoofSensorAnimation:'Roof sensor', SpoilerAnimation:'Spoiler', SuspensionAnimation:'Suspension', ChargeportGlobalAnimation:'Charge port assembly', Jumper_Seat_Animation:'Jump seat', Jumper_Seat_Armrests_Animation:'Jump seat armrests', HoodAnimation:'Frunk', TrunkAnimation:'Trunk / liftgate', LFDoorAnimation:'Front left door', RFDoorAnimation:'Front right door', LRDoorAnimation:'Rear left door', RRDoorAnimation:'Rear right door', LFDoorMirrorAnimation:'Left mirror', RFDoorMirrorAnimation:'Right mirror', LFWindowAnimation:'Front left window', RFWindowAnimation:'Front right window', LRWindowAnimation:'Rear left window', RRWindowAnimation:'Rear right window', ChargeportAnimation:'Charge port', ChargePortAnimation:'Charge port', TonneauAnimation:'Tonneau cover' };
export function createShowroomAnimation(bridge, panel) {
  panel.innerHTML = '<div class="motion-heading"><div><span class="model-eyebrow">TESLA</span><h2>Vehicle controls</h2></div><button type="button" data-close aria-label="Close vehicle controls">×</button></div><div class="motion-switches" role="group" aria-label="Tesla vehicle controls"></div><div class="motion-caption"><span data-status>Choose a Tesla to animate</span><span>Combine any controls</span></div>';
  const list = panel.querySelector('.motion-switches'), status = panel.querySelector('[data-status]');
  let rig, parts, nodes = [], restWorld = [], normalization, inverseNormalization, segments = [], clips = [], last = 0, frame, dirty = false;
  const position = new Vector3(), normal = new Vector3(), euler = new Euler(0, 0, 0, 'YXZ');
  const deltas = new Map();
  function resetNodes() { for (const n of nodes) { n.p.copy(n.restP); n.q.copy(n.restQ); n.s.copy(n.restS); } }
  function worldMatrices() { for (const n of nodes) { n.local.compose(n.p, n.q, n.s); n.world.copy(n.local); if (n.parent >= 0) n.world.premultiply(nodes[n.parent].world); } }
  function resolve(path) {
    const clean = path.replace(/^\.\//, ''), leaf = clean.split('/').at(-1);
    const matches = nodes.map((n,i)=>({n,i})).filter(({n})=>n.name===leaf);
    return matches.find(({i})=>{ const names=[]; for(let at=i;at>=0;at=nodes[at].parent) names.unshift(nodes[at].name); return names.join('/').endsWith(clean); })?.i ?? matches[0]?.i;
  }
  function apply() {
    if (!rig || !bridge.ready) return;
    resetNodes();
    const allTracks = clips.flatMap(c => c.tracks), affected = new Set(allTracks.map(t=>t.node));
    for (const clip of clips) {
      if (clip.current <= 0) continue;
      for (const { node, track, property } of clip.tracks) {
        const n = nodes[node], value = sampleTrack(track, clip.current * clip.duration);
        if (value == null) continue;
        if (track.type === 'transform') { n.p.copy(value.position); n.q.copy(value.quaternion); n.s.copy(value.scale); }
        else if (property === 'rotation_degrees') { euler.set(...value.map(v=>v*Math.PI/180),'YXZ'); n.q.setFromEuler(euler); }
        else if (property === 'translation') n.p.fromArray(value);
        else if (property === 'delta_translation') n.p.copy(n.restP).add(position.fromArray(value));
        else if (property === 'scale') n.s.fromArray(value);
      }
    }
    worldMatrices(); deltas.clear();
    const ranges = new Map();
    for (const segment of segments) {
      let changed = false;
      for (let at=segment.node;at>=0;at=nodes[at].parent) if(affected.has(at)){ changed=true; break; }
      if (!changed) continue;
      const part = parts.find(p=>p.name===segment.material);
      if (!part) continue;
      let delta = deltas.get(segment.node);
      if (!delta) {
        const matrix = new Matrix4().copy(nodes[segment.node].world).multiply(restWorld[segment.node]);
        matrix.premultiply(normalization).multiply(inverseNormalization);
        delta = {matrix,normal:new Matrix3().getNormalMatrix(matrix)}; deltas.set(segment.node,delta);
      }
      const source = new DataView(part.rest.buffer,part.rest.byteOffset,part.rest.byteLength), target = new DataView(part.current.buffer), end=segment.first+segment.count;
      for(let i=segment.first;i<end;i++){
        const at=i*20;
        position.set(source.getInt16(at,true)/32767*rig.quant[0],source.getInt16(at+2,true)/32767*rig.quant[1],source.getInt16(at+4,true)/32767*rig.quant[2]).applyMatrix4(delta.matrix);
        for(let axis=0;axis<3;axis++) target.setInt16(at+axis*2,Math.max(-32767,Math.min(32767,Math.round(position.getComponent(axis)/rig.quant[axis]*32767))),true);
        let x=source.getInt16(at+8,true)/32767,y=source.getInt16(at+10,true)/32767;
        const z=1-Math.abs(x)-Math.abs(y),t=Math.max(-z,0);x+=x>=0?-t:t;y+=y>=0?-t:t;
        normal.set(x,y,z).applyNormalMatrix(delta.normal);
        const sum=Math.abs(normal.x)+Math.abs(normal.y)+Math.abs(normal.z)||1;x=normal.x/sum;y=normal.y/sum;
        if(normal.z<0){const old=x;x=(1-Math.abs(y))*(old>=0?1:-1);y=(1-Math.abs(old))*(y>=0?1:-1);}
        target.setInt16(at+8,Math.round(x*32767),true);target.setInt16(at+10,Math.round(y*32767),true);
      }
      const range=ranges.get(part)||{first:segment.first,end};range.first=Math.min(range.first,segment.first);range.end=Math.max(range.end,end);ranges.set(part,range);
    }
    for(const[part,r]of ranges)bridge.upload(part,r.first,r.end-r.first);
    panel.dataset.active=String(clips.filter(c=>c.current>0).length);
  }
  function setTarget(clip, target) { clip.target=target;clip.button.setAttribute('aria-checked',String(Boolean(target)));dirty=true; }
  panel.querySelector('[data-close]').onclick=()=>{panel.hidden=true;};
  function tick(now){
    frame=requestAnimationFrame(tick);if(!last)last=now;const elapsed=now-last;if(elapsed<1000/24)return;last=now;
    if(!rig)return;if(!bridge.ready){status.textContent='Preparing showroom…';return;}
    panel.dataset.ready='true';status.textContent=`${clips.filter(c=>c.target).length} enabled`;
    if(document.hidden)return;
    for(const c of clips)if(c.current!==c.target){c.current=advanceToggle(c.current,c.target,Math.min(elapsed/1000,0.1),c.duration);dirty=true;}
    if(dirty){apply();dirty=false;}
  }
  frame=requestAnimationFrame(tick);
  return {
    bind(nextRig,nextParts){
      rig=nextRig;parts=nextParts;nodes=[];segments=rig?.segments||[];clips=[];dirty=false;list.replaceChildren();panel.dataset.ready='false';panel.dataset.active='0';
      if(!rig){status.textContent='APK controls are available on Tesla models';return;}
      normalization=new Matrix4().fromArray(rig.normalize);inverseNormalization=normalization.clone().invert();
      nodes=rig.nodes.map(n=>{const p=new Vector3(),q=new Quaternion(),s=new Vector3();new Matrix4().fromArray(n.matrix).decompose(p,q,s);return{...n,p,q,s,restP:p.clone(),restQ:q.clone(),restS:s.clone(),local:new Matrix4(),world:new Matrix4()};});
      worldMatrices();restWorld=nodes.map(n=>n.world.clone().invert());
      for(const source of rig.animations){
        const tracks=(source.tracks||[]).map(track=>{const colon=track.target.lastIndexOf(':');return{node:resolve(colon<0?track.target:track.target.slice(0,colon)),property:colon<0?'transform':track.target.slice(colon+1),track};}).filter(t=>t.node!==undefined);
        if(!tracks.length)continue;
        const button=document.createElement('button');button.type='button';button.className='motion-switch';button.setAttribute('role','switch');button.setAttribute('aria-checked','false');button.dataset.clip=source.name;
        const label=document.createElement('span');label.textContent=labels[source.name]||source.name.replace(/Animation$/,'').replace(/([a-z])([A-Z])/g,'$1 $2');
        button.append(label);list.append(button);
        const clip={tracks,duration:source.duration||1,current:0,target:0,button};button.onclick=()=>setTarget(clip,clip.target?0:1);clips.push(clip);
      }
    },
    stop(){clips.forEach(c=>{c.current=0;c.target=0;});bridge.reset();},
    dispose(){cancelAnimationFrame(frame);},
  };
}
