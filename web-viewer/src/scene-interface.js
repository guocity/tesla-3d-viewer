// Modify only the authored Visor's mini-player container. Rive property 18 is
// TransformComponent.opacity; keep every object and reference index intact.
export function hideSceneMedia(source) {
  const bytes = new Uint8Array(source);
  const marker = new Uint8Array([4, 6, 68, 111, 99, 107, 32, 82, 5, 199, 5, 0]);
  let start = -1;
  outer: for (let i = 0; i <= bytes.length - marker.length; i++) {
    for (let j = 0; j < marker.length; j++) if (bytes[i + j] !== marker[j]) continue outer;
    if (start !== -1) throw new Error('The scene media container is ambiguous.');
    start = i;
  }
  if (start < 0) throw new Error('The scene media container has changed.');
  const at = start + marker.length - 1;
  const result = new Uint8Array(bytes.length + 5);
  result.set(bytes.subarray(0, at));
  result.set([18, 0, 0, 0, 0], at);
  result.set(bytes.subarray(at), at + 5);
  return result.buffer;
}

// Hide only the BMW UI roots in their nested artboards. Keep the Garage,
// world script, environment, geometry, lights, reflections and camera intact.
export function hideOriginalMenus(source) {
  let bytes = new Uint8Array(source);
  for (const [name, parent, expected] of [['Panel', 0, 5], ['HUD Inner', 2, 1]]) {
    const text = new TextEncoder().encode(name);
    const marker = new Uint8Array([4, text.length, ...text, 5, parent, 0]);
    const offsets = [];
    outer: for (let i = 0; i <= bytes.length - marker.length; i++) {
      for (let j = 0; j < marker.length; j++) if (bytes[i + j] !== marker[j]) continue outer;
      offsets.push(i + marker.length - 1);
    }
    if (offsets.length !== expected) throw new Error(`The scene ${name} menu roots have changed.`);
    const result = new Uint8Array(bytes.length + offsets.length * 5);
    let start = 0, destination = 0;
    for (const at of offsets) {
      result.set(bytes.subarray(start, at), destination); destination += at - start;
      result.set([18, 0, 0, 0, 0], destination); destination += 5; start = at;
    }
    result.set(bytes.subarray(start), destination); bytes = result;
  }
  return bytes.buffer;
}
