// APK materials are shared between front and rear lamps; node names distinguish them.
export function sceneMaterial(materialName, nodeName = '', rear = false) {
  const name = materialName.toLowerCase();
  const part = nodeName.toLowerCase();
  const lamp = /^(?:headlight|taillight)(?:__|$)|^trim__(?:lights?|brake)(?:_|$)|^trim__turnsignal.*brakes|^glass(?:_clear)?__glass_lights/.test(name);
  const rearName = /(?:brake|tail|rear|back)[_ .-]*(?:lights?|lamps?)|(?:lights?|lamps?)[_ .-]*(?:rear|trunk)|lights?_spoiler/.test(part);
  // Several APK meshes called "Headlights" contain both front and rear lamps.
  // Conversion supplies the triangle's vehicle-space location for these meshes.
  // Clear lamp covers use the scene's transparent clear-glass material.
  // Keep this separate from tinted cabin glazing and emissive lamp geometry.
  if (/charge[_ .-]*(?:cap|port)|chargeport/.test(part) && lamp) return 'MetallicBlack02';
  if (name === 'headlight__lights1') return 'GlassWhite';
  if (/^glass(?:_clear)?__glass_lights/.test(name)) return 'GlassWhite';
  if (lamp && (rear || rearName)) {
    const emitter = /illumination/.test(name) || /^trim__turnsignal.*brakes/.test(name) || /^trim__light$/.test(name) && /brake|(?:lights?|signal).*on|parking_lights/.test(part);
    // The red GlassRed preset adds 35% tint on every overlapping surface.
    // Lamp covers must use the clear 2% preset, with red confined to emitters.
    return emitter && !/off/.test(part) ? 'LightRed' : 'GlassWhite';
  }
  if (/^trim__light$/.test(name) && /^(?:headlights?_on|drl)(?:_|$)/.test(part)) return 'Light';
  if (/glass/.test(name)) return 'GlassBlack';
  if (/taillight|light.*red/.test(name)) return 'LightRed';
  if (/headlight|light.*white/.test(name)) return 'Light';
  if (/mirror/.test(name)) return 'Mirror';
  if (/tire|rubber|interior|seat|carpet|trim|plastic/.test(name)) return 'BottomCar';
  if (/paint/.test(name) && !/black|rough/.test(name)) return 'CarPaint';
  if (/chrome|metal|rim|wheel/.test(name)) return 'MetallicGray';
  return 'MetallicBlack02';
}
