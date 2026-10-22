// Tesla APK: mobile/materials/PowerflowSingle.shader, flow_state = 1.
// Original cable UV.x increases from its loose end toward the charging handle.
export function chargingFlowAmount(seconds, cableUV) {
  const phase = seconds / 1.5 - cableUV / 1.5;
  const wrapped = phase - Math.floor(phase);
  const leading = Math.min(1, wrapped / .08);
  return (1 - wrapped) ** 2 * leading * leading * (3 - 2 * leading);
}

export function patchChargingFlowShader(source) {
  if (source.includes('vShowroomChargeUV')) return source;
  const vertex = /CarIn (\w+) = CarIn\([^;]+;/;
  const fragment = /VOut \w+ = VOut\(gl_FragCoord[^;]+;/;
  if (source.includes('gl_Position') && vertex.test(source)) {
    return source.replace('precision highp int;', 'precision highp int;\nout float vShowroomChargeUV;')
      .replace(vertex, (declaration, input) => `${declaration}\n    vShowroomChargeUV = ${input}.ao.z < 0.5 ? ${input}.ao.y : -1.0;`);
  }
  if (!fragment.test(source)) return source;
  return source.replace('precision highp int;', 'precision highp int;\nin float vShowroomChargeUV;\nuniform float uShowroomChargeTime;\nuniform float uShowroomChargeActive;')
    .replace(/(\s+vec3 \w+ = c;\s+vec4 \w+ = exposureOut\()/, `
    if (vShowroomChargeUV >= 0.0 && uShowroomChargeActive > 0.5) {
      float chargePhase = fract(uShowroomChargeTime / 1.5 - vShowroomChargeUV / 1.5);
      float chargeFlow = pow(1.0 - chargePhase, 2.0) * smoothstep(0.0, 0.08, chargePhase);
      c = c * (1.0 - chargeFlow) * 0.2 + vec3(0.0, 1.0, 0.0) * chargeFlow;
    }
$1`);
}

export function createChargingFlow(now = () => performance.now()) {
  const programs = new WeakMap();
  let active = false, started = 0;
  return {
    setActive(on) {
      if (on && !active) started = now();
      active = on;
    },
    beforeDraw(gl) {
      const program = gl.getParameter(gl.CURRENT_PROGRAM);
      if (!program) return;
      let locations = programs.get(program);
      if (locations === undefined) {
        locations = { time: gl.getUniformLocation(program, 'uShowroomChargeTime'), active: gl.getUniformLocation(program, 'uShowroomChargeActive') };
        programs.set(program, locations);
      }
      if (locations.time == null) return;
      gl.uniform1f(locations.time, active ? ((now() - started) / 1000) % 1.5 : 0);
      gl.uniform1f(locations.active, Number(active));
    },
  };
}
