import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, unlinkSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { availableParallelism } from 'node:os';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { convertVehicle, replaceVehicleBlob } from '../src/vehicle-scene.js';

// GLTFLoader only needs geometry for packing; skip embedded image decoding in Node.
globalThis.self = globalThis;
globalThis.createImageBitmap = async () => ({ width: 1, height: 1, close() {} });
globalThis.ProgressEvent = class { constructor(type, data) { Object.assign(this, data); this.type = type; } };
const root = new URL('../', import.meta.url);
const models = new URL('../../models/', import.meta.url);
const output = new URL('site-assets/', root);

function emit(name, bytes, folder = 'models') {
  const packed = gzipSync(bytes, { level: 9 });
  const hash = createHash('sha256').update(packed).digest('hex').slice(0, 12);
  const filename = `${folder}/${name}.${hash}.bin`;
  mkdirSync(new URL(`${folder}/`, output), { recursive: true });
  const path = new URL(filename, output);
  if (!existsSync(path)) writeFileSync(path, packed);
  return { file: filename, bytes: packed.length, decodedBytes: bytes.byteLength };
}

if (!isMainThread) {
  const { vehicle, glbPath, inputHash } = workerData;
  const bytes = readFileSync(new URL(glbPath));
  const { packed, rig } = await convertVehicle(Uint8Array.from(bytes).buffer, { includeRig: true, vehicleId: vehicle.id });
  rig.animations = vehicle.animations || [];
  const record = { hash: inputHash, packed: emit(vehicle.id, packed), rig: emit(`${vehicle.id}-rig`, Buffer.from(JSON.stringify(rig)), 'animations') };
  writeFileSync(new URL(`generated/${vehicle.id}.cache.json`, root), JSON.stringify(record));
  parentPort.postMessage(record);
  process.exit(0);
}

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

const source = readFileSync(new URL('public/reference/file.riv', root));
const sceneHash = createHash('sha256').update(source).update(readFileSync(new URL('src/scene-buffer.js', root))).digest('hex');
const sceneCachePath = new URL('generated/scene.cache.json', root);
let sceneRecord;
if (existsSync(sceneCachePath)) {
  const cached = JSON.parse(readFileSync(sceneCachePath));
  if (cached.hash === sceneHash && existsSync(new URL(cached.scene.file, output)) && existsSync(new URL(cached.bmw.file, output))) sceneRecord = cached;
}
if (!sceneRecord) {
  const scene = Uint8Array.from(source).buffer;
  const start = source.indexOf('RCP2');
  const view = new DataView(scene);
  let end = start + 112;
  for (let i = 0; i < view.getUint32(start + 4, true); i++) end += 64 + view.getUint32(end + 36, true) * 20 + view.getUint32(end + 40, true) * 4;
  const empty = scene.slice(start, start + 112);
  new DataView(empty).setUint32(4, 0, true);
  // Restore the original BMW caption in the shared shell; Tesla captions are replaced on assembly.
  const shell = Buffer.from(replaceVehicleBlob(scene, empty));
  let at;
  while ((at = shell.indexOf('TESLA ')) >= 0) shell.write('BMW XM', at);
  sceneRecord = { hash: sceneHash, scene: emit('scene', shell, 'scene'), bmw: emit('bmw', scene.slice(start, end)) };
  writeFileSync(sceneCachePath, JSON.stringify(sceneRecord));
}
const manifest = { version: 1, scene: sceneRecord.scene, bmw: sceneRecord.bmw, vehicles: [], files: {} };

const sharedSourceHash = createHash('sha256')
  .update(readFileSync(new URL('src/vehicle-scene.js', root)))
  .update(readFileSync(new URL('src/vehicle-materials.js', root)))
  .update(readFileSync(new URL('src/charging-geometry.js', root)))
  .update(readFileSync(new URL('src/cybertruck-optics.js', root)))
  .digest();

const catalog = JSON.parse(readFileSync(new URL('catalog.json', models)));
const records = new Array(catalog.vehicles.length);
const pending = [];

for (let i = 0; i < catalog.vehicles.length; i++) {
  const vehicle = catalog.vehicles[i];
  const glbUrl = new URL(vehicle.file.replace(/^models\//, ''), models);
  const bytes = readFileSync(glbUrl);
  const inputHash = createHash('sha256').update(bytes).update(sharedSourceHash).digest('hex');
  const cachePath = new URL(`generated/${vehicle.id}.cache.json`, root);
  let record;
  if (existsSync(cachePath)) {
    const cached = JSON.parse(readFileSync(cachePath));
    if (cached.hash === inputHash && existsSync(new URL(cached.packed.file, output)) && (!cached.rig || existsSync(new URL(cached.rig.file, output)))) record = cached;
  }
  if (record) records[i] = record;
  else pending.push({ index: i, vehicle, glbPath: glbUrl.href, inputHash });
}

if (pending.length === 1) {
  const { index, vehicle, glbPath, inputHash } = pending[0];
  const bytes = readFileSync(new URL(glbPath));
  const { packed, rig } = await convertVehicle(Uint8Array.from(bytes).buffer, { includeRig: true, vehicleId: vehicle.id });
  rig.animations = vehicle.animations || [];
  const record = { hash: inputHash, packed: emit(vehicle.id, packed), rig: emit(`${vehicle.id}-rig`, Buffer.from(JSON.stringify(rig)), 'animations') };
  writeFileSync(new URL(`generated/${vehicle.id}.cache.json`, root), JSON.stringify(record));
  records[index] = record;
} else if (pending.length > 1) {
  const concurrency = Math.min(pending.length, Math.max(1, availableParallelism()));
  let cursor = 0;
  await Promise.all(Array.from({ length: concurrency }, async () => {
    while (cursor < pending.length) {
      const job = pending[cursor++];
      records[job.index] = await new Promise((resolve, reject) => {
        const worker = new Worker(new URL(import.meta.url), { workerData: { vehicle: job.vehicle, glbPath: job.glbPath, inputHash: job.inputHash } });
        worker.once('message', resolve);
        worker.once('error', reject);
        worker.once('exit', code => { if (code !== 0) reject(new Error(`Worker for ${job.vehicle.id} exited with code ${code}`)); });
      });
    }
  }));
}

for (let i = 0; i < catalog.vehicles.length; i++) {
  const vehicle = catalog.vehicles[i];
  const record = records[i];
  manifest.vehicles.push({ id: vehicle.id, name: vehicle.name, packed: record.packed, rig: record.rig });
}
mkdirSync(new URL('animations/', output), { recursive: true });
writeFileSync(new URL('animations/catalog.json', output), JSON.stringify(catalog));
writeFileSync(new URL('manifest.json', output), JSON.stringify(manifest));
const total = [manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)].reduce((n, a) => n + a.bytes, 0);
console.log(`Prepared ${manifest.vehicles.length} vehicles. Shared scene ${(manifest.scene.bytes / 1e6).toFixed(1)} MB; complete payload ${(total / 1e6).toFixed(1)} MB compressed.`);

const activeFiles = new Set([manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)].map(entry => entry.file));
for (const filename of readdirSync(output, { recursive: true })) if (filename.endsWith('.bin') && !activeFiles.has(filename)) unlinkSync(new URL(filename, output));
