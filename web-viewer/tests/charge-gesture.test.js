import { test } from 'node:test';
import assert from 'node:assert/strict';
import { bindChargeGesture } from '../src/charge-gesture.js';

test('charger taps remain clicks and mouse/touch drags reach the canvas without toggling charging', () => {
  const previous={MouseEvent:globalThis.MouseEvent,window:globalThis.window};
  globalThis.window={};
  globalThis.MouseEvent=class {constructor(type,values){this.type=type;Object.assign(this,values);}};
  try {
    for(const pointerType of ['mouse','touch']) {
      const button=new EventTarget(), forwarded=[];
      let captured;
      button.setPointerCapture=id=>{captured=id;};button.hasPointerCapture=id=>captured===id;button.releasePointerCapture=()=>{captured=undefined;};
      const gesture=bindChargeGesture(button,{dispatchEvent:e=>{forwarded.push(e);return true;}});
      const pointer=(type,x,y)=>{const event=new Event(type,{cancelable:true});Object.assign(event,{pointerId:1,isPrimary:true,pointerType,button:0,clientX:x,clientY:y});button.dispatchEvent(event);};
      pointer('pointerdown',100,100);pointer('pointermove',102,101);pointer('pointerup',102,101);
      assert.equal(forwarded.length,0);
      assert.equal(gesture.consumeClick({detail:1}),false);
      pointer('pointerdown',100,100);pointer('pointermove',120,100);pointer('pointermove',170,120);pointer('pointerup',170,120);
      assert.deepEqual(forwarded.map(e=>e.type),['mousedown','mousemove','mousemove','mouseup']);
      assert.equal(forwarded[0].clientX,100);
      assert.equal(forwarded.at(-1).buttons,0);
      assert.equal(gesture.consumeClick({detail:1}),true);
      assert.equal(gesture.consumeClick({detail:0}),false,'keyboard activation still works');
      assert.equal(captured,undefined);
      forwarded.length=0;
      pointer('pointerdown',100,100);pointer('pointermove',125,100);pointer('pointercancel',125,100);
      assert.deepEqual(forwarded.map(e=>e.type),['mousedown','mousemove','mouseup']);
      assert.equal(gesture.dragging,false);
    }
  } finally {Object.assign(globalThis,previous);}
});
