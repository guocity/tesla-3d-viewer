import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bindViewerTouch } from '../src/viewer-touch.js';

test('finger drags use mouse input and cancellation releases the drag', t => {
  const previous = { MouseEvent: globalThis.MouseEvent, window: globalThis.window };
  t.after(() => Object.assign(globalThis, previous));
  globalThis.window = {};
  globalThis.MouseEvent = class extends Event {
    constructor(type, options) { super(type, options); Object.assign(this, { clientX: options.clientX, clientY: options.clientY, buttons: options.buttons }); }
  };
  const canvas = new EventTarget(), events = [];
  let capture;
  canvas.setPointerCapture = id => { capture = id; };
  canvas.hasPointerCapture = id => capture === id;
  canvas.releasePointerCapture = () => { capture = undefined; };
  for (const type of ['mouseover','mousemove','mousedown','mouseup','mouseout']) canvas.addEventListener(type, e => events.push(e));
  bindViewerTouch(canvas);
  const send = (type, id = 42) => {
    const e = new Event(type, { cancelable: true });
    Object.assign(e, { pointerId: id, pointerType: 'touch', clientX: 120, clientY: 200 });
    canvas.dispatchEvent(e);
  };
  send('pointerdown'); send('pointermove', 43); send('pointermove'); send('pointercancel');
  assert.deepEqual(events.map(e => e.type), ['mouseover','mousemove','mousedown','mousemove','mouseup','mouseout']);
  assert.equal(events[3].buttons, 1);
  assert.equal(events[4].buttons, 0);
  assert.equal(capture, undefined);
  send('pointermove');
  assert.equal(events.length, 6);
  const touch = new Event('touchstart', { cancelable: true });
  canvas.dispatchEvent(touch);
  assert.equal(touch.defaultPrevented, true);
});
