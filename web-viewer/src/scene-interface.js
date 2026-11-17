function findMarker(bytes, marker, from = 0) {
  const first = marker[0], len = marker.length, limit = bytes.length - len;
  for (let i = from; (i = bytes.indexOf(first, i)) !== -1 && i <= limit; i++) {
    let match = true;
    for (let j = 1; j < len; j++) {
      if (bytes[i + j] !== marker[j]) { match = false; break; }
    }
    if (match) return i;
  }
  return -1;
}

// Modify only the authored Visor's mini-player container. Rive property 18 is
// TransformComponent.opacity; keep every object and reference index intact.
export function hideSceneMedia(source) {
  const bytes = new Uint8Array(source);
  const marker = new Uint8Array([4, 6, 68, 111, 99, 107, 32, 82, 5, 199, 5, 0]);
  const start = findMarker(bytes, marker);
  if (start < 0) throw new Error('The scene media container has changed.');
  if (findMarker(bytes, marker, start + 1) >= 0) throw new Error('The scene media container is ambiguous.');
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
    for (let i = 0; (i = findMarker(bytes, marker, i)) >= 0; i++) offsets.push(i + marker.length - 1);
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

// Collapse the old fan, steering and headlight hit targets, not just their
// opacity: invisible Rive nodes would otherwise still accept clicks.
export function disableVehicleHotspots(source) {
  const bytes = new Uint8Array(source), positions = [];
  for (const name of ['Pin 0', 'Pin 1', 'Pin 2', 'Pin 3']) {
    const marker = new Uint8Array([4, name.length, ...new TextEncoder().encode(name), 5, 34, 0]);
    const found = findMarker(bytes, marker);
    if (found < 0) throw new Error(`Missing ${name} hotspot`);
    if (findMarker(bytes, marker, found + 1) >= 0) throw new Error(`Ambiguous ${name} hotspot`);
    positions.push(found + marker.length - 1);
  }
  positions.sort((a,b)=>a-b);
  const result = new Uint8Array(bytes.length + positions.length * 10);
  let start=0, at=0;
  for (const position of positions) {
    result.set(bytes.subarray(start,position),at); at += position-start;
    result.set([16,0,0,0,0,17,0,0,0,0],at); at+=10; start=position;
  }
  result.set(bytes.subarray(start),at); return result.buffer;
}

// Collapse the Rive wordmark, brandmark, and Intro splash overlay so no Rive logo or bootup screen appears.
export function hideRiveBranding(source) {
  let bytes = new Uint8Array(source);
  for (const [name, parent, expected] of [['Intro', 0, 1], ['RIVE_Wordmark_ROOT', 0, 2], ['NuRiveWordmark01', 2, 1], ['NuRiveBrandmark01', 2, 1]]) {
    const text = new TextEncoder().encode(name);
    const marker = new Uint8Array([4, text.length, ...text, 5, parent, 0]);
    const offsets = [];
    for (let i = 0; (i = findMarker(bytes, marker, i)) >= 0; i++) offsets.push(i + marker.length - 1);
    if (offsets.length !== expected) throw new Error(`The scene ${name} branding roots have changed.`);
    const result = new Uint8Array(bytes.length + offsets.length * 10);
    let start = 0, destination = 0;
    for (const at of offsets) {
      result.set(bytes.subarray(start, at), destination); destination += at - start;
      result.set([16, 0, 0, 0, 0, 17, 0, 0, 0, 0], destination); destination += 10; start = at;
    }
    result.set(bytes.subarray(start), destination); bytes = result;
  }
  return bytes.buffer;
}
