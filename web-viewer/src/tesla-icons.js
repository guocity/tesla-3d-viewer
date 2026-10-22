import sheet from './assets/icons/tesla-reference-alpha.png?url';
// The reference sheet's luminance is baked into alpha for Safari, including
// versions that ignore mask-mode on PNGs. Both mask syntaxes use the same crop.
const crops={
  controls:[747,354,110,76], fan:[750,551,104,104], defrost:[1042,553,104,104],
  charging:[467,778,96,96], wordmark:[745,214,114,28],
};
export function teslaIcon(name,size=23) {
  const [x,y,w,h]=crops[name];
  const mask = `url('${sheet}') ${-x*size/w}px ${-y*size/w}px / ${1600*size/w}px ${1200*size/w}px no-repeat`;
  return `<span class="tesla-reference-icon" aria-hidden="true" style="width:${size}px;height:${size*h/w}px;-webkit-mask:${mask};mask:${mask};mask-mode:alpha"></span>`;
}
