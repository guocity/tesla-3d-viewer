// The authored Garage drag uses the mouse pointer (id 0). Normalize finger
// input to that same path instead of passing iOS touch identifiers into it.
export function bindViewerTouch(canvas) {
  let active;
  const forward = (type, point, buttons) => canvas.dispatchEvent(new MouseEvent(type, {
    bubbles: true, cancelable: true, view: window,
    clientX: point.clientX, clientY: point.clientY, button: 0, buttons,
  }));
  canvas.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch' || active) return;
    active = event.pointerId;
    event.preventDefault();
    canvas.setPointerCapture(active);
    forward('mouseover', event, 0);
    forward('mousemove', event, 0);
    forward('mousedown', event, 1);
  });
  canvas.addEventListener('pointermove', event => {
    if (event.pointerId !== active) return;
    event.preventDefault();
    forward('mousemove', event, 1);
  });
  const end = event => {
    if (event.pointerId !== active) return;
    event.preventDefault();
    forward('mouseup', event, 0);
    forward('mouseout', event, 0);
    const id = active; active = undefined;
    if (canvas.hasPointerCapture(id)) canvas.releasePointerCapture(id);
  };
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) canvas.addEventListener(type, end);
  // Avoid duplicate input from Rive's own TouchEvent adapter and compatibility clicks.
  for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel']) {
    canvas.addEventListener(type, event => {
      event.preventDefault(); event.stopImmediatePropagation();
    }, { capture: true, passive: false });
  }
}

export function preventViewerKeyboard(doc) {
  // This viewer has no text entry. Rive can append its hidden editing proxy
  // lazily when an authored focus node is tapped.
  const lock = () => doc.querySelectorAll('input,textarea').forEach(input => {
    input.readOnly = true;
    input.inputMode = 'none';
    if (doc.activeElement === input) input.blur();
  });
  new MutationObserver(lock).observe(doc.body, { childList: true, subtree: true });
  doc.addEventListener('focusin', event => {
    if (event.target.matches('input,textarea')) { lock(); event.target.blur(); }
  }, true);
  lock();
}
