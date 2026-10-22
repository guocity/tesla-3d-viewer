const plug = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 2v5m8-5v5M6 7h12v4a6 6 0 0 1-5 5.9V22h-2v-5.1A6 6 0 0 1 6 11V7Z"/></svg>';

export function createChargingControl({ canvas, getInstance, getAnimations }) {
  const button = document.createElement('button'); button.type = 'button'; button.className = 'tesla-charge-hotspot';
  button.innerHTML = `${plug}<span class="charge-tooltip">Start charging</span>`;
  button.setAttribute('aria-label','Open charge port and start charging'); button.setAttribute('aria-pressed','false');
  button.hidden = true;
  const info = document.createElement('div'); info.className = 'tesla-charge-progress'; info.hidden = true;
  info.setAttribute('role','status'); info.innerHTML = `<span class="charging-symbol">${plug}</span><div><strong>Charging</strong><span>Click the plug to disconnect</span></div>`;
  document.body.append(button, info);
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
  async function toggle() {
    const instance = getInstance(); if (!instance?.loaded || document.getElementById('rive-stage').dataset.ready !== 'true' || busy) return;
    busy = true; button.disabled = true;
    const request = generation;
    try {
      animations = await getAnimations();
      if (request !== generation) return;
      const next = !connected;
      animations.setCharging(next);
      connected = next;
      button.setAttribute('aria-pressed', String(connected));
      button.setAttribute('aria-label', connected ? 'Disconnect charging and close charge port' : 'Open charge port and start charging');
      button.querySelector('.charge-tooltip').textContent = connected ? 'Disconnect & close' : 'Start charging';
      document.documentElement.dataset.charging = String(connected);
      showInfo(connected);
    } finally { busy = false; button.disabled = false; }
  }
  button.onclick = () => { toggle().catch(error => { info.hidden=false; info.textContent=error.message; }); };
  function position() {
    const instance = getInstance();
    if (instance?.loaded && document.getElementById('rive-stage').dataset.ready === 'true') {
      const vm = instance.viewModelInstance, rect = canvas.getBoundingClientRect();
      const width = instance.artboard.width, height = instance.artboard.height;
      const x = vm.number('pin2x').value / width * rect.width + rect.left;
      const y = vm.number('pin2y').value / height * rect.height + rect.top;
      button.style.left = `${Math.max(30, Math.min(innerWidth - 30, x))}px`;
      button.style.top = `${Math.max(100, Math.min(innerHeight - 110, y))}px`;
      button.hidden = false;
      if (animations) {
        const state = animations.getChargingState();
        button.dataset.portOpen = state.portOpen.toFixed(3);
        button.dataset.connection = state.connection.toFixed(3);
        button.dataset.opacity = state.opacity.toFixed(3);
        const label=info.querySelector('strong');
        if (connected && label) label.textContent = state.portOpen < .98 ? 'Opening charge port' : state.connection < .98 ? 'Connecting charger' : 'Charging';
      }
    } else button.hidden = true;
    requestAnimationFrame(position);
  }
  requestAnimationFrame(position);
  return {
    reset() { generation++; clearTimeout(fadeTimer); info.dataset.visible='false'; animations=undefined; connected=false; button.hidden=true; info.hidden=true; button.setAttribute('aria-pressed','false'); button.setAttribute('aria-label','Open charge port and start charging'); button.querySelector('.charge-tooltip').textContent='Start charging'; document.documentElement.dataset.charging='false'; },
  };
}
