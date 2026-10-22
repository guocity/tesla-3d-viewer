import { createChargeCamera } from './charging-camera.js';
import { teslaIcon } from './tesla-icons.js';
import { bindChargeGesture } from './charge-gesture.js';
const plug = teslaIcon('charging',24);

export function createChargingControl({ canvas, bridge, getPortPoint, getInstance, getAnimations }) {
  const button = document.createElement('button'); button.type = 'button'; button.className = 'tesla-charge-hotspot';
  button.innerHTML = plug;
  button.setAttribute('aria-label','Open charge port and start charging'); button.setAttribute('aria-pressed','false');
  button.hidden = true;
  const info = document.createElement('div'); info.className = 'tesla-charge-progress'; info.hidden = true;
  info.setAttribute('role','status'); info.innerHTML = `<span class="charging-symbol">${plug}</span><div><strong>Charging</strong><span>Click the plug to disconnect</span></div>`;
  document.body.append(button, info);
  const header=document.querySelector('.vehicle-selector'), toolbar=document.querySelector('.tesla-bottom');
  let connected = false, busy = false, generation = 0, animations, fadeTimer;
  function showInfo(visible) {
    clearTimeout(fadeTimer);
    if (visible) {
      info.hidden=false;
      requestAnimationFrame(() => { if (connected) info.dataset.visible='true'; });
    } else {
      info.dataset.visible='false';
      fadeTimer=setTimeout(() => { if (!connected) info.hidden=true; }, 360);
    }
  }
  const cameraControl=createChargeCamera({canvas,bridge,getInstance,onState:state=>button.dataset.view=state});
  async function toggle() {
    const instance = getInstance(); if (!instance?.loaded || document.getElementById('rive-stage').dataset.ready !== 'true' || busy) return;
    busy = true; button.disabled = true;
    const request = generation;
    try {
      animations = await getAnimations();
      if (request !== generation) return;
      const next = !connected;
      connected = next;
      if(!next){cameraControl.cancel();animations.setCharging(false);}
      button.setAttribute('aria-pressed', String(connected));
      button.setAttribute('aria-label', connected ? 'Disconnect charging and close charge port' : 'Open charge port and start charging');
      document.documentElement.dataset.charging = String(connected);
      showInfo(connected);
      if(next){
        const label=info.querySelector('strong');if(label)label.textContent='Moving to charge port';
        await cameraControl.focus(getPortPoint());
        if(request===generation&&connected)animations.setCharging(true);
      }
    } finally { busy = false; button.disabled = false; }
  }
  const gesture = bindChargeGesture(button, canvas);
  button.onclick = event => { if (gesture.consumeClick(event)) { event.preventDefault(); return; } toggle().catch(error => { info.hidden=false; info.textContent=error.message; }); };
  function position() {
    const instance = getInstance();
    if (instance?.loaded && document.getElementById('rive-stage').dataset.ready === 'true') {
      const vm = instance.viewModelInstance, rect = canvas.getBoundingClientRect();
      if(bridge.camera){button.dataset.cameraEye=JSON.stringify(bridge.camera.eye.toArray());button.dataset.cameraZoom=String(bridge.camera.zoom??bridge.camera.eye.length());}
      const width = instance.artboard.width, height = instance.artboard.height;
      const point=getPortPoint();
      const projected=point&&bridge.camera ? point.clone().applyMatrix4(bridge.camera.mvp) : null;
      const x = projected ? (projected.x*.5+.5)*rect.width+rect.left : vm.number('pin2x').value / width * rect.width + rect.left;
      const y = projected ? (.5-projected.y*.5)*rect.height+rect.top : vm.number('pin2y').value / height * rect.height + rect.top;
      if (!gesture.dragging) {
        button.style.left = `${connected ? innerWidth - 42 : Math.max(30, Math.min(innerWidth - 30, x - 48))}px`;
        const top=(header?.getBoundingClientRect().bottom ?? 76)+24;
        const bottom=(toolbar?.getBoundingClientRect().top ?? innerHeight-82)-24;
        button.style.top = `${connected ? bottom - 18 : Math.max(top, Math.min(bottom, y))}px`;
      }
      button.hidden = false;
      if (animations) {
        const state = animations.getChargingState();
        button.dataset.hasCable = String(state.hasCable);
        button.dataset.portOpen = state.portOpen.toFixed(3);
        button.dataset.connection = state.connection.toFixed(3);
        button.dataset.opacity = state.opacity.toFixed(3);
        const label=info.querySelector('strong');
        if (connected && label && !busy) label.textContent = state.portOpen < .98 ? 'Opening charge port' : state.connection < .98 ? 'Connecting charger' : 'Charging';
      }
    } else button.hidden = true;
    requestAnimationFrame(position);
  }
  requestAnimationFrame(position);
  return {
    reset() { cameraControl.cancel(); gesture.reset(); generation++; clearTimeout(fadeTimer); info.dataset.visible='false'; animations=undefined; connected=false; button.hidden=true; info.hidden=true; button.setAttribute('aria-pressed','false'); button.setAttribute('aria-label','Open charge port and start charging'); document.documentElement.dataset.charging='false'; },
  };
}
