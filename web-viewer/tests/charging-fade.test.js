import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chargingOpacity, patchChargingFadeShader } from '../src/charging-fade.js';

test('plug opacity eases in and out while retaining exact end states', () => {
  assert.equal(chargingOpacity(-1),0);
  assert.equal(chargingOpacity(0),0);
  assert.equal(chargingOpacity(.5),.5);
  assert.equal(chargingOpacity(1),1);
  assert.equal(chargingOpacity(2),1);
  assert.ok(chargingOpacity(.1)<.1);
  assert.ok(chargingOpacity(.9)>.9);
});

test('cable coverage is isolated to tagged vertices and original lighting is restored', () => {
  const source = 'struct VOut { float ao; }; void main() { VOut i_1 = VOut(gl_FragCoord, normal, uv, ao); render(i_1); }';
  const result = patchChargingFadeShader(source);
  assert.ok(result.includes('if (i_1.ao < 0.5)'));
  assert.ok(result.includes('if (coverage >= chargeOpacity) discard;'));
  assert.ok(result.includes('i_1.ao = 1.0;'));
  assert.ok(result.indexOf('i_1.ao = 1.0;') < result.indexOf('render(i_1)'));
  assert.equal(patchChargingFadeShader(result),result);
  const unrelated = 'void main() { gl_Position=vec4(0.0); }';
  assert.equal(patchChargingFadeShader(unrelated),unrelated);
});
