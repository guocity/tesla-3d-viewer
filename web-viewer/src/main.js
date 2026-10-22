import { bindViewerTouch, preventViewerKeyboard } from './viewer-touch.js';
import { createChargingControl } from './charging-control.js';
import { createTeslaChrome } from './tesla-chrome.js';
import { toggleSceneAppearance } from './scene-appearance.js';
import { hideSceneMedia, hideOriginalMenus, disableVehicleHotspots } from './scene-interface.js';
import { createVehicleBridge } from './gpu-vehicle-bridge.js';
import * as rive from '@rive-app/webgl2';
import wasmUrl from '@rive-app/webgl2/rive.wasm?url';
import fallbackWasmUrl from '@rive-app/webgl2/rive_fallback.wasm?url';
import { replaceVehicleBlob } from './scene-buffer.js';
import '../public/reference/hosted.css';
import './vehicle-selector.css';
import './tesla-controls.css';
import { createModelPicker } from './model-picker.js';

rive.RuntimeLoader.setWasmUrl(wasmUrl);
rive.RuntimeLoader.setWasmFallbackUrl(fallbackWasmUrl);
// Fetch/compile WASM in parallel with the scene and selected vehicle.
const runtimeReady = rive.RuntimeLoader.awaitInstance();
runtimeReady.catch(() => {});
const base = new URL(import.meta.env.BASE_URL, location.href);
const assetBase = new URL('data/', base);
const params = new URLSearchParams(location.search);
const panel = document.createElement('div');
panel.className = 'vehicle-selector';
panel.innerHTML = '<select id="vehicle"></select><button id="animation-mode" type="button">APK animations</button><label for="quality">Quality</label><select id="quality"><option value="smooth">Smooth</option><option value="high">High</option></select>';
document.body.append(panel);
const select = panel.querySelector('#vehicle');
const picker = createModelPicker(select);
const mode = panel.querySelector('#animation-mode');
const quality = panel.querySelector('#quality');
const status = document.getElementById('rive-status');
const canvas = document.querySelector('#rive-stage canvas');
canvas.tabIndex = -1;
bindViewerTouch(canvas);
preventViewerKeyboard(document);
let instance, manifest, shellPromise, token = 0;
const bridge = createVehicleBridge(canvas);
let animationController, animationModule, currentParts, currentRig;
const motionPanel = document.createElement('section');
new MutationObserver(() => mode.setAttribute('aria-expanded', String(!motionPanel.hidden))).observe(motionPanel, { attributes: true, attributeFilter: ['hidden'] });
motionPanel.className = 'showroom-motion'; motionPanel.hidden = true; motionPanel.setAttribute('aria-label', 'Showroom animations'); document.body.append(motionPanel);
const packedCache = new Map();
const loader = import(/* @vite-ignore */ new URL('asset-loader.js', base).href);
function progress(text) { status.hidden = false; status.classList.remove('error'); status.querySelector('.message').textContent = text; }
function error(e) { status.classList.add('error'); status.hidden = false; status.querySelector('.message').textContent = e.message; console.error(e); }
function resize() { instance?.resizeDrawingSurfaceToCanvas(quality.value === 'smooth' ? Math.min(devicePixelRatio, 1.25) : Math.min(devicePixelRatio, 2)); }
new ResizeObserver(resize).observe(canvas);
quality.addEventListener('change', resize);
function updateURL() {
  params.set('vehicle', select.value); params.delete('mode');
  history.replaceState(null, '', `${location.pathname}?${params}`);
}
async function ensureAnimations() {
  if (!animationController) {
    animationModule ||= import('./showroom-animation.js');
    const { createShowroomAnimation } = await animationModule;
    animationController = createShowroomAnimation(bridge, motionPanel);
    animationController.bind(currentRig, currentParts);
  }
}
mode.textContent = 'Controls';
mode.setAttribute('aria-expanded', 'false');
mode.addEventListener('click', () => { ensureAnimations().then(() => { motionPanel.hidden = !motionPanel.hidden; mode.setAttribute('aria-expanded', String(!motionPanel.hidden)); }).catch(error); });
select.addEventListener('change', () => { updateURL(); showVehicle().catch(error); });
document.addEventListener('visibilitychange', () => { if (document.hidden) instance?.pause(); else instance?.play('Garage'); });

async function showVehicle() {
  const request = ++token;
  const selected = select.value;
  const vehicle = manifest.vehicles.find(v => v.id === selected);
  charging.reset();
  appearance.disabled = true;
  animationController?.stop();
  motionPanel.hidden = true; mode.setAttribute('aria-expanded', 'false');
  chrome.closePanels();
  canvas.style.visibility = 'hidden';
  delete document.getElementById('rive-stage').dataset.ready;
  progress(`Loading ${vehicle?.name || 'BMW XM'}…`);
  const { readAsset } = await loader;
  shellPromise ||= readAsset(new URL(manifest.scene.file, assetBase).href).catch(e => { shellPromise = null; throw e; });
  const entry = selected === 'bmw' ? manifest.bmw : vehicle?.packed;
  if (!entry) throw new Error('This vehicle is unavailable. Choose another car.');
  let packed = packedCache.get(selected);
  if (!packed) {
    packed = await readAsset(new URL(entry.file, assetBase).href, bytes => {
      if (request === token) progress(`Loading ${vehicle?.name || 'BMW XM'} · ${Math.min(100, Math.round(bytes / entry.bytes * 100))}%`);
    });
    if (packedCache.size >= 2) packedCache.delete(packedCache.keys().next().value);
    packedCache.set(selected, packed);
  }
  const rigPromise = vehicle?.rig ? readAsset(new URL(vehicle.rig.file, assetBase).href).then(b => JSON.parse(new TextDecoder().decode(b))) : Promise.resolve(null);
  const [shell, , rig] = await Promise.all([shellPromise, runtimeReady, rigPromise]);
  if (request !== token) return;
  progress('Starting scene…');
  currentParts = bridge.setVehicle(packed);
  currentRig = rig;
  animationController?.bind(currentRig, currentParts);
  await ensureAnimations();
  if (request !== token) return;
  const buffer = disableVehicleHotspots(hideOriginalMenus(hideSceneMedia(replaceVehicleBlob(shell.slice(0), packed, selected !== 'bmw'))));
  // Reload through the existing renderer so its GPU context stays valid.
  const load = { buffer, artboard: 'Garage', stateMachine: 'Garage', autoplay: true, autoBind: true, enableGPUCanvas: true };
  if (instance) instance.load(load);
  else instance = new rive.Rive({ ...load, canvas, enableMultiTouch: false,
    focusOptions: { allowFocusInterrupt: false },
    layout: new rive.Layout({ fit: 'layout', alignment: 'center' }),
    onLoad: () => {
      const vm = instance.viewModelInstance;
      vm.number('hud').value = 0;
      vm.number('section').value = -1;
      vm.number('playing').value = 0;
      // The original BMW HUD stays closed; Tesla controls are an HTML layer.
      resize();
      let finished = false;
      const loadedToken = token;
      const reveal = () => {
        if (finished || loadedToken !== token) return; finished = true;
        animationController?.refresh();
        if (nightMode) toggleSceneNight();
        appearance.disabled = false;
        canvas.style.visibility = 'visible'; status.hidden = true;
        document.getElementById('rive-stage').dataset.ready = 'true';
        if (document.hidden) instance.pause();
      };
      bridge.waitForSceneFrame(reveal);
      // Some drivers resolve their default framebuffer outside the intercepted
      // draw calls. Never leave the scene hidden waiting for a pixel probe.
      setTimeout(reveal, 6000);
    },
    onLoadError: () => error(new Error('The scene could not be loaded. Select another car to retry.')),
  });
}
async function boot() {
  progress('Loading vehicle catalog…');
  const response = await fetch(new URL('manifest.json', assetBase), { cache: 'no-store' });
  if (!response.ok) throw new Error('Prepared assets are missing. Run pnpm prepare:assets.');
  manifest = await response.json();
  for (const vehicle of manifest.vehicles) select.add(new Option(vehicle.name, vehicle.id));
  const chosen = params.get('vehicle');
  select.value = [...select.options].some(o => o.value === chosen) ? chosen : 'model3_high';
  picker.refresh();
  updateURL();
  await showVehicle();
}
boot().catch(error);

// Use the Garage state machine's authored N shortcut. This changes its sky,
// environment lighting and reflections, without substituting another scene.
let nightMode = false;
const appearance = document.createElement('button');
appearance.disabled = true; appearance.type = 'button'; appearance.className = 'scene-appearance';
appearance.textContent = '☀ Day'; appearance.setAttribute('aria-label', 'Switch to night'); appearance.setAttribute('aria-pressed', 'false');
panel.append(appearance);
function toggleSceneNight() { return toggleSceneAppearance(instance); }
appearance.onclick = () => {
  if (!instance?.loaded) return;
  if (!toggleSceneNight()) return;
  nightMode = !nightMode;
  document.documentElement.dataset.appearance = nightMode ? 'night' : 'day';
  appearance.textContent = nightMode ? '☾ Night' : '☀ Day';
  appearance.setAttribute('aria-label', nightMode ? 'Switch to day' : 'Switch to night');
  appearance.setAttribute('aria-pressed', String(nightMode));
};

const chrome = createTeslaChrome({
  panel, controls: mode, appearance, quality,
  setTemperature(value) {
    const vm = instance?.viewModelInstance;
    if (vm) { vm.string('tempL').value = value.toFixed(1); vm.string('tempR').value = value.toFixed(1); }
  },
  setFan(on) { const vm = instance?.viewModelInstance; if (vm) vm.number('fan').value = on ? 3 : 0; },
  setDefrost(on) { const vm = instance?.viewModelInstance; if (vm) vm.number('defrost').value = Number(on); },
});
panel.querySelector('label[for=quality]')?.remove();

const charging = createChargingControl({
  bridge, getPortPoint: () => animationController?.getChargePortPoint(),
  canvas, getInstance: () => instance,
  getAnimations: async () => { await ensureAnimations(); return animationController; },
});
