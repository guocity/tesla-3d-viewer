import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

// ============================================================================
// TESLA OEM PAINT PALETTE & STUDIO PRESETS
// ============================================================================
const PAINT_PALETTE = [
  { name: 'Ultra Red', hex: '#b9101c', metalness: 0.78, roughness: 0.12, clearcoat: 1.0 },
  { name: 'Quicksilver', hex: '#8b929a', metalness: 0.90, roughness: 0.14, clearcoat: 1.0 },
  { name: 'Stainless Steel', hex: '#b6babd', metalness: 0.94, roughness: 0.24, clearcoat: 0.18 },
  { name: 'Stealth Grey', hex: '#33373d', metalness: 0.76, roughness: 0.15, clearcoat: 1.0 },
  { name: 'Pearl White', hex: '#eef1f5', metalness: 0.45, roughness: 0.12, clearcoat: 1.0 },
  { name: 'Deep Blue Metallic', hex: '#122c5c', metalness: 0.80, roughness: 0.13, clearcoat: 1.0 },
  { name: 'Solid Black', hex: '#0d0e11', metalness: 0.65, roughness: 0.08, clearcoat: 1.0 },
  { name: 'Lunar Silver', hex: '#a4abb3', metalness: 0.88, roughness: 0.13, clearcoat: 1.0 },
  { name: 'Midnight Cherry', hex: '#480a16', metalness: 0.82, roughness: 0.11, clearcoat: 1.0 },
  { name: 'Cyber Matte Black', hex: '#16181c', metalness: 0.55, roughness: 0.44, clearcoat: 0.10 },
  { name: 'Glacier Blue', hex: '#4e779c', metalness: 0.75, roughness: 0.14, clearcoat: 1.0 },
  { name: 'Founders Gold', hex: '#b89758', metalness: 0.88, roughness: 0.16, clearcoat: 1.0 },
];

const INTERIOR_THEMES = {
  black: { primary: '#17191e', secondary: '#22252c', roughness: 0.62 },
  white: { primary: '#eaedf2', secondary: '#23262e', roughness: 0.50 },
  cream: { primary: '#d8ccb8', secondary: '#2a2623', roughness: 0.54 },
};

const ENV_PRESETS = {
  showroom: {
    label: 'Showroom Dark',
    bgTop: '#07090e',
    bgHorizon: '#121722',
    bgBottom: '#040507',
    softboxColor: '#ffffff',
    softboxIntensity: 9.0,
    rimColor: '#6ea8ff',
    rimIntensity: 5.5,
    warmColor: '#ff9b6a',
    warmIntensity: 3.0,
    floorColor: '#090b10',
  },
  sunset: {
    label: 'Golden Hour',
    bgTop: '#161224',
    bgHorizon: '#59292c',
    bgBottom: '#08060a',
    softboxColor: '#ffd4a6',
    softboxIntensity: 8.5,
    rimColor: '#ff6a3d',
    rimIntensity: 9.5,
    warmColor: '#4c7fff',
    warmIntensity: 3.5,
    floorColor: '#0e0a0d',
  },
  cyber: {
    label: 'Cyber Neon',
    bgTop: '#050812',
    bgHorizon: '#0e1b30',
    bgBottom: '#030408',
    softboxColor: '#d8ecff',
    softboxIntensity: 8.0,
    rimColor: '#00e5ff',
    rimIntensity: 10.0,
    warmColor: '#ff1e56',
    warmIntensity: 7.5,
    floorColor: '#060911',
  },
  studio: {
    label: 'White Studio',
    bgTop: '#cfd6e0',
    bgHorizon: '#e5eaf0',
    bgBottom: '#8d96a5',
    softboxColor: '#ffffff',
    softboxIntensity: 11.0,
    rimColor: '#ffffff',
    rimIntensity: 6.5,
    warmColor: '#e6f0ff',
    warmIntensity: 5.0,
    floorColor: '#1a1f29',
  },
  alpine: {
    label: 'Alpine Day',
    bgTop: '#182b49',
    bgHorizon: '#6382a8',
    bgBottom: '#0d131c',
    softboxColor: '#f2f7ff',
    softboxIntensity: 10.0,
    rimColor: '#99c7ff',
    rimIntensity: 7.0,
    warmColor: '#ffd6a1',
    warmIntensity: 4.5,
    floorColor: '#0c1017',
  },
};

function getColorLuminance(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

// ============================================================================
// APPLICATION STATE
// ============================================================================
const state = {
  catalog: { vehicles: [], wheels: [], energy_and_accessories: [] },
  activeTab: 'vehicles',
  searchQuery: '',
  currentAsset: null,
  currentModelRoot: null,

  // Render mode: 'realtime' | 'pathtrace'
  renderMode: 'realtime',
  pathTracerReady: false,
  pathTracerFallbackMode: false,
  ptSamples: 0,
  ptMaxSamples: 512,
  ptDirty: true,
  isInteracting: false,

  // Paint & Material Customization
  paint: { ...PAINT_PALETTE[2] },
  interior: 'black',
  caliperColor: '#d41418',
  windowTint: 0.55,
  emissiveStrength: 2.4,

  // Environment & Studio
  envPreset: 'showroom',
  exposure: 1.15,
  envRotationDeg: 35,
  floorReflectivity: 0.45,
  ptBounces: 5,
  ptAperture: 0.008,

  // Interactive Articulation & Closures
  doorTargets: {
    frunk: 0,
    trunk: 0,
    door_lf: 0,
    door_rf: 0,
    door_lr: 0,
    door_rr: 0,
    windows: 0,
    mirrors: 0,
    chargeport: 0,
    tonneau: 0,
  },
  doorCurrent: {
    frunk: 0,
    trunk: 0,
    door_lf: 0,
    door_rf: 0,
    door_lr: 0,
    door_rr: 0,
    windows: 0,
    mirrors: 0,
    chargeport: 0,
    tonneau: 0,
  },
  resolvedTracks: {},
  explodeAmount: 0,

  // Toggles
  turntable: false,
  spinWheels: false,
  wireframe: false,

  // Categorized scene references for fast updates
  materialBuckets: {
    paint: [],
    glass_tinted: [],
    glass_clear: [],
    caliper: [],
    interior: [],
    emissive: [],
    all: [],
  },
  wheelPivotNodes: [],
  factoryWheelClones: new Map(),
  explodeNodes: [],

  // Smooth camera transition
  cameraAnim: null,
  modelBounds: {
    size: new THREE.Vector3(4.5, 1.6, 2.0),
    center: new THREE.Vector3(0, 0.75, 0),
    radius: 2.6,
  },
};

// In-memory cache of loaded GLTF scenes for instant switching
const gltfCache = new Map();

// ============================================================================
// CORE THREE.JS OBJECTS
// ============================================================================
const canvas = document.getElementById('webgl-canvas');
const viewportEl = document.getElementById('viewport-container');

const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  powerPreference: 'high-performance',
  preserveDrawingBuffer: true,
});
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = state.exposure;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(36, 1, 0.05, 250);
camera.position.set(4.6, 1.85, 4.2);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.06;
controls.maxPolarAngle = Math.PI * 0.492;
controls.minDistance = 0.45;
controls.maxDistance = 35;
controls.target.set(0, 0.68, 0);

// Post-processing for Real-Time PBR mode
const composer = new EffectComposer(renderer);
const renderPass = new RenderPass(scene, camera);
composer.addPass(renderPass);

const bloomPass = new UnrealBloomPass(new THREE.Vector2(512, 512), 0.28, 0.55, 0.88);
composer.addPass(bloomPass);

const outputPass = new OutputPass();
composer.addPass(outputPass);

// Lazy-loaded GPU Path Tracer instance (initialized only when GPU Path Tracing is clicked)
let pathTracer = null;
let pathTracerInitPromise = null;

async function ensurePathTracerInitialized() {
  if (pathTracer || state.pathTracerFallbackMode) return pathTracer;
  if (pathTracerInitPromise) return pathTracerInitPromise;

  pathTracerInitPromise = (async () => {
    try {
      const mod = await import('three-gpu-pathtracer');
      const WebGLPathTracer = mod.WebGLPathTracer;
      pathTracer = new WebGLPathTracer(renderer);
      pathTracer.bounces = state.ptBounces;
      pathTracer.transmissiveBounces = 4;
      pathTracer.filterGlossyFactor = 0.35;
      pathTracer.multipleImportanceSampling = true;
      pathTracer.renderScale = Math.min(window.devicePixelRatio, 1.15);
      pathTracer.tiles.set(2, 2);
      pathTracer.synchronizeRenderSize = true;
      return pathTracer;
    } catch (err) {
      console.warn('WebGLPathTracer fallback to progressive accumulation:', err);
      state.pathTracerFallbackMode = true;
      return null;
    }
  })();

  return pathTracerInitPromise;
}

const pmremGenerator = new THREE.PMREMGenerator(renderer);
pmremGenerator.compileEquirectangularShader();

const gltfLoader = new GLTFLoader();
const modelGroup = new THREE.Group();
modelGroup.name = 'LoadedAssetRoot';
scene.add(modelGroup);

// ============================================================================
// STUDIO LIGHTING, FLOOR PEDESTAL & CONTACT SHADOWS
// ============================================================================
const studioGroup = new THREE.Group();
studioGroup.name = 'StudioEnvironment';
scene.add(studioGroup);

const keyLight = new THREE.DirectionalLight(0xffffff, 2.6);
keyLight.position.set(5, 9, 6);
keyLight.castShadow = true;
keyLight.shadow.mapSize.set(2048, 2048);
keyLight.shadow.camera.near = 0.5;
keyLight.shadow.camera.far = 28;
const d = 4.8;
keyLight.shadow.camera.left = -d;
keyLight.shadow.camera.right = d;
keyLight.shadow.camera.top = d;
keyLight.shadow.camera.bottom = -d;
keyLight.shadow.bias = -0.0003;
keyLight.shadow.normalBias = 0.015;
studioGroup.add(keyLight);

const fillLight = new THREE.DirectionalLight(0x88b4ff, 1.15);
fillLight.position.set(-6, 4, -5);
studioGroup.add(fillLight);

const rimLight = new THREE.DirectionalLight(0xffcfa8, 1.35);
rimLight.position.set(-5, 6, 5);
studioGroup.add(rimLight);

function createStudioFloorTexture() {
  const size = 512;
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d');

  const grad = ctx.createRadialGradient(size / 2, size / 2, 8, size / 2, size / 2, size * 0.48);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.55, 'rgba(200,210,225,0.65)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);

  ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
  ctx.lineWidth = 1.2;
  [0.18, 0.28, 0.38].forEach((r) => {
    ctx.beginPath();
    ctx.arc(size / 2, size / 2, size * r, 0, Math.PI * 2);
    ctx.stroke();
  });

  const tex = new THREE.CanvasTexture(c);
  tex.needsUpdate = true;
  return tex;
}

function createContactShadowTexture() {
  const w = 256;
  const h = 256;
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d');

  ctx.clearRect(0, 0, w, h);
  ctx.save();
  ctx.translate(w / 2, h / 2);
  ctx.scale(1.0, 0.56);
  const grad = ctx.createRadialGradient(0, 0, w * 0.08, 0, 0, w * 0.46);
  grad.addColorStop(0, 'rgba(0, 0, 0, 0.92)');
  grad.addColorStop(0.55, 'rgba(0, 0, 0, 0.68)');
  grad.addColorStop(0.82, 'rgba(0, 0, 0, 0.18)');
  grad.addColorStop(1, 'rgba(0, 0, 0, 0.0)');
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.arc(0, 0, w * 0.48, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  const tex = new THREE.CanvasTexture(c);
  tex.needsUpdate = true;
  return tex;
}

const floorGeo = new THREE.CircleGeometry(22, 72);
const floorAlphaTex = createStudioFloorTexture();
const floorMat = new THREE.MeshPhysicalMaterial({
  color: new THREE.Color('#090b10'),
  metalness: 0.25,
  roughness: 0.22,
  clearcoat: state.floorReflectivity,
  clearcoatRoughness: 0.14,
  alphaMap: floorAlphaTex,
  transparent: true,
  opacity: 0.96,
});
const floorMesh = new THREE.Mesh(floorGeo, floorMat);
floorMesh.rotation.x = -Math.PI / 2;
floorMesh.position.y = -0.004;
floorMesh.receiveShadow = true;
floorMesh.name = 'Studio_Pedestal_Floor';
studioGroup.add(floorMesh);

const contactShadowGeo = new THREE.PlaneGeometry(1, 1);
const contactShadowMat = new THREE.MeshBasicMaterial({
  map: createContactShadowTexture(),
  transparent: true,
  opacity: 0.85,
  depthWrite: false,
});
const contactShadowMesh = new THREE.Mesh(contactShadowGeo, contactShadowMat);
contactShadowMesh.rotation.x = -Math.PI / 2;
contactShadowMesh.position.y = 0.001;
contactShadowMesh.name = 'Contact_Shadow';
studioGroup.add(contactShadowMesh);

// ============================================================================
// PROCEDURAL AUTOMOTIVE HDRI ENVIRONMENT GENERATOR
// ============================================================================
let currentEnvRenderTarget = null;

function buildStudioEnvironment(presetKey, rotationDeg = 35) {
  const preset = ENV_PRESETS[presetKey] || ENV_PRESETS.showroom;
  const envScene = new THREE.Scene();

  const skyGeo = new THREE.SphereGeometry(60, 48, 24);
  const posAttr = skyGeo.attributes.position;
  const colors = new Float32Array(posAttr.count * 3);
  const cTop = new THREE.Color(preset.bgTop);
  const cHorizon = new THREE.Color(preset.bgHorizon);
  const cBottom = new THREE.Color(preset.bgBottom);
  const tmpColor = new THREE.Color();

  for (let i = 0; i < posAttr.count; i++) {
    const y = posAttr.getY(i) / 60;
    if (y >= 0) {
      tmpColor.lerpColors(cHorizon, cTop, Math.pow(y, 0.55));
    } else {
      tmpColor.lerpColors(cHorizon, cBottom, Math.min(1, Math.pow(-y, 0.45) * 1.4));
    }
    colors[i * 3] = tmpColor.r;
    colors[i * 3 + 1] = tmpColor.g;
    colors[i * 3 + 2] = tmpColor.b;
  }
  skyGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  const skyMat = new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide });
  envScene.add(new THREE.Mesh(skyGeo, skyMat));

  const rig = new THREE.Group();
  rig.rotation.y = THREE.MathUtils.degToRad(rotationDeg);
  envScene.add(rig);

  const mainStrip = new THREE.Mesh(
    new THREE.PlaneGeometry(28, 7),
    new THREE.MeshBasicMaterial({
      color: new THREE.Color(preset.softboxColor).multiplyScalar(preset.softboxIntensity),
      side: THREE.DoubleSide,
    })
  );
  mainStrip.position.set(0, 22, 0);
  mainStrip.rotation.x = Math.PI / 2;
  rig.add(mainStrip);

  [-7.5, 7.5].forEach((zOffset) => {
    const rib = new THREE.Mesh(
      new THREE.PlaneGeometry(26, 2.2),
      new THREE.MeshBasicMaterial({
        color: new THREE.Color(preset.softboxColor).multiplyScalar(preset.softboxIntensity * 0.65),
        side: THREE.DoubleSide,
      })
    );
    rib.position.set(0, 18, zOffset);
    rib.lookAt(0, 0, 0);
    rig.add(rib);
  });

  const sidePanelA = new THREE.Mesh(
    new THREE.PlaneGeometry(22, 6),
    new THREE.MeshBasicMaterial({
      color: new THREE.Color(preset.rimColor).multiplyScalar(preset.rimIntensity),
      side: THREE.DoubleSide,
    })
  );
  sidePanelA.position.set(16, 6, 18);
  sidePanelA.lookAt(0, 1, 0);
  rig.add(sidePanelA);

  const sidePanelB = new THREE.Mesh(
    new THREE.PlaneGeometry(20, 5),
    new THREE.MeshBasicMaterial({
      color: new THREE.Color(preset.warmColor).multiplyScalar(preset.warmIntensity),
      side: THREE.DoubleSide,
    })
  );
  sidePanelB.position.set(-18, 5, -15);
  sidePanelB.lookAt(0, 1, 0);
  rig.add(sidePanelB);

  const horizonStrip = new THREE.Mesh(
    new THREE.CylinderGeometry(36, 36, 1.4, 48, 1, true, 0, Math.PI * 0.85),
    new THREE.MeshBasicMaterial({
      color: new THREE.Color(preset.rimColor).multiplyScalar(preset.rimIntensity * 0.45),
      side: THREE.BackSide,
    })
  );
  horizonStrip.position.y = 2.2;
  rig.add(horizonStrip);

  if (currentEnvRenderTarget) {
    currentEnvRenderTarget.dispose();
  }
  currentEnvRenderTarget = pmremGenerator.fromScene(envScene, 0.025);
  scene.environment = currentEnvRenderTarget.texture;
  scene.background = new THREE.Color(preset.bgBottom).lerp(new THREE.Color(preset.bgHorizon), 0.35);

  if (scene.environmentRotation) {
    scene.environmentRotation.set(0, THREE.MathUtils.degToRad(rotationDeg), 0);
  }

  floorMat.color.set(preset.floorColor);
  markPathTracerSceneDirty();
}

// ============================================================================
// PBR MATERIAL UPGRADE SYSTEM (GODOT 3.2 -> AUTOMOTIVE PHYSICAL PBR)
// ============================================================================
function createBrushedDetailTexture() {
  const size = 128;
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#808080';
  ctx.fillRect(0, 0, size, size);
  for (let i = 0; i < 400; i++) {
    const y = Math.random() * size;
    const v = 115 + Math.floor(Math.random() * 26);
    ctx.strokeStyle = `rgb(${v},${v},${v})`;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(size, y);
    ctx.stroke();
  }
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(12, 12);
  return tex;
}

const brushedTex = createBrushedDetailTexture();

function classifyMeshAndMaterial(mesh, oldMat) {
  const matName = (oldMat?.name || '').toLowerCase();
  const meshName = (mesh?.name || '').toLowerCase();
  const parentName = (mesh?.parent?.name || '').toLowerCase();

  if (matName.includes('__')) {
    const prefix = matName.split('__')[0];
    if (prefix) return prefix;
  }
  if (oldMat?.userData?.category) {
    return oldMat.userData.category;
  }

  const combined = `${matName} ${meshName} ${parentName}`;
  if (combined.includes('caliper')) return 'caliper';
  if (combined.includes('rotor') || combined.includes('brake_disc')) return 'rotor';
  if (combined.includes('taillight') || combined.includes('brake_light')) return 'taillight';
  if (combined.includes('headlight') || combined.includes('drl') || combined.includes('lightbar')) return 'headlight';
  if (combined.includes('mirror') && !combined.includes('housing') && !combined.includes('spatial')) return 'mirror';
  if (combined.includes('window') || combined.includes('windshield') || combined.includes('glass')) return 'glass_tinted';
  if (combined.includes('tire') || combined.includes('sidewall') || combined.includes('tread')) return 'tire';
  if (combined.includes('carpaint') || combined.includes('steel_exterior') || combined.includes('body')) return 'paint';
  return 'trim';
}

function upgradeModelMaterials(root) {
  state.materialBuckets = {
    paint: [],
    glass_tinted: [],
    glass_clear: [],
    caliper: [],
    interior: [],
    emissive: [],
    all: [],
  };

  const materialCache = new Map();

  root.traverse((node) => {
    if (!node.isMesh) return;

    node.castShadow = true;
    node.receiveShadow = true;

    if (node.geometry && !node.geometry.attributes.normal) {
      node.geometry.computeVertexNormals();
    }

    const oldMat = Array.isArray(node.material) ? node.material[0] : node.material;
    const category = classifyMeshAndMaterial(node, oldMat);
    const cacheKey = `${category}::${oldMat ? oldMat.name : node.name}`;

    if (materialCache.has(cacheKey)) {
      node.material = materialCache.get(cacheKey);
      return;
    }

    const baseColor = oldMat?.color ? oldMat.color.clone() : new THREE.Color(0.5, 0.5, 0.5);
    const lum = getColorLuminance(baseColor);
    let newMat;

    switch (category) {
      case 'paint': {
        const isStainless = state.paint.name === 'Stainless Steel';
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'paint_material',
          color: new THREE.Color(state.paint.hex),
          metalness: state.paint.metalness,
          roughness: state.paint.roughness,
          clearcoat: state.paint.clearcoat,
          clearcoatRoughness: isStainless ? 0.22 : 0.04,
          roughnessMap: isStainless ? brushedTex : null,
          anisotropy: isStainless ? 0.55 : 0.0,
          sheen: 0.15,
          sheenRoughness: 0.25,
          sheenColor: new THREE.Color(state.paint.hex).lerp(new THREE.Color(0xffffff), 0.35),
          envMapIntensity: 1.35,
          side: THREE.DoubleSide,
        });
        state.materialBuckets.paint.push(newMat);
        break;
      }

      case 'glass':
      case 'glass_tinted': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'glass_tinted',
          color: new THREE.Color('#0c1218'),
          metalness: 0.05,
          roughness: 0.03,
          transmission: 1.0 - state.windowTint * 0.72,
          transparent: true,
          opacity: Math.max(0.32, state.windowTint),
          ior: 1.52,
          reflectivity: 0.9,
          clearcoat: 1.0,
          clearcoatRoughness: 0.02,
          envMapIntensity: 1.6,
          side: THREE.DoubleSide,
        });
        state.materialBuckets.glass_tinted.push(newMat);
        break;
      }

      case 'glass_clear': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'glass_clear',
          color: new THREE.Color('#eef6ff'),
          metalness: 0.0,
          roughness: 0.02,
          transmission: 0.88,
          transparent: true,
          opacity: 0.42,
          ior: 1.5,
          clearcoat: 1.0,
          clearcoatRoughness: 0.02,
          envMapIntensity: 1.5,
          side: THREE.DoubleSide,
        });
        state.materialBuckets.glass_clear.push(newMat);
        break;
      }

      case 'mirror': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'mirror_chrome',
          color: new THREE.Color('#f8fafc'),
          metalness: 1.0,
          roughness: 0.01,
          clearcoat: 1.0,
          envMapIntensity: 1.8,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'caliper': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'brake_caliper',
          color: new THREE.Color(state.caliperColor),
          metalness: 0.65,
          roughness: 0.18,
          clearcoat: 1.0,
          clearcoatRoughness: 0.05,
          envMapIntensity: 1.3,
          side: THREE.DoubleSide,
        });
        state.materialBuckets.caliper.push(newMat);
        break;
      }

      case 'rotor': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'brake_rotor',
          color: new THREE.Color('#9ca3af'),
          metalness: 0.92,
          roughness: 0.26,
          roughnessMap: brushedTex,
          anisotropy: 0.7,
          clearcoat: 0.15,
          envMapIntensity: 1.25,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'taillight': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'taillight_led',
          color: new THREE.Color('#4a0408'),
          emissive: new THREE.Color('#ff1420'),
          emissiveIntensity: state.emissiveStrength,
          roughness: 0.12,
          metalness: 0.1,
          clearcoat: 1.0,
          side: THREE.DoubleSide,
        });
        newMat.userData.baseEmissiveScale = 1.0;
        state.materialBuckets.emissive.push(newMat);
        break;
      }

      case 'turn_signal': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'turn_signal_led',
          color: new THREE.Color('#451a03'),
          emissive: new THREE.Color('#ff8c00'),
          emissiveIntensity: state.emissiveStrength * 0.85,
          roughness: 0.15,
          metalness: 0.1,
          clearcoat: 1.0,
          side: THREE.DoubleSide,
        });
        newMat.userData.baseEmissiveScale = 0.85;
        state.materialBuckets.emissive.push(newMat);
        break;
      }

      case 'headlight': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'headlight_led',
          color: new THREE.Color('#ffffff'),
          emissive: new THREE.Color('#e8f2ff'),
          emissiveIntensity: state.emissiveStrength * 1.15,
          roughness: 0.08,
          metalness: 0.1,
          clearcoat: 1.0,
          side: THREE.DoubleSide,
        });
        newMat.userData.baseEmissiveScale = 1.15;
        state.materialBuckets.emissive.push(newMat);
        break;
      }

      case 'tire': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'tire_rubber',
          color: new THREE.Color('#141619'),
          metalness: 0.06,
          roughness: 0.80,
          clearcoat: 0.06,
          clearcoatRoughness: 0.55,
          envMapIntensity: 0.65,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'chrome': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'chrome_accent',
          color: new THREE.Color('#e2e8f0'),
          metalness: 0.96,
          roughness: 0.08,
          clearcoat: 0.8,
          envMapIntensity: 1.5,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'wheel_rim': {
        const rimColor = lum > 0.35 ? baseColor : new THREE.Color('#2c3038');
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'wheel_alloy',
          color: rimColor,
          metalness: 0.86,
          roughness: 0.22,
          clearcoat: 0.75,
          clearcoatRoughness: 0.12,
          envMapIntensity: 1.35,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'interior':
      case 'interior_white': {
        const theme = INTERIOR_THEMES[state.interior] || INTERIOR_THEMES.black;
        const lowerName = (oldMat?.name || '').toLowerCase();
        const isPrimarySeat = category === 'interior_white' || lowerName.includes('seat') || lowerName.includes('white');
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'interior_cabin',
          color: new THREE.Color(isPrimarySeat ? theme.primary : theme.secondary),
          metalness: 0.08,
          roughness: theme.roughness,
          sheen: 0.25,
          sheenRoughness: 0.6,
          clearcoat: 0.05,
          side: THREE.DoubleSide,
        });
        newMat.userData.isPrimarySeat = isPrimarySeat;
        state.materialBuckets.interior.push(newMat);
        break;
      }

      case 'wood': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'open_pore_wood',
          color: new THREE.Color('#5c402c'),
          metalness: 0.04,
          roughness: 0.52,
          clearcoat: 0.15,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'carbon': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'carbon_fiber',
          color: new THREE.Color('#1c1e24'),
          metalness: 0.45,
          roughness: 0.22,
          clearcoat: 1.0,
          clearcoatRoughness: 0.05,
          roughnessMap: brushedTex,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'screen': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'infotainment_display',
          color: new THREE.Color('#090d16'),
          emissive: new THREE.Color('#111d35'),
          emissiveIntensity: 0.65,
          metalness: 0.1,
          roughness: 0.06,
          clearcoat: 1.0,
          side: THREE.DoubleSide,
        });
        break;
      }

      case 'solar': {
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'solar_cell',
          color: new THREE.Color('#0f1b2e'),
          metalness: 0.72,
          roughness: 0.14,
          clearcoat: 0.9,
          side: THREE.DoubleSide,
        });
        break;
      }

      default: {
        const isEnergyWhite = lum > 0.65;
        newMat = new THREE.MeshPhysicalMaterial({
          name: oldMat?.name || 'trim_surface',
          color: isEnergyWhite ? new THREE.Color('#e9edf2') : baseColor,
          metalness: oldMat?.metalness ?? (isEnergyWhite ? 0.35 : 0.25),
          roughness: oldMat?.roughness ?? (isEnergyWhite ? 0.16 : 0.48),
          clearcoat: isEnergyWhite ? 0.85 : 0.18,
          clearcoatRoughness: 0.18,
          envMapIntensity: 1.1,
          side: THREE.DoubleSide,
        });
        break;
      }
    }

    newMat.wireframe = state.wireframe;
    newMat.userData.category = category;
    materialCache.set(cacheKey, newMat);
    state.materialBuckets.all.push(newMat);
    node.material = newMat;
  });
}

// ============================================================================
// INTERACTIVE CLOSURES, DOORS & ARTICULATION ENGINE
// ============================================================================
function findNodeByPathOrName(root, targetPath) {
  const cleanPath = targetPath.replace(/^\.\//, '');
  if (cleanPath === '.' || cleanPath === '') return root;

  const segments = cleanPath.split('/');
  const leafName = segments[segments.length - 1];

  let found = null;
  root.traverse((obj) => {
    if (found) return;
    if (obj.name === leafName) {
      found = obj;
    }
  });
  return found;
}

function buildArticulationTracks(root, asset) {
  const map = {
    frunk: [],
    trunk: [],
    door_lf: [],
    door_rf: [],
    door_lr: [],
    door_rr: [],
    windows: [],
    mirrors: [],
    chargeport: [],
    tonneau: [],
  };

  const animNameMap = {
    Hood: 'frunk',
    Trunk: 'trunk',
    LFDoor: 'door_lf',
    RFDoor: 'door_rf',
    LRDoor: 'door_lr',
    LRDoorComplete: 'door_lr',
    RRDoor: 'door_rr',
    RRDoorComplete: 'door_rr',
    LFWindow: 'windows',
    RFWindow: 'windows',
    LRWindow: 'windows',
    RRWindow: 'windows',
    LFDoorMirror: 'mirrors',
    RFDoorMirror: 'mirrors',
    Chargeport: 'chargeport',
  };

  const rawAnims = asset.animations || [];
  for (const anim of rawAnims) {
    const partKey = animNameMap[anim.name];
    if (!partKey) continue;

    for (const tr of anim.tracks || []) {
      const [nodePath, prop] = tr.target.split(':');
      const node = findNodeByPathOrName(root, nodePath);
      if (!node) continue;

      if (!node.userData.origPos) {
        node.userData.origPos = node.position.clone();
        node.userData.origQuat = node.quaternion.clone();
        node.userData.origScale = node.scale.clone();
      }

      map[partKey].push({
        node,
        prop,
        start: tr.start,
        end: tr.end,
      });
    }
  }

  const fallbackDefs = [
    { part: 'frunk', names: ['Hood_Spatial', 'Hood_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, 0, 68] },
    { part: 'trunk', names: ['Trunk_Spatial', 'Trunk_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, 0, -68] },
    { part: 'door_lf', names: ['Door_LF_Spatial', 'Door_LF_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, -65, 0] },
    { part: 'door_rf', names: ['Door_RF_Spatial', 'Door_RF_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, 65, 0] },
    { part: 'door_lr', names: ['Door_LR_Spatial', 'Door_LR_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, -65, 0] },
    { part: 'door_rr', names: ['Door_RR_Spatial', 'Door_RR_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, 65, 0] },
    { part: 'chargeport', names: ['Charge_Cap_Spatial', 'Charge_Port_Spatial', 'ChargeCap_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [82, 0, 0] },
    { part: 'windows', names: ['Window_LF_Spatial', 'Window_RF_Spatial', 'Window_LR_Spatial', 'Window_RR_Spatial', 'Window_FL', 'Window_FR', 'Window_RL', 'Window_RR'], prop: 'delta_translation', start: [0, 0, 0], end: [0, -0.34, 0] },
    { part: 'mirrors', names: ['Door_LF_Mirror_Spatial', 'Door_LF_Mirror_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, 42, 0] },
    { part: 'mirrors', names: ['Door_RF_Mirror_Spatial', 'Door_RF_Mirror_Locator'], prop: 'rotation_degrees', start: [0, 0, 0], end: [0, -42, 0] },
    { part: 'tonneau', names: ['Tonneau_Cover'], prop: 'delta_translation', start: [0, 0, 0], end: [1.35, 0.14, 0] },
  ];

  for (const fb of fallbackDefs) {
    if (map[fb.part].length > 0) continue;
    for (const candidateName of fb.names) {
      const node = findNodeByPathOrName(root, candidateName);
      if (node) {
        if (!node.userData.origPos) {
          node.userData.origPos = node.position.clone();
          node.userData.origQuat = node.quaternion.clone();
          node.userData.origScale = node.scale.clone();
        }
        map[fb.part].push({
          node,
          prop: fb.prop,
          start: fb.start,
          end: fb.end,
        });
      }
    }
  }

  state.resolvedTracks = map;

  document.querySelectorAll('#door-buttons .door-btn').forEach((btn) => {
    const part = btn.dataset.part;
    const hasPart = map[part] && map[part].length > 0;
    btn.disabled = !hasPart;
    btn.style.opacity = hasPart ? '1' : '0.35';
    btn.classList.remove('active');
  });
}

function applyArticulationStep(dt) {
  let anyChanged = false;
  const speed = 4.2;

  for (const part of Object.keys(state.doorTargets)) {
    const target = state.doorTargets[part];
    const current = state.doorCurrent[part];
    if (Math.abs(target - current) > 0.0005) {
      const next = THREE.MathUtils.lerp(current, target, Math.min(1, dt * speed));
      state.doorCurrent[part] = Math.abs(target - next) < 0.001 ? target : next;
      anyChanged = true;

      const t = state.doorCurrent[part];
      const eased = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

      const tracks = state.resolvedTracks[part] || [];
      for (const tr of tracks) {
        const { node, prop, start, end } = tr;
        if (prop === 'rotation_degrees') {
          const rx = THREE.MathUtils.degToRad(THREE.MathUtils.lerp(start[0], end[0], eased));
          const ry = THREE.MathUtils.degToRad(THREE.MathUtils.lerp(start[1], end[1], eased));
          const rz = THREE.MathUtils.degToRad(THREE.MathUtils.lerp(start[2], end[2], eased));
          const euler = new THREE.Euler(rx, ry, rz, 'YXZ');
          node.quaternion.setFromEuler(euler);
        } else if (prop === 'translation') {
          node.position.set(
            THREE.MathUtils.lerp(start[0], end[0], eased),
            THREE.MathUtils.lerp(start[1], end[1], eased),
            THREE.MathUtils.lerp(start[2], end[2], eased)
          );
        } else if (prop === 'delta_translation') {
          const orig = node.userData.origPos || new THREE.Vector3();
          node.position.set(
            orig.x + THREE.MathUtils.lerp(start[0], end[0], eased),
            orig.y + THREE.MathUtils.lerp(start[1], end[1], eased),
            orig.z + THREE.MathUtils.lerp(start[2], end[2], eased)
          );
        } else if (prop === 'scale') {
          node.scale.set(
            THREE.MathUtils.lerp(start[0], end[0], eased),
            THREE.MathUtils.lerp(start[1], end[1], eased),
            THREE.MathUtils.lerp(start[2], end[2], eased)
          );
        }
      }
    }
  }

  if (anyChanged) {
    markPathTracerSceneDirty();
  }
}

// ============================================================================
// FAST O(1) PART EXPLOSION / SPREAD ENGINE
// ============================================================================
function prepareExplosionNodes(root, rootCenter) {
  state.explodeNodes = [];
  const meshCenter = new THREE.Vector3();
  const parentQuatInv = new THREE.Quaternion();

  root.traverse((node) => {
    if (node.isMesh && node.geometry) {
      if (!node.geometry.boundingBox) {
        node.geometry.computeBoundingBox();
      }
      node.geometry.boundingBox.getCenter(meshCenter);
      meshCenter.applyMatrix4(node.matrixWorld);

      const dir = meshCenter.clone().sub(rootCenter);
      if (dir.lengthSq() < 0.0001) {
        dir.set(0, 1, 0);
      }
      if (node.parent) {
        node.parent.getWorldQuaternion(parentQuatInv).invert();
        dir.applyQuaternion(parentQuatInv);
      }
      dir.multiplyScalar(0.85);

      state.explodeNodes.push({
        node,
        origPos: node.position.clone(),
        localDir: dir,
      });
    }
  });
}

function applyExplosion(amount) {
  state.explodeAmount = amount;
  for (const item of state.explodeNodes) {
    item.node.position.copy(item.origPos).addScaledVector(item.localDir, amount);
  }
  markPathTracerSceneDirty();
}

// ============================================================================
// LIVE 3D WHEEL SWAPPER & WHEEL SPINNING
// ============================================================================
function collectWheelPivots(root) {
  state.wheelPivotNodes = [];
  state.factoryWheelClones.clear();

  const wheelPatterns = [
    'Wheel_LF_Spatial', 'Wheel_RF_Spatial', 'Wheel_LR_Spatial', 'Wheel_RR_Spatial', 'Wheel_RL_Spatial',
    'Wheel_LF_Locator', 'Wheel_RF_Locator', 'Wheel_LR_Locator', 'Wheel_RR_Locator',
    'Wheel_MR_Spatial', 'Wheel_ML_Spatial',
  ];

  root.traverse((node) => {
    if (wheelPatterns.includes(node.name)) {
      state.wheelPivotNodes.push(node);
      const cloneChildren = node.children.map((c) => c.clone(true));
      state.factoryWheelClones.set(node, cloneChildren);
    }
  });
}

async function fetchGltfCached(url, onProgress) {
  if (gltfCache.has(url)) {
    return gltfCache.get(url).clone(true);
  }
  const gltf = await new Promise((resolve, reject) => {
    gltfLoader.load(url, resolve, onProgress, reject);
  });
  gltfCache.set(url, gltf.scene);
  return gltf.scene.clone(true);
}

async function swapWheelsOnCurrentVehicle(wheelId) {
  if (!state.currentModelRoot || state.wheelPivotNodes.length === 0) return;

  const labelEl = document.getElementById('wheel-swap-label');

  if (!wheelId) {
    for (const pivot of state.wheelPivotNodes) {
      while (pivot.children.length > 0) {
        pivot.remove(pivot.children[0]);
      }
      const origChildren = state.factoryWheelClones.get(pivot) || [];
      origChildren.forEach((ch) => pivot.add(ch.clone(true)));
    }
    upgradeModelMaterials(state.currentModelRoot);
    if (labelEl) labelEl.textContent = 'Factory Default';
    markPathTracerSceneDirty(true);
    return;
  }

  const wheelEntry = state.catalog.wheels.find((w) => w.id === wheelId);
  if (!wheelEntry) return;

  if (labelEl) labelEl.textContent = wheelEntry.name;

  const donorWheel = await fetchGltfCached(wheelEntry.file);
  const donorBox = new THREE.Box3().setFromObject(donorWheel);
  const donorSize = donorBox.getSize(new THREE.Vector3());
  const donorDiameter = Math.max(donorSize.x, donorSize.y, 0.4);

  for (const pivot of state.wheelPivotNodes) {
    const curBox = new THREE.Box3().setFromObject(pivot);
    const curSize = curBox.getSize(new THREE.Vector3());
    const targetDiameter = Math.max(curSize.x, curSize.y, 0.68);
    const scaleFactor = targetDiameter / donorDiameter;

    while (pivot.children.length > 0) {
      pivot.remove(pivot.children[0]);
    }

    const inst = donorWheel.clone(true);
    const isRightSide = pivot.name.includes('_RF') || pivot.name.includes('_RR') || pivot.name.includes('_MR');
    inst.scale.set(scaleFactor, scaleFactor, isRightSide ? -scaleFactor : scaleFactor);
    pivot.add(inst);
  }

  upgradeModelMaterials(state.currentModelRoot);
  markPathTracerSceneDirty(true);
}

// ============================================================================
// ASSET LOADER & CAMERA FRAMING
// ============================================================================
async function loadAsset(asset) {
  state.currentAsset = asset;

  const loadingOverlay = document.getElementById('loading-overlay');
  const loadingTitle = document.getElementById('loading-title');
  const loadingSub = document.getElementById('loading-sub');
  loadingTitle.textContent = `Loading ${asset.name}...`;
  loadingSub.textContent = 'Streaming binary glTF 2.0 geometry...';
  loadingOverlay.classList.remove('hidden');

  document.querySelectorAll('.asset-card').forEach((card) => {
    card.classList.toggle('active', card.dataset.id === asset.id);
  });

  document.getElementById('hud-badge').textContent = asset.badge || 'TESLA 3D ASSET';
  document.getElementById('hud-title').textContent = asset.name;
  document.getElementById('hud-subtitle').textContent = asset.subtitle || '';

  const specsContainer = document.getElementById('hud-specs');
  if (asset.specs) {
    specsContainer.style.display = 'flex';
    document.getElementById('spec-range').textContent = asset.specs.range;
    document.getElementById('spec-accel').textContent = asset.specs.zeroToSixty;
    document.getElementById('spec-speed').textContent = asset.specs.topSpeed;
    document.getElementById('spec-power').textContent = asset.specs.power;
  } else {
    specsContainer.style.display = 'none';
  }

  const vertsFmt = (asset.vertices || 0).toLocaleString();
  const trisFmt = (asset.triangles || 0).toLocaleString();
  const sizeMb = ((asset.size_bytes || 0) / (1024 * 1024)).toFixed(1);
  document.getElementById('poly-counter').textContent = `${vertsFmt} verts • ${trisFmt} tris • ${sizeMb} MB`;

  const dlBtn = document.getElementById('btn-download-glb');
  dlBtn.href = asset.file;
  dlBtn.download = `${asset.id}.glb`;

  if (asset.defaultPaint) {
    const matchedPaint = PAINT_PALETTE.find((p) => p.name === asset.defaultPaint);
    if (matchedPaint) {
      selectPaintSwatch(matchedPaint, false);
    }
  }

  Object.keys(state.doorTargets).forEach((k) => {
    state.doorTargets[k] = 0;
    state.doorCurrent[k] = 0;
  });
  document.getElementById('btn-toggle-all-doors').textContent = 'Open All';
  document.getElementById('slider-explode').value = '0';
  document.getElementById('select-wheel-swap').value = '';
  document.getElementById('wheel-swap-label').textContent = 'Factory Default';

  try {
    const totalBytes = asset.size_bytes || 1;
    const root = await fetchGltfCached(asset.file, (xhr) => {
      if (xhr && xhr.loaded) {
        const pct = Math.min(100, Math.round((xhr.loaded / (xhr.total || totalBytes)) * 100));
        loadingSub.textContent = `Streaming glTF 2.0 meshes (${pct}%)`;
      }
    });

    while (modelGroup.children.length > 0) {
      modelGroup.remove(modelGroup.children[0]);
    }

    state.currentModelRoot = root;

    // Fast bounding box calculation using geometry bounds
    root.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());

    root.position.set(-center.x, -box.min.y, -center.z);
    modelGroup.add(root);
    modelGroup.updateMatrixWorld(true);

    const worldSize = size.clone();
    const worldCenter = new THREE.Vector3(0, size.y * 0.5, 0);
    const radius = Math.max(worldSize.x, worldSize.y, worldSize.z) * 0.55;

    state.modelBounds = { size: worldSize, center: worldCenter, radius };

    contactShadowMesh.scale.set(worldSize.x * 1.18, worldSize.z * 1.28, 1);

    upgradeModelMaterials(root);
    buildArticulationTracks(root, asset);
    collectWheelPivots(root);
    prepareExplosionNodes(root, worldCenter);

    document.getElementById('sec-wheel-swap').style.opacity = state.wheelPivotNodes.length > 0 ? '1' : '0.45';

    setCameraPreset('hero', true);
    markPathTracerSceneDirty(true);
  } catch (err) {
    console.error('Error loading GLB asset:', err);
    loadingSub.textContent = `Error: ${err.message || err}`;
  } finally {
    loadingOverlay.classList.add('hidden');
  }
}

// ============================================================================
// CAMERA PRESETS & SMOOTH TRANSITIONS
// ============================================================================
function setCameraPreset(presetName, immediate = false) {
  document.querySelectorAll('.camera-dock .cam-btn[data-cam]').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.cam === presetName);
  });

  const { size, center, radius } = state.modelBounds;
  const r = Math.max(radius, 0.85);
  const target = new THREE.Vector3(0, center.y * 0.88, 0);
  const pos = new THREE.Vector3();

  switch (presetName) {
    case 'hero':
      pos.set(r * 1.65, r * 0.68, r * 1.48);
      break;
    case 'side':
      pos.set(0.0, r * 0.48, r * 2.15);
      break;
    case 'rear':
      pos.set(-r * 1.68, r * 0.65, r * 1.42);
      break;
    case 'front':
      pos.set(r * 2.05, r * 0.46, 0.02);
      break;
    case 'wheel':
      target.set(size.x * 0.28, size.y * 0.24, size.z * 0.36);
      pos.set(size.x * 0.34, size.y * 0.28, size.z * 0.95);
      break;
    case 'interior':
      target.set(size.x * 0.12, size.y * 0.62, 0.0);
      pos.set(-size.x * 0.08, size.y * 0.72, size.z * 0.26);
      break;
    case 'top':
      pos.set(0.05, r * 2.45, 0.05);
      break;
    default:
      pos.set(r * 1.65, r * 0.68, r * 1.48);
  }

  if (immediate) {
    camera.position.copy(pos);
    controls.target.copy(target);
    controls.update();
    state.cameraAnim = null;
    markPathTracerCameraDirty();
  } else {
    state.cameraAnim = {
      startPos: camera.position.clone(),
      endPos: pos,
      startTarget: controls.target.clone(),
      endTarget: target,
      progress: 0,
    };
  }
}

// ============================================================================
// GPU PATH TRACER SYNCHRONIZATION
// ============================================================================
function markPathTracerSceneDirty(rebuildBvh = false) {
  state.ptDirty = true;
  state.ptSamples = 0;

  if (state.renderMode === 'pathtrace' && pathTracer && !state.pathTracerFallbackMode) {
    try {
      if (rebuildBvh || !state.pathTracerReady) {
        pathTracer.setScene(scene, camera);
        state.pathTracerReady = true;
      } else {
        pathTracer.updateMaterials();
        pathTracer.updateEnvironment();
        pathTracer.updateLights();
      }
      pathTracer.reset();
    } catch (err) {
      console.warn('WebGLPathTracer scene sync fallback:', err);
      state.pathTracerFallbackMode = true;
    }
  }
}

function markPathTracerCameraDirty() {
  state.ptSamples = 0;
  if (state.renderMode === 'pathtrace' && pathTracer && !state.pathTracerFallbackMode && state.pathTracerReady) {
    try {
      pathTracer.updateCamera();
      pathTracer.reset();
    } catch (err) {
      state.pathTracerFallbackMode = true;
    }
  }
}

async function setRenderMode(mode) {
  state.renderMode = mode;
  document.getElementById('btn-mode-realtime').classList.toggle('active', mode === 'realtime');
  document.getElementById('btn-mode-pathtrace').classList.toggle('active', mode === 'pathtrace');

  const ptHud = document.getElementById('pt-hud');
  if (mode === 'pathtrace') {
    ptHud.classList.remove('hidden');
    document.getElementById('pt-samples-text').textContent = 'Building BVH...';
    await ensurePathTracerInitialized();
    state.pathTracerReady = false;
    markPathTracerSceneDirty(true);
  } else {
    ptHud.classList.add('hidden');
  }
}

// ============================================================================
// UI BINDINGS & CONTROLS
// ============================================================================
function renderAssetList() {
  const listEl = document.getElementById('asset-list');
  listEl.innerHTML = '';

  const q = state.searchQuery.trim().toLowerCase();
  let items = [];

  if (q.length > 0) {
    items = [
      ...state.catalog.vehicles,
      ...state.catalog.wheels,
      ...state.catalog.energy_and_accessories,
    ].filter(
      (item) =>
        item.name.toLowerCase().includes(q) ||
        (item.subtitle || '').toLowerCase().includes(q) ||
        item.id.toLowerCase().includes(q)
    );
  } else {
    items = state.catalog[state.activeTab] || [];
  }

  for (const item of items) {
    const card = document.createElement('div');
    card.className = `asset-card${state.currentAsset?.id === item.id ? ' active' : ''}`;
    card.dataset.id = item.id;

    const trisK = ((item.triangles || 0) / 1000).toFixed(1) + 'k tris';
    const sizeMb = ((item.size_bytes || 0) / (1024 * 1024)).toFixed(1) + ' MB';

    card.innerHTML = `
      <div class="asset-card-top">
        <span class="asset-name">${item.name}</span>
        <span class="asset-badge">${item.badge || '3D'}</span>
      </div>
      <div class="asset-sub">${item.subtitle || item.category}</div>
      <div class="asset-meta">
        <span>${trisK}</span>
        <span>•</span>
        <span>${sizeMb}</span>
        ${item.animations?.length ? `<span>• ${item.animations.length} anims</span>` : ''}
      </div>
    `;

    card.addEventListener('click', () => loadAsset(item));
    listEl.appendChild(card);
  }
}

function selectPaintSwatch(paintObj, updateSliders = true) {
  state.paint = { ...paintObj };
  document.getElementById('paint-name-label').textContent = paintObj.name;

  document.querySelectorAll('#paint-swatches .swatch-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.name === paintObj.name);
  });

  if (updateSliders) {
    document.getElementById('slider-clearcoat').value = String(paintObj.clearcoat);
    document.getElementById('slider-roughness').value = String(paintObj.roughness);
    document.getElementById('slider-metallic').value = String(paintObj.metalness);
  }

  applyPaintStateToMaterials();
}

function applyPaintStateToMaterials() {
  const isStainless = state.paint.name === 'Stainless Steel';
  for (const mat of state.materialBuckets.paint) {
    mat.color.set(state.paint.hex);
    mat.metalness = state.paint.metalness;
    mat.roughness = state.paint.roughness;
    mat.clearcoat = state.paint.clearcoat;
    mat.roughnessMap = isStainless ? brushedTex : null;
    mat.needsUpdate = true;
  }
  markPathTracerSceneDirty();
}

function populateSceneTreeModal() {
  const container = document.getElementById('scene-tree-list');
  const filter = document.getElementById('node-search').value.trim().toLowerCase();
  container.innerHTML = '';

  if (!state.currentModelRoot) return;

  const rows = [];
  state.currentModelRoot.traverse((node) => {
    if (node === state.currentModelRoot) return;
    const matName = node.isMesh ? (node.material?.name || '') : '';
    const textMatch =
      !filter ||
      node.name.toLowerCase().includes(filter) ||
      matName.toLowerCase().includes(filter);
    if (!textMatch) return;

    let depth = 0;
    let p = node.parent;
    while (p && p !== state.currentModelRoot) {
      depth++;
      p = p.parent;
    }

    rows.push({ node, depth, matName });
  });

  for (const { node, depth, matName } of rows) {
    const row = document.createElement('div');
    row.className = `tree-node-row${node.visible ? '' : ' hidden-node'}`;
    row.style.paddingLeft = `${12 + depth * 14}px`;

    const badgeType = node.isMesh ? 'MESH' : 'PIVOT';
    row.innerHTML = `
      <span class="tree-type ${node.isMesh ? 'mesh-badge' : 'pivot-badge'}">${badgeType}</span>
      <span class="tree-name">${node.name || '(unnamed)'}</span>
      <span class="tree-mat">${matName}</span>
      <button class="tree-vis-btn">${node.visible ? 'Visible' : 'Hidden'}</button>
    `;

    row.addEventListener('click', () => {
      node.visible = !node.visible;
      row.classList.toggle('hidden-node', !node.visible);
      row.querySelector('.tree-vis-btn').textContent = node.visible ? 'Visible' : 'Hidden';
      markPathTracerSceneDirty();
    });

    container.appendChild(row);
  }
}

function initUIListeners() {
  document.getElementById('btn-mode-realtime').addEventListener('click', () => setRenderMode('realtime'));
  document.getElementById('btn-mode-pathtrace').addEventListener('click', () => setRenderMode('pathtrace'));

  document.querySelectorAll('#catalog-tabs .tab-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#catalog-tabs .tab-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.activeTab = btn.dataset.tab;
      state.searchQuery = '';
      document.getElementById('asset-search').value = '';
      renderAssetList();
      const firstInTab = (state.catalog[state.activeTab] || [])[0];
      if (firstInTab) loadAsset(firstInTab);
    });
  });

  document.getElementById('asset-search').addEventListener('input', (e) => {
    state.searchQuery = e.target.value;
    renderAssetList();
  });

  const swatchContainer = document.getElementById('paint-swatches');
  PAINT_PALETTE.forEach((p) => {
    const btn = document.createElement('button');
    btn.className = 'swatch-btn';
    btn.dataset.name = p.name;
    btn.title = p.name;
    btn.style.background = p.hex;
    btn.addEventListener('click', () => selectPaintSwatch(p, true));
    swatchContainer.appendChild(btn);
  });

  document.getElementById('slider-clearcoat').addEventListener('input', (e) => {
    state.paint.clearcoat = parseFloat(e.target.value);
    applyPaintStateToMaterials();
  });
  document.getElementById('slider-roughness').addEventListener('input', (e) => {
    state.paint.roughness = parseFloat(e.target.value);
    applyPaintStateToMaterials();
  });
  document.getElementById('slider-metallic').addEventListener('input', (e) => {
    state.paint.metalness = parseFloat(e.target.value);
    applyPaintStateToMaterials();
  });

  document.querySelectorAll('#door-buttons .door-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const part = btn.dataset.part;
      const next = state.doorTargets[part] > 0.5 ? 0 : 1;
      state.doorTargets[part] = next;
      btn.classList.toggle('active', next === 1);
    });
  });

  document.getElementById('btn-toggle-all-doors').addEventListener('click', (e) => {
    const anyClosed = ['frunk', 'trunk', 'door_lf', 'door_rf', 'door_lr', 'door_rr'].some(
      (k) => (state.resolvedTracks[k]?.length || 0) > 0 && state.doorTargets[k] < 0.5
    );
    const targetVal = anyClosed ? 1 : 0;
    e.target.textContent = targetVal ? 'Close All' : 'Open All';

    document.querySelectorAll('#door-buttons .door-btn').forEach((btn) => {
      const part = btn.dataset.part;
      if (state.resolvedTracks[part]?.length > 0) {
        state.doorTargets[part] = targetVal;
        btn.classList.toggle('active', targetVal === 1);
      }
    });
  });

  document.getElementById('slider-explode').addEventListener('input', (e) => {
    applyExplosion(parseFloat(e.target.value));
  });

  document.getElementById('select-wheel-swap').addEventListener('change', (e) => {
    swapWheelsOnCurrentVehicle(e.target.value);
  });

  document.querySelectorAll('#interior-pills .mini-pill').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#interior-pills .mini-pill').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.interior = btn.dataset.interior;
      const theme = INTERIOR_THEMES[state.interior] || INTERIOR_THEMES.black;
      for (const mat of state.materialBuckets.interior) {
        mat.color.set(mat.userData.isPrimarySeat ? theme.primary : theme.secondary);
        mat.roughness = theme.roughness;
      }
      markPathTracerSceneDirty();
    });
  });

  document.querySelectorAll('#caliper-pills .mini-pill').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#caliper-pills .mini-pill').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.caliperColor = btn.dataset.caliper;
      for (const mat of state.materialBuckets.caliper) {
        mat.color.set(state.caliperColor);
      }
      markPathTracerSceneDirty();
    });
  });

  document.getElementById('slider-tint').addEventListener('input', (e) => {
    state.windowTint = parseFloat(e.target.value);
    for (const mat of state.materialBuckets.glass_tinted) {
      mat.opacity = Math.max(0.25, state.windowTint);
      mat.transmission = 1.0 - state.windowTint * 0.72;
    }
    markPathTracerSceneDirty();
  });

  document.querySelectorAll('#env-buttons .env-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#env-buttons .env-btn').forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      state.envPreset = btn.dataset.env;
      document.getElementById('env-name-label').textContent = ENV_PRESETS[state.envPreset].label;
      buildStudioEnvironment(state.envPreset, state.envRotationDeg);
    });
  });

  document.getElementById('slider-exposure').addEventListener('input', (e) => {
    state.exposure = parseFloat(e.target.value);
    renderer.toneMappingExposure = state.exposure;
    markPathTracerSceneDirty();
  });

  document.getElementById('slider-env-rot').addEventListener('input', (e) => {
    state.envRotationDeg = parseFloat(e.target.value);
    buildStudioEnvironment(state.envPreset, state.envRotationDeg);
  });

  document.getElementById('slider-lights-emissive').addEventListener('input', (e) => {
    state.emissiveStrength = parseFloat(e.target.value);
    for (const mat of state.materialBuckets.emissive) {
      mat.emissiveIntensity = state.emissiveStrength * (mat.userData.baseEmissiveScale || 1.0);
    }
    markPathTracerSceneDirty();
  });

  document.getElementById('slider-floor-refl').addEventListener('input', (e) => {
    state.floorReflectivity = parseFloat(e.target.value);
    floorMat.clearcoat = state.floorReflectivity;
    floorMat.roughness = 0.45 - state.floorReflectivity * 0.35;
    markPathTracerSceneDirty();
  });

  document.getElementById('slider-pt-bounces').addEventListener('input', (e) => {
    state.ptBounces = parseInt(e.target.value, 10);
    if (pathTracer) {
      pathTracer.bounces = state.ptBounces;
      markPathTracerSceneDirty();
    }
  });

  document.getElementById('slider-pt-aperture').addEventListener('input', (e) => {
    state.ptAperture = parseFloat(e.target.value);
    markPathTracerCameraDirty();
  });

  document.querySelectorAll('.camera-dock .cam-btn[data-cam]').forEach((btn) => {
    btn.addEventListener('click', () => setCameraPreset(btn.dataset.cam, false));
  });

  document.getElementById('btn-turntable').addEventListener('click', (e) => {
    state.turntable = !state.turntable;
    e.currentTarget.classList.toggle('active', state.turntable);
  });

  document.getElementById('btn-spin-wheels').addEventListener('click', (e) => {
    state.spinWheels = !state.spinWheels;
    e.currentTarget.classList.toggle('active', state.spinWheels);
  });

  document.getElementById('btn-wireframe').addEventListener('click', (e) => {
    state.wireframe = !state.wireframe;
    e.currentTarget.classList.toggle('active', state.wireframe);
    for (const mat of state.materialBuckets.all) {
      mat.wireframe = state.wireframe;
    }
  });

  document.getElementById('btn-screenshot').addEventListener('click', () => {
    const link = document.createElement('a');
    const id = state.currentAsset?.id || 'tesla_studio';
    link.download = `${id}_${state.renderMode}_render.png`;
    link.href = canvas.toDataURL('image/png');
    link.click();
  });

  const modal = document.getElementById('scene-modal');
  document.getElementById('btn-inspect-nodes').addEventListener('click', () => {
    modal.classList.remove('hidden');
    populateSceneTreeModal();
  });
  document.getElementById('btn-close-modal').addEventListener('click', () => {
    modal.classList.add('hidden');
  });
  document.getElementById('node-search').addEventListener('input', populateSceneTreeModal);
  document.getElementById('btn-show-all-nodes').addEventListener('click', () => {
    if (state.currentModelRoot) {
      state.currentModelRoot.traverse((n) => {
        n.visible = true;
      });
      populateSceneTreeModal();
      markPathTracerSceneDirty();
    }
  });

  controls.addEventListener('change', () => {
    markPathTracerCameraDirty();
  });
  controls.addEventListener('start', () => {
    state.isInteracting = true;
    state.cameraAnim = null;
  });
  controls.addEventListener('end', () => {
    state.isInteracting = false;
  });
}

// ============================================================================
// VIEWPORT RESIZE HANDLER
// ============================================================================
function handleResize() {
  const w = viewportEl.clientWidth;
  const h = viewportEl.clientHeight;
  if (w === 0 || h === 0) return;

  camera.aspect = w / h;
  camera.updateProjectionMatrix();

  renderer.setSize(w, h, false);
  composer.setSize(w, h);
  bloomPass.resolution.set(Math.floor(w * 0.5), Math.floor(h * 0.5));

  markPathTracerCameraDirty();
}

window.addEventListener('resize', handleResize);

// ============================================================================
// MAIN RENDER & PATH-TRACING ACCUMULATION LOOP
// ============================================================================
let lastTime = performance.now();

function animate(now) {
  requestAnimationFrame(animate);

  const dt = Math.min(0.1, (now - lastTime) / 1000);
  lastTime = now;

  if (state.cameraAnim) {
    state.cameraAnim.progress = Math.min(1, state.cameraAnim.progress + dt * 2.2);
    const t = state.cameraAnim.progress;
    const ease = 1 - Math.pow(1 - t, 3);
    camera.position.lerpVectors(state.cameraAnim.startPos, state.cameraAnim.endPos, ease);
    controls.target.lerpVectors(state.cameraAnim.startTarget, state.cameraAnim.endTarget, ease);
    if (t >= 1) state.cameraAnim = null;
    markPathTracerCameraDirty();
  }

  if (state.turntable && !state.isInteracting) {
    const angle = dt * 0.42;
    const offset = camera.position.clone().sub(controls.target);
    offset.applyAxisAngle(new THREE.Vector3(0, 1, 0), angle);
    camera.position.copy(controls.target).add(offset);
    markPathTracerCameraDirty();
  }

  if (state.spinWheels && state.wheelPivotNodes.length > 0) {
    for (const pivot of state.wheelPivotNodes) {
      pivot.rotation.z -= dt * 8.5;
    }
    markPathTracerSceneDirty();
  }

  applyArticulationStep(dt);

  controls.update();

  if (state.renderMode === 'pathtrace') {
    if (pathTracer && !state.pathTracerFallbackMode) {
      try {
        if (!state.pathTracerReady) {
          pathTracer.setScene(scene, camera);
          state.pathTracerReady = true;
        }
        if (state.ptSamples < state.ptMaxSamples) {
          pathTracer.renderSample();
          state.ptSamples = Math.floor(pathTracer.samples);
        }
      } catch (err) {
        console.warn('Switching to high-precision PBR accumulation:', err);
        state.pathTracerFallbackMode = true;
      }
    }

    if (state.pathTracerFallbackMode || !pathTracer) {
      composer.render();
      if (state.ptSamples < state.ptMaxSamples) {
        state.ptSamples++;
      }
    }

    const samplesClamped = Math.min(state.ptSamples, state.ptMaxSamples);
    const pct = Math.min(100, (samplesClamped / state.ptMaxSamples) * 100);
    document.getElementById('pt-samples-text').textContent = `${samplesClamped} / ${state.ptMaxSamples} samples`;
    document.getElementById('pt-progress-bar').style.width = `${pct.toFixed(1)}%`;
  } else {
    composer.render();
  }
}

// ============================================================================
// BOOTSTRAP
// ============================================================================
async function init() {
  handleResize();
  buildStudioEnvironment(state.envPreset, state.envRotationDeg);
  initUIListeners();

  // Start rendering loop immediately so studio environment is live
  requestAnimationFrame(animate);

  try {
    const resp = await fetch('models/catalog.json');
    state.catalog = await resp.json();

    document.getElementById('count-vehicles').textContent = state.catalog.vehicles.length;
    document.getElementById('count-wheels').textContent = state.catalog.wheels.length;
    document.getElementById('count-energy').textContent = state.catalog.energy_and_accessories.length;

    const wheelSelect = document.getElementById('select-wheel-swap');
    for (const w of state.catalog.wheels) {
      const opt = document.createElement('option');
      opt.value = w.id;
      opt.textContent = w.name;
      wheelSelect.appendChild(opt);
    }

    renderAssetList();

    // Load Model 3 Performance (5.2 MB) or Cybertruck immediately
    const initialVehicle =
      state.catalog.vehicles.find((v) => v.id === 'model3_high') ||
      state.catalog.vehicles[0];
    if (initialVehicle) {
      await loadAsset(initialVehicle);
    }
  } catch (err) {
    console.error('Failed to load catalog.json:', err);
    document.getElementById('loading-overlay').classList.add('hidden');
  }
}

init();
