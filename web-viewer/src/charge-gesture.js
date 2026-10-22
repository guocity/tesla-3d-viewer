// A tap operates the charger; a drag starting on its overlay belongs to the
// showroom. Rive's pinned input adapter listens to mouse events on the canvas.
export function bindChargeGesture(button, canvas) {
  let active, dragged = false;
  function forward(type, event, buttons) {
    canvas.dispatchEvent(new MouseEvent(type, {
      bubbles: true, cancelable: true, view: window,
      clientX: event.clientX, clientY: event.clientY,
      button: 0, buttons, ctrlKey: event.ctrlKey, shiftKey: event.shiftKey,
      altKey: event.altKey, metaKey: event.metaKey,
    }));
  }
  function end(event) {
    if (!active || event.pointerId !== active.pointerId) return;
    if (dragged) forward('mouseup', event, 0);
    const id = active.pointerId;
    active = undefined;
    if (button.hasPointerCapture(id)) button.releasePointerCapture(id);
  }
  button.addEventListener('pointerdown', event => {
    if (active || event.button !== 0 || !event.isPrimary) return;
    dragged = false;
    active = event;
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
  });
  button.addEventListener('pointermove', event => {
    if (!active || event.pointerId !== active.pointerId) return;
    if (!dragged && Math.hypot(event.clientX-active.clientX,event.clientY-active.clientY) >= 6) {
      dragged = true;
      forward('mousedown', active, 1);
    }
    if (dragged) { event.preventDefault(); forward('mousemove', event, 1); }
  });
  button.addEventListener('pointerup', end);
  function cancel(event) {
    if (!active || event.pointerId !== active.pointerId) return;
    end(event);
    dragged = true;
  }
  button.addEventListener('pointercancel', cancel);
  button.addEventListener('lostpointercapture', cancel);
  return {
    consumeClick(event) { return event.detail !== 0 && dragged; },
    reset() { if (active) end(active); dragged = false; },
    get dragging() { return Boolean(active && dragged); },
  };
}
