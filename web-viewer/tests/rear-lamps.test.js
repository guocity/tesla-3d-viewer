import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';

const root = new URL('../site-assets/', import.meta.url);
const manifest = JSON.parse(readFileSync(new URL('manifest.json', root)));
for (const vehicle of manifest.vehicles) {
  test(`${vehicle.id}: prepared rear lamps are red and front headlights stay white`, () => {
    const bytes = gunzipSync(readFileSync(new URL(vehicle.packed.file, root)));
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let at = 112, redTriangles = 0, frontWhiteTriangles = 0;
    const qx = view.getFloat32(8, true) / 1.5, qz = view.getFloat32(16, true);
    const axis = qx > qz ? 0 : 2, sign = axis === 0 ? -1 : 1;
    // X quantization reserves a 1.5x margin; Z uses the vehicle length.
    const rearThreshold = 32767 * .2 / (axis === 0 ? 1.5 : 1);
    for (let m = 0; m < view.getUint32(4, true); m++) {
      const name = bytes.subarray(at, at + 32).toString().replace(/\0.*$/, '');
      const vertices = view.getUint32(at + 36, true), count = view.getUint32(at + 40, true);
      if (name === 'Light' || name === 'LightRed' || name === 'GlassRed') {
        for (let i = 0; i < count; i += 3) {
          let z = 0;
          for (let j = 0; j < 3; j++) {
            const vertex = view.getUint32(at + 64 + vertices * 20 + (i + j) * 4, true);
            z += view.getInt16(at + 64 + vertex * 20 + axis * 2, true) / 3;
          }
          if (z * sign < -rearThreshold - 2 && name !== 'GlassRed') {
            assert.notEqual(name, 'LightRed', `${vehicle.id} has a red front headlight triangle`);
            frontWhiteTriangles++;
          }
          if (z * sign > rearThreshold + 2) {
            assert.notEqual(name, 'Light', `${vehicle.id} has a white rear lamp triangle`);
            assert.notEqual(name, 'GlassRed', `${vehicle.id} has an extra tinted rear lens layer`);
            redTriangles++;
          }
        }
      }
      at += 64 + vertices * 20 + count * 4;
    }
    assert.ok(frontWhiteTriangles > 0, `${vehicle.id} must retain white front headlights`);
    assert.ok(redTriangles > 0, `${vehicle.id} must retain red rear lamps`);
  });
}

for (const vehicle of manifest.vehicles) {
  test(`${vehicle.id}: charging covers do not emit light and lamp lenses are clear`, () => {
    const rig = JSON.parse(gunzipSync(readFileSync(new URL(vehicle.rig.file, root))));
    const lensNodes = new Map();
    for (const segment of rig.segments) {
      const name = rig.nodes[segment.node].name;
      if (/charge[_ .-]*(?:cap|port)|chargeport/i.test(name)) {
        assert.ok(!['Light', 'LightRed'].includes(segment.material), `${vehicle.id}: ${name} must not glow`);
      }
      if (/lights?_glass|glass_lights/i.test(name) && /Glass/.test(segment.material)) {
        const group = name.replace(/_\d+$/, '');
        if (!lensNodes.has(group)) lensNodes.set(group, new Set());
        lensNodes.get(group).add(segment.material);
      }
    }
    for (const [name, materials] of lensNodes) assert.ok(materials.has('GlassWhite'), `${vehicle.id}: ${name} must include a clear glass lens`);
  });
}
