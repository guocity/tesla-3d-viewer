import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { hideSceneMedia, hideOriginalMenus, disableVehicleHotspots } from '../src/scene-interface.js';

test('media edit preserves all authored scene bytes and object indices', () => {
  const original = readFileSync(new URL('../public/reference/file.riv', import.meta.url));
  const source = Uint8Array.from(original).buffer;
  const marker = Buffer.from([4, 6, 68, 111, 99, 107, 32, 82, 5, 199, 5, 0]);
  const at = original.indexOf(marker) + marker.length - 1;
  const result = Buffer.from(hideSceneMedia(source));
  assert.equal(result.length, original.length + 5);
  assert.deepEqual(result.subarray(at, at + 5), Buffer.from([18, 0, 0, 0, 0]));
  assert.deepEqual(Buffer.concat([result.subarray(0, at), result.subarray(at + 5)]), original);
  assert.deepEqual(Buffer.from(source), original);
});

test('changed scene versions fail explicitly rather than editing another component', () => {
  assert.throws(() => hideSceneMedia(new ArrayBuffer(0)), /container has changed/);
  const marker = [4, 6, 68, 111, 99, 107, 32, 82, 5, 199, 5, 0];
  assert.throws(() => hideSceneMedia(Uint8Array.from([...marker, ...marker]).buffer), /ambiguous/);
});

test('BMW menu roots are hidden while Garage geometry is preserved', () => {
  const source = readFileSync(new URL('../public/reference/file.riv', import.meta.url));
  const result = Buffer.from(hideOriginalMenus(Uint8Array.from(source).buffer));
  assert.equal(result.length, source.length + 30);
  const start = source.indexOf('RCP2');
  const view = new DataView(source.buffer, source.byteOffset, source.byteLength);
  let end = start + 112;
  for (let i = 0; i < view.getUint32(start + 4, true); i++) end += 64 + view.getUint32(end + 36, true) * 20 + view.getUint32(end + 40, true) * 4;
  assert.deepEqual(result.subarray(start, end), source.subarray(start, end));
  assert.ok(result.includes(Buffer.from([4,9,...Buffer.from('HUD Inner'),5,2,18,0,0,0,0,0])));
});

test('legacy hotspots are collapsed so their hit targets are disabled', () => {
  const original = readFileSync(new URL('../public/reference/file.riv', import.meta.url));
  const result = Buffer.from(disableVehicleHotspots(Uint8Array.from(original).buffer));
  assert.equal(result.length, original.length + 40);
  for (const name of ['Pin 0','Pin 1','Pin 2','Pin 3']) {
    const marker = Buffer.from([4,name.length,...Buffer.from(name),5,34,16,0,0,0,0,17,0,0,0,0,0]);
    assert.ok(result.includes(marker), `${name} must have zero scale on both axes`);
  }
});
