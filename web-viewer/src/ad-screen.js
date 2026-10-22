// Replace the authored LED wall's image sampler, preserving its perspective,
// occlusion, LED grid, spill light and floor reflection.
export function patchAdShader(source) {
  if (!/vec3 ledTexF?\(vec2 \w+\)/.test(source)) return source;
  if (source.includes('uniform float uShowroomAdMix;')) return source;
  return source.replace('precision highp int;', 'precision highp int;\nuniform highp sampler2D uShowroomAd;\nuniform float uShowroomAdMix;')
    .replace(/vec3 (ledTexF?)\(vec2 (\w+)\) \{([\s\S]*?)\n\}/g, (_,name,uv,body)=>
      `vec3 ${name}(vec2 ${uv}) {${body.replace(/return ([^;]+);/, (_,original)=>`return mix(${original}, pow(texture(uShowroomAd, ${uv}).rgb, vec3(2.2)), uShowroomAdMix);`)}\n}`);

}
// Keep the original color program for eight seconds, show the ad for eight,
// then cross-fade back. Both phases use the authored monitor/LED rendering.
export function adScreenMix(seconds) {
  const t=((seconds%16)+16)%16;
  if(t<1)return t*t*(3-2*t);
  if(t<7)return 1;
  if(t<8){const f=8-t;return f*f*(3-2*f);}
  return 0;
}
export function createAdScreen() {
  const image=new Image();image.src=new URL('../ads/lgnat.jpg',import.meta.url).href;
  const contexts=new WeakMap(), started=performance.now();
  return {
    patchShader:patchAdShader,
    beforeDraw(gl) {
      if(!image.complete||!image.naturalWidth)return;
      let state=contexts.get(gl);
      if(!state){state={unit:gl.getParameter(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS)-1,programs:new WeakMap()};contexts.set(gl,state);}
      const program=gl.getParameter(gl.CURRENT_PROGRAM);if(!program)return;
      let locations=state.programs.get(program);
      if(locations===undefined){locations={image:gl.getUniformLocation(program,'uShowroomAd'),mix:gl.getUniformLocation(program,'uShowroomAdMix')};state.programs.set(program,locations);}
      if(locations.image===null)return;
      const previousUnit=gl.getParameter(gl.ACTIVE_TEXTURE);
      gl.activeTexture(gl.TEXTURE0+state.unit);
      const previousTexture=gl.getParameter(gl.TEXTURE_BINDING_2D);
      if(!state.texture){
        state.texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,state.texture);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
        const flip=gl.getParameter(gl.UNPACK_FLIP_Y_WEBGL);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,false);
        gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,image);gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL,flip);
      } else gl.bindTexture(gl.TEXTURE_2D,state.texture);
      gl.uniform1i(locations.image,state.unit);gl.uniform1f(locations.mix,adScreenMix((performance.now()-started)/1000));gl.activeTexture(previousUnit);
      return ()=>{gl.activeTexture(gl.TEXTURE0+state.unit);gl.bindTexture(gl.TEXTURE_2D,previousTexture);gl.activeTexture(previousUnit);};
    },
  };
}
