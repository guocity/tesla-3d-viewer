// Apply a custom wrap texture to the vehicle's CarPaint material in the
// Rive WebGL2 PBR shader, preserving scene lighting, shadows, and clearcoat.
export const WRAP_OPTIONS = [
  { id: 'none', name: 'No Wrap', url: null },
  { id: 'img_6155', name: 'Cybercab', url: new URL('../wraps/IMG_6155.PNG', import.meta.url).href },
  { id: 'my_010838', name: 'Police', url: new URL('../wraps/wrap-my-010838.png', import.meta.url).href },
  { id: 'my_011100', name: 'Labubu', url: new URL('../wraps/wrap-my-011100.png', import.meta.url).href },
];

export function patchWrapShader(source) {
  if (source.includes('uShowroomWrapActive')) return source;
  const vertex = /CarIn (\w+) = CarIn\([^;]+;/;
  const fragment = /VOut \w+ = VOut\(gl_FragCoord[^;]+;/;
  // Only patch the PBR car vertex shader (VOut), never the height/shadow shader (HOut).
  if (source.includes('gl_Position') && vertex.test(source) && /\bVOut\b/.test(source)) {
    return source
      .replace('precision highp int;', 'precision highp int;\nout vec2 vShowroomWrapUV;\nout float vShowroomIsPaint;')
      .replace(
        vertex,
        (declaration, input) =>
          `${declaration}\n    vShowroomWrapUV = ${input}.uv;\n    vShowroomIsPaint = ${input}.ao.w < 0.5 ? 1.0 : 0.0;`
      );
  }
  // Only patch the PBR car fragment shader (has albedo + exposureOut), never fs_glass.
  if (source.includes('gl_Position') || !fragment.test(source) || !/\balbedo\b/.test(source)) return source;
  const albedoPoint = /(\s+vec3 \w+ = albedo;\s+float \w+ = metal;)/;
  if (!albedoPoint.test(source)) return source;
  return source
    .replace(
      'precision highp int;',
      'precision highp int;\nin vec2 vShowroomWrapUV;\nin float vShowroomIsPaint;\nuniform highp sampler2D uShowroomWrap;\nuniform float uShowroomWrapActive;'
    )
    .replace(
      albedoPoint,
      `\n    if (uShowroomWrapActive > 0.5 && vShowroomIsPaint > 0.5 && gl_FrontFacing) {\n      vec4 wrapSample = texture(uShowroomWrap, vShowroomWrapUV);\n      if (wrapSample.a > 0.05) {\n        albedo = mix(albedo, pow(wrapSample.rgb, vec3(2.2)), wrapSample.a);\n      }\n    }\n$1`
    );
}

export function createCarWrap() {
  const contexts = new WeakMap();
  const images = new Map();
  let activeId = 'none';

  function ensureImage(id) {
    if (id === 'none') return null;
    let entry = images.get(id);
    if (!entry) {
      const opt = WRAP_OPTIONS.find(o => o.id === id);
      if (!opt?.url) return null;
      const img = new Image();
      img.src = opt.url;
      entry = { img, textures: new WeakMap() };
      images.set(id, entry);
    }
    return entry;
  }

  return {
    patchShader: patchWrapShader,
    setWrap(id) {
      activeId = WRAP_OPTIONS.some(o => o.id === id) ? id : 'none';
      ensureImage(activeId);
    },
    getWrap() {
      return activeId;
    },
    beforeDraw(gl) {
      const program = gl.getParameter(gl.CURRENT_PROGRAM);
      if (!program) return;
      let state = contexts.get(gl);
      if (!state) {
        state = {
          unit: Math.max(0, gl.getParameter(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS) - 2),
          programs: new WeakMap(),
        };
        contexts.set(gl, state);
      }
      let locations = state.programs.get(program);
      if (locations === undefined) {
        locations = {
          image: gl.getUniformLocation(program, 'uShowroomWrap'),
          active: gl.getUniformLocation(program, 'uShowroomWrapActive'),
        };
        state.programs.set(program, locations);
      }
      if (locations.image === null || locations.active === null) return;

      const entry = activeId !== 'none' ? images.get(activeId) : null;
      const ready = Boolean(entry && entry.img.complete && entry.img.naturalWidth > 0);
      gl.uniform1f(locations.active, ready ? 1.0 : 0.0);

      const previousUnit = gl.getParameter(gl.ACTIVE_TEXTURE);
      gl.activeTexture(gl.TEXTURE0 + state.unit);
      const previousTexture = gl.getParameter(gl.TEXTURE_BINDING_2D);

      let texture;
      if (ready) {
        texture = entry.textures.get(gl);
        if (!texture) {
          texture = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, texture);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
          const flip = gl.getParameter(gl.UNPACK_FLIP_Y_WEBGL);
          gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, entry.img);
          gl.generateMipmap(gl.TEXTURE_2D);
          gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, flip);
          entry.textures.set(gl, texture);
        } else {
          gl.bindTexture(gl.TEXTURE_2D, texture);
        }
      } else {
        if (!state.fallback) {
          state.fallback = gl.createTexture();
          gl.bindTexture(gl.TEXTURE_2D, state.fallback);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
        } else {
          gl.bindTexture(gl.TEXTURE_2D, state.fallback);
        }
      }

      gl.uniform1i(locations.image, state.unit);
      gl.activeTexture(previousUnit);
      return () => {
        gl.activeTexture(gl.TEXTURE0 + state.unit);
        gl.bindTexture(gl.TEXTURE_2D, previousTexture);
        gl.activeTexture(previousUnit);
      };
    },
  };
}
