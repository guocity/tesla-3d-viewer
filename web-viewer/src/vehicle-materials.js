// APK materials are shared between front and rear lamps; node names distinguish them.
export function sceneMaterial(materialName, nodeName = '') {
  const name = materialName.toLowerCase();
  const part = nodeName.toLowerCase();
  // Reverse lamps are not continuously illuminated in the parked showroom.
  if (/headlights?_trunk|reverse[_ .-]*(lights?|lamps?)/.test(part)) return 'MetallicWhite';
  if (/(?:brake|tail|rear)[_ .-]*(?:lights?|lamps?)|(?:lights?|lamps?)[_ .-]*(?:rear|trunk)/.test(part)) return /off/.test(part) ? 'GlassRed' : 'LightRed';
  if (/glass/.test(name)) return 'GlassBlack';
  if (/taillight|light.*red/.test(name)) return 'LightRed';
  if (/headlight|light.*white/.test(name)) return 'Light';
  if (/mirror/.test(name)) return 'Mirror';
  if (/tire|rubber|interior|seat|carpet|trim|plastic/.test(name)) return 'BottomCar';
  if (/paint/.test(name) && !/black|rough/.test(name)) return 'CarPaint';
  if (/chrome|metal|rim|wheel/.test(name)) return 'MetallicGray';
  return 'MetallicBlack02';
}
