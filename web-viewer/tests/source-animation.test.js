import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sampleTrack } from '../public/legacy/source-animation.js';

test('APK animation evaluates intermediate keys and final authored pose', () => {
  const track = { type: 'value', times: [0, 0.4, 1], values: [[0, 0, 0], [0, 40, 0], [0, 100, 0]], interpolation: 1 };
  assert.deepEqual(sampleTrack(track, 0.7), [0, 70, 0]);
  assert.deepEqual(sampleTrack(track, 1), [0, 100, 0]);
  assert.deepEqual(sampleTrack({ ...track, interpolation: 0 }, 0.7), [0, 40, 0]);
});
test('source transform interpolation preserves scale while slerping rotation', () => {
  const track = { type: 'transform', times: [0, 1], values: [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1], [2, 0, 0, 0, 1, 0, 0, 1, 1, 1]] };
  const sample = sampleTrack(track, 0.5);
  assert.equal(sample.position.x, 1);
  assert.ok(Math.abs(sample.quaternion.length() - 1) < 1e-6);
  assert.deepEqual(sample.scale.toArray(), [1, 1, 1]);
});
test('Godot row-major 12-value transforms preserve the source origin', () => {
  const value = [1, 0, 0, 0, 1, 0, 0, 0, 1, 3, 4, 5];
  const sample = sampleTrack({ type: 'transform', times: [0], values: [value] }, 0);
  assert.deepEqual(sample.position.toArray(), [3, 4, 5]);
  assert.deepEqual(sample.scale.toArray(), [1, 1, 1]);
});
