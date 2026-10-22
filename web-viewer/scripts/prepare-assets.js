import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, unlinkSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { convertVehicle, replaceVehicleBlob } from '../src/vehicle-scene.js';

// GLTFLoader only needs geometry for packing; skip embedded image decoding in Node.
globalThis.self = globalThis;
globalThis.createImageBitmap = async () => ({ width: 1, height: 1, close() {} });
globalThis.ProgressEvent = class { constructor(type, data) { Object.assign(this, data); this.type = type; } };
const root = new URL('../', import.meta.url);
const models = new URL('../../models/', import.meta.url);
const output = new URL('site-assets/', root);
mkdirSync(output, { recursive: true });
if (process.argv.includes('--prepared') || !existsSync(new URL('catalog.json', models))) {
  const manifest = JSON.parse(readFileSync(new URL('manifest.json', output)));
  for (const entry of [manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)]) {
    if (!existsSync(new URL(entry.file, output))) throw new Error(`Missing deployment asset: ${entry.file}`);
  }
  console.log('Using checked-in, prepared site assets; APK extraction is not needed.');
  process.exit(0);
}
mkdirSync(new URL('generated/', root), { recursive: true });
function emit(name, bytes, folder = 'models') {
  const packed = gzipSync(bytes, { level: 9 });
  const hash = createHash('sha256').update(packed).digest('hex').slice(0, 12);
  const filename = `${folder}/${name}.${hash}.bin`;
  mkdirSync(new URL(`${folder}/`, output), { recursive: true });
  const path = new URL(filename, output);
  if (!existsSync(path)) writeFileSync(path, packed);
  return { file: filename, bytes: packed.length, decodedBytes: bytes.byteLength };
}
const source = readFileSync(new URL('public/reference/file.riv', root));
const scene = Uint8Array.from(source).buffer;
const start = source.indexOf('RCP2');
const view = new DataView(scene);
let end = start + 112;
for (let i = 0; i < view.getUint32(start + 4, true); i++) end += 64 + view.getUint32(end + 36, true) * 20 + view.getUint32(end + 40, true) * 4;
const empty = scene.slice(start, start + 112);
new DataView(empty).setUint32(4, 0, true);
const manifest = { version: 1, scene: emit('scene', replaceVehicleBlob(scene, empty), 'scene'), bmw: emit('bmw', scene.slice(start, end)), vehicles: [], files: {} };
// Restore the original BMW caption in the shared shell; Tesla captions are replaced on assembly.
const shell = Buffer.from(replaceVehicleBlob(scene, empty));
let at;
while ((at = shell.indexOf('TESLA ')) >= 0) shell.write('BMW XM', at);
manifest.scene = emit('scene', shell, 'scene');
const catalog = JSON.parse(readFileSync(new URL('catalog.json', models)));
for (const vehicle of catalog.vehicles) {
  const bytes = readFileSync(new URL(vehicle.file.replace(/^models\//, ''), models));
  const inputHash = createHash('sha256').update(bytes).update(readFileSync(new URL('src/vehicle-scene.js', root))).update(readFileSync(new URL('src/vehicle-materials.js', root))).update(readFileSync(new URL('src/charging-geometry.js', root))).update(readFileSync(new URL('src/cybertruck-optics.js', root))).digest('hex');
  const cachePath = new URL(`generated/${vehicle.id}.cache.json`, root);
  let record;
  if (existsSync(cachePath)) {
    const cached = JSON.parse(readFileSync(cachePath));
    if (cached.hash === inputHash && existsSync(new URL(cached.packed.file, output))) record = cached;
  }
  if (!record) {
    const { packed, rig } = await convertVehicle(Uint8Array.from(bytes).buffer, { includeRig: true });
    rig.animations = vehicle.animations || [];
    record = { hash: inputHash, packed: emit(vehicle.id, packed), rig: emit(`${vehicle.id}-rig`, Buffer.from(JSON.stringify(rig)), 'animations') };
    writeFileSync(cachePath, JSON.stringify(record));
  }
  manifest.vehicles.push({ id: vehicle.id, name: vehicle.name, packed: record.packed, rig: record.rig });
}
mkdirSync(new URL('animations/', output), { recursive: true });
writeFileSync(new URL('animations/catalog.json', output), JSON.stringify(catalog));
writeFileSync(new URL('manifest.json', output), JSON.stringify(manifest));
const total = [manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)].reduce((n, a) => n + a.bytes, 0);
console.log(`Prepared ${manifest.vehicles.length} vehicles. Shared scene ${(manifest.scene.bytes / 1e6).toFixed(1)} MB; complete payload ${(total / 1e6).toFixed(1)} MB compressed.`);

const activeFiles = new Set([manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)].map(entry => entry.file));
for (const filename of readdirSync(output, { recursive: true })) if (filename.endsWith('.bin') && !activeFiles.has(filename)) unlinkSync(new URL(filename, output));
