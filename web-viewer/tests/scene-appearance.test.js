import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toggleSceneAppearance } from '../src/scene-appearance.js';

test('Garage sees the press during an advance before key release', () => {
  let pressed = false, night = false;
  const instance = {
    animator: { stateMachines: [{ stateMachine: { name: 'Garage' }, instance: {
      hasFocusNodes() { return true; }, clearFocus() {}, focusNext() { return true; },
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

test('a stale held key is released before repeated appearance switches', () => {
  let pressed=true, previous=true, night=false;
  const instance={
    animator:{stateMachines:[{stateMachine:{name:'Garage'},instance:{
      hasFocusNodes() { return true; }, clearFocus() {}, focusNext() { return true; },
      keyInput(key, modifiers, down) { pressed=down; return down; },
      advanceAndApply() { if(pressed && !previous) night=!night; previous=pressed; },
    }}]}, play() {},
  };
  assert.equal(toggleSceneAppearance(instance),true);
  assert.equal(night,true);
  toggleSceneAppearance(instance);
  assert.equal(night,false);
  assert.equal(pressed,false);
  assert.equal(previous,false);
});

test('HTML focus loss is repaired on every click before sending N', () => {
  let focused=false, pressed=false, night=false;
  const machine={
    hasFocusNodes(){return true;},
    clearFocus(){focused=false;},
    focusNext(){focused=true;return true;},
    keyInput(key, modifiers, down){if(!focused)return false;pressed=down;return down;},
    advanceAndApply(){if(pressed)night=!night;},
  };
  const instance={animator:{stateMachines:[{stateMachine:{name:'Garage'},instance:machine}]},play(){}};
  for(let i=0;i<6;i++) {
    assert.equal(toggleSceneAppearance(instance),true);
    assert.equal(night,i%2===0);
    assert.equal(focused,false);
    assert.equal(pressed,false);
  }
});

test('ignored key commands do not report an appearance change', () => {
  const machine={hasFocusNodes:()=>true,clearFocus(){},focusNext:()=>true,keyInput:()=>false,advanceAndApply(){}};
  assert.equal(toggleSceneAppearance({animator:{stateMachines:[{stateMachine:{name:'Garage'},instance:machine}]},play(){}}),false);
  machine.focusNext=()=>false;
  assert.equal(toggleSceneAppearance({animator:{stateMachines:[{stateMachine:{name:'Garage'},instance:machine}]}}),false);
});
