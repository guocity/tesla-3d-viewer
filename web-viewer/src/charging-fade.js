// Cable vertices alone reserve the lower half of the AO byte for opacity.
// Other Tesla vertices stay at 255. Restore AO after the opacity test so a
// fading plug keeps its original lighting and shape in the existing scene.
export function chargingOpacity(progress) {
  const t = Math.max(0, Math.min(1, progress));
  return t * t * (3 - 2 * t);
}

export function patchChargingFadeShader(source) {
  if (source.includes('float chargeOpacity =')) return source;
  if (!source.includes('gl_FragCoord') || !source.includes('float ao;')) return source;
  return source.replace(/(VOut (\w+) = VOut\(gl_FragCoord[^;]+;)/, (_, declaration, input) => `${declaration}
    if (${input}.ao < 0.5) {
      float chargeOpacity = ${input}.ao * (255.0 / 127.0);
      float coverage = fract(sin(dot(floor(gl_FragCoord.xy), vec2(12.9898, 78.233))) * 43758.5453);
      if (coverage >= chargeOpacity) discard;
      ${input}.ao = 1.0;
    }
  `);
}
