import { cybertruckLampClips } from './cybertruck-lighting.js';
import { chargingOpacity } from './charging-fade.js';
import { Matrix4, Matrix3, Vector3, Quaternion, Euler } from 'three';
import { sampleTrack } from '../public/legacy/source-animation.js';

export function advanceToggle(current, target, elapsedSeconds, duration) {
  const step = Math.max(0, elapsedSeconds) / Math.max(0.15, duration);
  return target > current ? Math.min(target, current + step) : Math.max(target, current - step);
}

const labels = { LeftSignalAnimation:'Left turn signal', RightSignalAnimation:'Right turn signal', DRLAnimation:'DRL', BrakeLightsAnimation:'Brake lights', RoofLightbarAnimation:'Roof light bar', LRDoorAnimationComplete:'Rear left falcon door', RRDoorAnimationComplete:'Rear right falcon door', LRDoorAnimationTop:'Rear left upper hinge', RRDoorAnimationTop:'Rear right upper hinge', LRDoorAnimationBottom:'Rear left lower hinge', RRDoorAnimationBottom:'Rear right lower hinge', LRDoorSensorAnimation:'Rear left door sensor', RRDoorSensorAnimation:'Rear right door sensor', RoofSensorAnimation:'Roof sensor', SpoilerAnimation:'Spoiler', SuspensionAnimation:'Suspension', ChargeportGlobalAnimation:'Charge port assembly', Jumper_Seat_Animation:'Jump seat', Jumper_Seat_Armrests_Animation:'Jump seat armrests', HoodAnimation:'Frunk', TrunkAnimation:'Trunk / liftgate', LFDoorAnimation:'Front left door', RFDoorAnimation:'Front right door', LRDoorAnimation:'Rear left door', RRDoorAnimation:'Rear right door', LFDoorMirrorAnimation:'Left mirror', RFDoorMirrorAnimation:'Right mirror', LFWindowAnimation:'Front left window', RFWindowAnimation:'Front right window', LRWindowAnimation:'Rear left window', RRWindowAnimation:'Rear right window', ChargeportAnimation:'Charge port', ChargePortAnimation:'Charge port', TonneauAnimation:'Tonneau cover' };
export function advanceCharging(current, connected, portOpen, elapsed) {
  return advanceToggle(current, connected && portOpen >= .98 ? 1 : 0, elapsed, .8);
}

export function createShowroomAnimation(bridge, panel) {
  panel.innerHTML = '<div class="motion-heading"><div><span class="model-eyebrow">TESLA</span><h2>Vehicle controls</h2></div><button type="button" data-close aria-label="Close vehicle controls">×</button></div><div class="motion-switches" role="group" aria-label="Tesla vehicle controls"></div><div class="motion-caption"><span data-status>Choose a Tesla to animate</span><span>Combine any controls</span></div>';
  const list = panel.querySelector('.motion-switches'), status = panel.querySelector('[data-status]');
  let rig, parts, nodes = [], restWorld = [], normalization, inverseNormalization, segments = [], clips = [], last = 0, frame, dirty = false, charging = false, connection = 0, chargeManaged = false, cableNodes = [];
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
      if (clip.current <= 0 && !clip.alwaysApply) continue;
      for (const { node, track, property } of clip.tracks) {
        const n = nodes[node], value = sampleTrack(track, (clip.blink && Math.floor(last / 450) % 2 ? 0 : clip.current) * clip.duration);
        if (value == null) continue;
        if (track.type === 'transform') { n.p.copy(value.position); n.q.copy(value.quaternion); n.s.copy(value.scale); }
        else if (property === 'rotation_degrees') { euler.set(...value.map(v=>v*Math.PI/180),'YXZ'); n.q.setFromEuler(euler); }
        else if (property.startsWith('rotation_degrees:')) {
          euler.setFromQuaternion(n.q, 'YXZ');
          euler[property.split(':')[1]] = value * Math.PI / 180;
          n.q.setFromEuler(euler);
        }
        else if (property === 'translation') n.p.fromArray(value);
        else if (property === 'delta_translation') n.p.copy(n.restP).add(position.fromArray(value));
        else if (property === 'scale') n.s.fromArray(value);
      }
    }
    for (const i of cableNodes) {
      affected.add(i);
      if (connection <= 0) nodes[i].s.setScalar(0);

    }
    worldMatrices(); deltas.clear();
    const ranges = new Map();
    for (const segment of segments) {
      let changed = false, cable = false;
      for (let at=segment.node;at>=0;at=nodes[at].parent) {
        if (affected.has(at)) changed = true;
        if (cableNodes.includes(at)) cable = true;
      }
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
        if (cable) target.setUint8(at+16, Math.round(chargingOpacity(connection)*127));
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
  function setTarget(clip, target) {
    if (clip.exclusiveGroup) {
      // Switch emitters together: cross-fading these overlapping strips would
      // briefly show both running and brake lights again.
      for (const other of clips.filter(c=>c.exclusiveGroup===clip.exclusiveGroup)) {
        other.current=other.target=other===clip?target:1-target;
        other.button.setAttribute('aria-checked',String(Boolean(other.target)));
      }
    } else { clip.target=target;if(clip.blink)clip.current=target;clip.button.setAttribute('aria-checked',String(Boolean(target))); }
    dirty=true;
  }
  panel.querySelector('[data-close]').onclick=()=>{panel.hidden=true;};
  function tick(now){
    frame=requestAnimationFrame(tick);if(!last)last=now;const elapsed=now-last;if(elapsed<1000/24)return;last=now;
    if(!rig)return;if(!bridge.ready){status.textContent='Preparing showroom…';return;}
    panel.dataset.ready='true';status.textContent=`${clips.filter(c=>c.target).length} enabled`;
    if(document.hidden)return;
    for(const c of clips)if(c.current!==c.target){c.current=advanceToggle(c.current,c.target,Math.min(elapsed/1000,0.1),c.duration);dirty=true;}
    const ports = clips.filter(c => /^chargeport(?:global)?animation$/i.test(c.button.dataset.clip));
    const portOpen = ports.length ? Math.min(...ports.map(c=>c.current)) : 1;
    const nextConnection = advanceCharging(connection, charging, portOpen, Math.min(elapsed/1000,.1));
    if (nextConnection !== connection) { connection = nextConnection; dirty = true; }
    if (chargeManaged && !charging && connection === 0) {
      for (const c of ports) if (c.target !== 0) setTarget(c, 0);
    }
    bridge.setChargingFlow?.(charging && connection > 0);
    if(clips.some(c=>c.blink && c.target))dirty=true;
    if(dirty){apply();dirty=false;}
  }
  frame=requestAnimationFrame(tick);
  return {
    bind(nextRig,nextParts){
      rig=nextRig;parts=nextParts;nodes=[];segments=rig?.segments||[];clips=[];dirty=true;charging=false;connection=0;chargeManaged=false;cableNodes=[];list.replaceChildren();panel.dataset.ready='false';panel.dataset.active='0';
      if(!rig){status.textContent='APK controls are available on Tesla models';return;}
      normalization=new Matrix4().fromArray(rig.normalize);inverseNormalization=normalization.clone().invert();
      nodes=rig.nodes.map(n=>{const p=new Vector3(),q=new Quaternion(),s=new Vector3();new Matrix4().fromArray(n.matrix).decompose(p,q,s);return{...n,p,q,s,restP:p.clone(),restQ:q.clone(),restS:s.clone(),local:new Matrix4(),world:new Matrix4()};});
      cableNodes=nodes.flatMap((n,i)=> n.name==='APK_ChargeCable' ? [i] : []);
      worldMatrices();restWorld=nodes.map(n=>n.world.clone().invert());
      // The roof bar is an optional accessory, absent until explicitly enabled.
      const roofBar = nodes.find(n => n.name === 'Roof_Lightbar');
      const roofAnimation = roofBar ? [{ name: 'RoofLightbarAnimation', duration: .6, alwaysApply: true, tracks: [{
        target: 'Roof_Lightbar:scale', type: 'value', interpolation: 1,
        times: [0, .6], values: [[0, 0, 0], roofBar.restS.toArray()],
      }] }] : [];
      for(const source of [...(rig.animations || []), ...roofAnimation, ...cybertruckLampClips(nodes)]){
        const tracks=(source.tracks||[]).map(track=>{const [path, ...property] = track.target.split(':');return{node:resolve(path),property:property.length?property.join(':'):'transform',track};}).filter(t=>t.node!==undefined);
        if(!tracks.length)continue;
        const button=document.createElement('button');button.type='button';button.className='motion-switch';button.setAttribute('role','switch');button.setAttribute('aria-checked','false');button.dataset.clip=source.name;
        const label=document.createElement('span');label.textContent=labels[source.name]||source.name.replace(/Animation$/,'').replace(/([a-z])([A-Z])/g,'$1 $2');
        button.append(label);if(!source.hiddenControl)list.append(button);
        const initial=Number(Boolean(source.defaultOn));
        button.setAttribute('aria-checked',String(Boolean(initial)));
        const clip={tracks,duration:source.duration||1,current:initial,target:initial,button,alwaysApply:Boolean(source.alwaysApply),exclusiveGroup:source.exclusiveGroup,blink:source.blink};button.onclick=()=>setTarget(clip,clip.target?0:1);clips.push(clip);
      }
    },
    getChargePortPoint() {
      const index = cableNodes[0];
      if (index === undefined || !normalization) return null;
      const point = new Vector3().setFromMatrixPosition(nodes[index].world).applyMatrix4(normalization);
      point.chargeSide = Math.sign(new Vector3(0,0,-1).transformDirection(nodes[index].world).x) || -1;
      return point;
    },
    getChargingState() {
      const ports = clips.filter(c => /^chargeport(?:global)?animation$/i.test(c.button.dataset.clip));
      return { portOpen: ports.length ? Math.min(...ports.map(c=>c.current)) : 1, connection, opacity:chargingOpacity(connection), hasCable: cableNodes.length>0 };
    },
    refresh() { if (rig && bridge.ready) { apply(); dirty=false; } },
    setCharging(on) {
      charging=on; chargeManaged=true; dirty=true;
      if (on) for (const c of clips.filter(c => /^chargeport(?:global)?animation$/i.test(c.button.dataset.clip))) setTarget(c,1);
      return cableNodes.length>0;
    },
    setChargePort(open) {
      const ports = clips.filter(c => /^chargeport(?:global)?animation$/i.test(c.button.dataset.clip));
      ports.forEach(c => setTarget(c, Number(open)));
      return ports.length > 0;
    },
    stop(){charging=false;connection=0;chargeManaged=false;bridge.setChargingFlow?.(false);clips.forEach(c=>{c.current=0;c.target=0;});bridge.reset();},
    dispose(){cancelAnimationFrame(frame);},
  };
}
