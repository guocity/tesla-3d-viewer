import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { replaceVehicleBlob } from '../src/vehicle-scene.js';

test('replacing the original packed vehicle preserves the entire authored scene', () => {
  const original = readFileSync(new URL('../public/reference/file.riv', import.meta.url));
  const source = Uint8Array.from(original).buffer;
  const start = original.indexOf('RCP2');
  const view = new DataView(source);
  let end = start + 112;
  for (let i = 0; i < view.getUint32(start + 4, true); i++) {
    end += 64 + view.getUint32(end + 36, true) * 20 + view.getUint32(end + 40, true) * 4;
  }
  const result = Buffer.from(replaceVehicleBlob(source, source.slice(start, end)));
  const expected = Buffer.from(original);
  let index;
  while ((index = expected.indexOf('BMW XM')) >= 0) expected.write('TESLA ', index, 'ascii');
  assert.deepEqual(result, expected);
  assert.deepEqual(Buffer.from(source), original, 'source scene must stay immutable');
});

test('unsupported or truncated vehicle data produces an actionable error', () => {
  assert.throws(() => replaceVehicleBlob(new ArrayBuffer(8), new ArrayBuffer(0)), /no supported vehicle buffer/);
  const bytes = new Uint8Array(112);
  bytes.set(new TextEncoder().encode('RCP2'));
  new DataView(bytes.buffer).setUint32(4, 1, true);
  assert.throws(() => replaceVehicleBlob(bytes.buffer, new ArrayBuffer(0)), /Invalid reference vehicle header/);
});
