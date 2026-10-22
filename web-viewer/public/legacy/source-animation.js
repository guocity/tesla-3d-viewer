import * as THREE from 'three';

function transform(value) {
  if (value.length === 12) return new THREE.Matrix4().set(value[0], value[1], value[2], value[9], value[3], value[4], value[5], value[10], value[6], value[7], value[8], value[11], 0, 0, 0, 1);
  return new THREE.Matrix4().compose(new THREE.Vector3().fromArray(value), new THREE.Quaternion().fromArray(value, 3), new THREE.Vector3().fromArray(value, 7));
}
export function sampleTrack(track, time) {
  const values = track.values;
  const times = track.times;
  if (!values?.length || !times?.length) return null;
  let hi = times.findIndex(t => t > time);
  if (hi < 0) hi = times.length - 1;
  let lo = Math.max(0, hi - 1);
  if (time >= times.at(-1)) lo = hi;
  let f = hi === lo ? 0 : Math.max(0, Math.min(1, (time - times[lo]) / (times[hi] - times[lo])));
  if (track.interpolation === 0) f = 0;
  const a = values[lo], b = values[hi];
  if (track.type === 'transform') {
    const pa = new THREE.Vector3(), qa = new THREE.Quaternion(), sa = new THREE.Vector3();
    const pb = new THREE.Vector3(), qb = new THREE.Quaternion(), sb = new THREE.Vector3();
    transform(a).decompose(pa, qa, sa); transform(b).decompose(pb, qb, sb);
    return { position: pa.lerp(pb, f), quaternion: qa.slerp(qb, f), scale: sa.lerp(sb, f) };
  }
  if (typeof a === 'number') return a + (b - a) * f;
  return a.map((v, i) => v + (b[i] - v) * f);
}
export function createSourcePlayer({ findNode, dirty }) {
  const bar = document.createElement('div');
  bar.className = 'source-transport';
  bar.innerHTML = '<label>APK clip <select aria-label="APK animation clip"></select></label><button type="button">Play</button><label><input type="checkbox" checked> Loop</label><label>Speed <select aria-label="Animation speed"><option value="0.5">½×</option><option value="1" selected>1×</option><option value="2">2×</option></select></label><input aria-label="Animation timeline" type="range" min="0" max="1" step="0.001" value="0"><output>0.00 s</output>';
  document.body.append(bar);
  const [clips, speed] = bar.querySelectorAll('select');
  const play = bar.querySelector('button'), loop = bar.querySelector('[type=checkbox]'), timeline = bar.querySelector('[type=range]'), output = bar.querySelector('output');
  let root, asset, tracks = [], originals = new Map(), duration = 1, time = 0, playing = false;
  function restore() { for (const [node, pose] of originals) { node.position.copy(pose.p); node.quaternion.copy(pose.q); node.scale.copy(pose.s); node.visible = pose.visible; } }
  function apply() {
    for (const { node, track, property } of tracks) {
      const value = sampleTrack(track, time);
      if (value == null) continue;
      if (track.type === 'transform') { node.position.copy(value.position); node.quaternion.copy(value.quaternion); node.scale.copy(value.scale); }
      else if (property === 'rotation_degrees') node.quaternion.setFromEuler(new THREE.Euler(...value.map(THREE.MathUtils.degToRad), 'YXZ'));
      else if (property === 'translation') node.position.fromArray(value);
      else if (property === 'delta_translation') node.position.copy(originals.get(node).p).add(new THREE.Vector3().fromArray(value));
      else if (property === 'scale') node.scale.fromArray(value);
      else if (property === 'visible') node.visible = Boolean(value);
    }
    timeline.value = time / duration; output.value = `${time.toFixed(2)} s`; dirty();
  }
  function selectClip() {
    restore(); time = 0; playing = false; play.textContent = 'Play';
    const clip = asset?.animations?.find(a => a.name === clips.value);
    duration = clip?.duration || 1;
    tracks = (clip?.tracks || []).map(track => {
      const colon = track.target.lastIndexOf(':');
      return { node: findNode(root, colon < 0 ? track.target : track.target.slice(0, colon)), property: colon < 0 ? 'transform' : track.target.slice(colon + 1), track };
    }).filter(t => t.node);
    apply();
  }
  clips.onchange = selectClip;
  play.onclick = () => { if (time >= duration) time = 0; playing = !playing; play.textContent = playing ? 'Pause' : 'Play'; };
  timeline.oninput = () => { time = Number(timeline.value) * duration; apply(); };
  return {
    bind(nextRoot, nextAsset) {
      root = nextRoot; asset = nextAsset; originals = new Map();
      root.traverse(n => originals.set(n, { p:n.position.clone(), q:n.quaternion.clone(), s:n.scale.clone(), visible:n.visible }));
      clips.replaceChildren();
      for (const clip of asset.animations || []) clips.add(new Option(clip.name.replace(/Animation$/, ''), clip.name));
      bar.hidden = !clips.options.length; selectClip();
    },
    tick(dt) {
      if (!playing || document.hidden) return;
      time += dt * Number(speed.value);
      if (time > duration) { if (loop.checked) time %= duration; else { time = duration; playing = false; play.textContent = 'Play'; } }
      apply();
    },
  };
}
