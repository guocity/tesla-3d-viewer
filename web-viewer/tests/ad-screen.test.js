import { test } from 'node:test';
import assert from 'node:assert/strict';
import { patchAdShader, adScreenMix } from '../src/ad-screen.js';

test('monitor and reflection sample the ad without replacing other scene textures', () => {
  for(const name of ['ledTex','ledTexF']) {
    const source=`precision highp int;\nvec3 ${name}(vec2 uv) {\n return textureLod(originalWall,uv,0.0).rgb;\n}\nvec3 sky() {return texture(skyMap,vec2(0)).rgb;}`;
    const result=patchAdShader(source);
    assert.ok(result.includes('uniform highp sampler2D uShowroomAd;'));
    assert.ok(result.includes('texture(uShowroomAd, uv)'));
    assert.ok(result.includes('texture(skyMap,vec2(0))'));
    assert.ok(result.includes('textureLod(originalWall,uv,0.0).rgb'));
    assert.equal(patchAdShader(result),result);
  }
  const unrelated='void main() {gl_Position=vec4(0.0);}';assert.equal(patchAdShader(unrelated),unrelated);
});

test('monitor cycles between the ad and original color program with smooth transitions', () => {
  assert.equal(adScreenMix(0),0);assert.equal(adScreenMix(.5),.5);
  assert.equal(adScreenMix(3),1);assert.equal(adScreenMix(7.5),.5);
  assert.equal(adScreenMix(10),0);assert.equal(adScreenMix(16),0);
  assert.equal(adScreenMix(19),1);
});
