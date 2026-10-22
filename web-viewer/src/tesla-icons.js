import sheet from './assets/icons/tesla-reference.png?url';
// Luminance masks crop the user's original sheet in CSS; no redrawing or
// opaque black image tiles, and icons inherit the active control's color.
const crops={
  controls:[747,354,110,76], fan:[750,551,104,104], defrost:[1042,553,104,104],
  charging:[467,778,96,96], wordmark:[745,214,114,28],
};
export function teslaIcon(name,size=23) {
  const [x,y,w,h]=crops[name];
  return `<span class="tesla-reference-icon" aria-hidden="true" style="width:${size}px;height:${size*h/w}px;mask-image:url('${sheet}');mask-mode:luminance;mask-repeat:no-repeat;mask-size:${1600*size/w}px ${1200*size/w}px;mask-position:${-x*size/w}px ${-y*size/w}px"></span>`;
}
