// Pinned Rive WebGL2 adapter. Match complete packed mesh signatures before
// retaining a buffer; unrelated UI, index and uniform uploads are never modified.
export function createVehicleBridge(canvas) {
  const contexts = new WeakSet();
  let parts = [], matched = new Map(), reveal, lastProbe = 0;
  function probe(gl) {
    if (!reveal || performance.now() - lastProbe < 100 || !gl.drawingBufferWidth) return;
    lastProbe = performance.now();
    if (gl.getParameter(gl.DRAW_FRAMEBUFFER_BINDING) !== null) return;
    const previous = gl.getParameter(gl.READ_FRAMEBUFFER_BINDING);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
    const pixel = new Uint8Array(4);
    let lit = 0;
    for (const [x,y] of [[0.12,0.82],[0.48,0.86],[0.84,0.82]]) {
      gl.readPixels(Math.floor(gl.drawingBufferWidth*x),Math.floor(gl.drawingBufferHeight*y),1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixel);
      if (pixel[0]+pixel[1]+pixel[2]>100) lit++;
    }
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, previous);
    if (lit >= 2) { const done = reveal; reveal = null; queueMicrotask(done); }
  }
  const getContext = canvas.getContext;
  canvas.getContext = function (...args) {
    const gl = getContext.apply(this, args);
    if (!gl || !args[0].includes('webgl') || contexts.has(gl)) return gl;
    contexts.add(gl);
    for (const method of ['drawElements','drawArrays','drawElementsInstanced','drawArraysInstanced','drawRangeElements','blitFramebuffer','flush']) {
      const originalDraw = gl[method];
      if (!originalDraw) continue;
      gl[method] = function (...args) { const result = originalDraw.apply(gl,args); probe(gl); return result; };
    }
    const original = gl.bufferSubData;
    gl.bufferSubData = function (target, destination, source, sourceOffset = 0, length) {
      if (target === gl.COPY_WRITE_BUFFER && ArrayBuffer.isView(source) && parts.length) {
        const unit = source.BYTES_PER_ELEMENT;
        const count = (length ?? source.length - sourceOffset) * unit;
        const bytes = new Uint8Array(source.buffer, source.byteOffset + sourceOffset * unit, count);
        const part = parts.find(p => {
          if (p.rest.length !== bytes.length) return false;
          for (let i = 0; i < Math.min(64, bytes.length); i++) if (p.rest[i] !== bytes[i]) return false;
          for (let i = Math.max(0, bytes.length - 32); i < bytes.length; i++) if (p.rest[i] !== bytes[i]) return false;
          return true;
        });
        if (part) matched.set(part.name, { gl, buffer: gl.getParameter(gl.COPY_WRITE_BUFFER_BINDING), offset: destination, upload: original });
      }
      return original.apply(this, arguments);
    };
    return gl;
  };
  return {
    setVehicle(packed) {
      matched = new Map(); parts = [];
      const view = new DataView(packed), bytes = new Uint8Array(packed);
      let at = 112;
      for (let i = 0; i < view.getUint32(4, true); i++) {
        const count = view.getUint32(at + 36, true), indices = view.getUint32(at + 40, true);
        const name = new TextDecoder().decode(bytes.subarray(at, at + 32)).replace(/\0.*$/, '');
        const rest = bytes.slice(at + 64, at + 64 + count * 20);
        parts.push({ name, rest, current: rest.slice(), count });
        at += 64 + count * 20 + indices * 4;
      }
      return parts;
    },
    waitForSceneFrame(callback) { reveal = callback; lastProbe = 0; },
    get ready() { return parts.length > 0 && matched.size === parts.length; },
    get matchedCount() { return matched.size; },
    upload(part, first = 0, count = part.count) {
      const binding = matched.get(part.name);
      if (!binding || !binding.buffer || binding.gl.isContextLost()) return false;
      const { gl, buffer, offset, upload } = binding;
      const previous = gl.getParameter(gl.COPY_WRITE_BUFFER_BINDING);
      gl.bindBuffer(gl.COPY_WRITE_BUFFER, buffer);
      upload.call(gl, gl.COPY_WRITE_BUFFER, offset + first * 20, part.current.subarray(first * 20, (first + count) * 20));
      gl.bindBuffer(gl.COPY_WRITE_BUFFER, previous);
      return true;
    },
    reset() { for (const part of parts) { part.current.set(part.rest); this.upload(part); } },
    clear() { parts = []; matched.clear(); },
  };
}
