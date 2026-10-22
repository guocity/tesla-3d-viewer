import { createVehicleBridge } from './gpu-vehicle-bridge.js';
import * as rive from '@rive-app/webgl2';
import wasmUrl from '@rive-app/webgl2/rive.wasm?url';
import fallbackWasmUrl from '@rive-app/webgl2/rive_fallback.wasm?url';
import { replaceVehicleBlob } from './scene-buffer.js';
import '../public/reference/hosted.css';
import './vehicle-selector.css';
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
panel.innerHTML = '<select id="vehicle"><option value="bmw">BMW XM · Original</option></select><button id="animation-mode" type="button">APK animations</button><label for="quality">Quality</label><select id="quality"><option value="smooth">Smooth</option><option value="high">High</option></select>';
document.body.append(panel);
const select = panel.querySelector('#vehicle');
const picker = createModelPicker(select);
const mode = panel.querySelector('#animation-mode');
const quality = panel.querySelector('#quality');
const status = document.getElementById('rive-status');
const canvas = document.querySelector('#rive-stage canvas');
let instance, manifest, shellPromise, token = 0;
const bridge = createVehicleBridge(canvas);
let animationController, animationModule, currentParts, currentRig;
const motionPanel = document.createElement('section');
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
mode.textContent = 'Animate vehicle';
mode.addEventListener('click', () => { ensureAnimations().then(() => { motionPanel.hidden = !motionPanel.hidden; }).catch(error); });
select.addEventListener('change', () => { updateURL(); showVehicle().catch(error); });
document.addEventListener('visibilitychange', () => { if (document.hidden) instance?.pause(); else instance?.play('Garage'); });

async function showVehicle() {
  const request = ++token;
  const selected = select.value;
  const vehicle = manifest.vehicles.find(v => v.id === selected);
  animationController?.stop();
  canvas.style.visibility = 'hidden';
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
  const buffer = replaceVehicleBlob(shell.slice(0), packed, selected !== 'bmw');
  // Reload through the existing renderer so its GPU context stays valid.
  const load = { buffer, artboard: 'Garage', stateMachine: 'Garage', autoplay: true, autoBind: true, enableGPUCanvas: true };
  if (instance) instance.load(load);
  else instance = new rive.Rive({ ...load, canvas, enableMultiTouch: true,
    layout: new rive.Layout({ fit: 'layout', alignment: 'center' }),
    onLoad: () => {
      resize();
      let finished = false;
      const loadedToken = token;
      const reveal = () => {
        if (finished || loadedToken !== token) return; finished = true;
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
  const response = await fetch(new URL('manifest.json', assetBase));
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
