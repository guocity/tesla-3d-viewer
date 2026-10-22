const encoder = new TextEncoder();
const MAGIC = encoder.encode('RCP2');

function findBytes(bytes, pattern) {
  outer: for (let i = 0; i <= bytes.length - pattern.length; i++) {
    for (let j = 0; j < pattern.length; j++) if (bytes[i + j] !== pattern[j]) continue outer;
    return i;
  }
  return -1;
}

function varint(value) {
  const result = [];
  do {
    const digit = value & 127;
    value = Math.floor(value / 128);
    result.push(digit | (value ? 128 : 0));
  } while (value);
  return new Uint8Array(result);
}

// RCP2 is the original scene's vehicle buffer: 112-byte header, then meshes
// with 64-byte headers, 20-byte quantized vertices and uint32 triangle indices.
// Preserve the scene's scripts, shaders, lighting, floor and dashboard verbatim.
export function replaceVehicleBlob(source, replacement, teslaCaption = true) {
  const bytes = new Uint8Array(source);
  const start = findBytes(bytes, MAGIC);
  if (start < 0) throw new Error('The reference scene has no supported vehicle buffer.');
  const view = new DataView(source);
  const count = view.getUint32(start + 4, true);
  let end = start + 112;
  for (let i = 0; i < count; i++) {
    if (end + 64 > bytes.length) throw new Error('Invalid reference vehicle header.');
    const vertices = view.getUint32(end + 36, true);
    const indices = view.getUint32(end + 40, true);
    end += 64 + vertices * 20 + indices * 4;
  }
  if (end > bytes.length) throw new Error('Invalid reference vehicle length.');
  const oldLength = varint(end - start);
  const lengthStart = start - oldLength.length;
  if (!oldLength.every((v, i) => bytes[lengthStart + i] === v)) {
    throw new Error('The reference vehicle framing has changed.');
  }
  const length = varint(replacement.byteLength);
  const result = new Uint8Array(lengthStart + length.length + replacement.byteLength + bytes.length - end);
  result.set(bytes.subarray(0, lengthStart));
  result.set(length, lengthStart);
  result.set(new Uint8Array(replacement), lengthStart + length.length);
  result.set(bytes.subarray(end), lengthStart + length.length + replacement.byteLength);

  // Keep the authored string byte lengths and Rive property framing intact.
  const bmw = encoder.encode('BMW XM');
  const tesla = encoder.encode('TESLA ');
  let offset;
  while (teslaCaption && (offset = findBytes(result, bmw)) >= 0) result.set(tesla, offset);
  return result.buffer;
}

