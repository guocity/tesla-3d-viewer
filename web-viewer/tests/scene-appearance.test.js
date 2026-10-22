import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toggleSceneAppearance } from '../src/scene-appearance.js';

test('Garage sees the press during an advance before key release', () => {
  let pressed = false, night = false;
  const instance = {
    animator: { stateMachines: [{ stateMachine: { name: 'Garage' }, instance: {
      keyInput(key, modifiers, down) { assert.equal(key, 78); pressed = down; return true; },
      advanceAndApply(dt) { assert.ok(dt > 0); if (pressed) night = !night; },
    } }] },
    play(name) { assert.equal(name, 'Garage'); },
  };
  assert.equal(toggleSceneAppearance(instance), true);
  assert.equal(night, true);
  assert.equal(pressed, false);
  toggleSceneAppearance(instance);
  assert.equal(night, false);
});

test('an unloaded scene cannot report a successful appearance change', () => {
  assert.equal(toggleSceneAppearance(null), false);
});
