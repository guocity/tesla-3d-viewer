import { Box3, BufferGeometry, CircleGeometry, Float32BufferAttribute, Mesh, SphereGeometry, Vector3 } from 'three';

// Cut the combined side emitters at the lower edge of the authored center DRL.
// Clip intersecting triangles too, so the seam is level rather than diagonal.
export function splitCybertruckRearLamps(root) {
  const center=root.getObjectByName('Headlights_Trunk2');
  if (!center) return false;
  root.updateMatrixWorld(true);
  const height=new Box3().setFromObject(center).min.y;
  const point=new Vector3();
  for(const side of ['Left','Right']) {
    const mesh=root.getObjectByName(`Brake_Lights_${side}2`);
    if(!mesh?.isMesh || root.getObjectByName(`DRL_Rear_${side}2`))continue;
    const source=mesh.geometry, attributes=Object.entries(source.attributes);
    function clipped(upper) {
      const output=Object.fromEntries(attributes.map(([name])=>[name,[]]));
      const count=source.index?.count??source.attributes.position.count;
      for(let i=0;i<count;i+=3) {
        let polygon=[0,1,2].map(j=>{
          const index=source.index?source.index.getX(i+j):i+j;
          const values=Object.fromEntries(attributes.map(([name,a])=>[name,Array.from({length:a.itemSize},(_,k)=>a.array[index*a.itemSize+k])]));
          return {values,y:point.fromArray(values.position).applyMatrix4(mesh.matrixWorld).y};
        });
        const result=[];
        for(let j=0;j<polygon.length;j++) {
          const a=polygon[j],b=polygon[(j+1)%polygon.length];
          const inside=p=>upper?p.y>=height:p.y<=height;
          if(inside(a))result.push(a);
          if(inside(a)!==inside(b)) {
            const f=(height-a.y)/(b.y-a.y);
            result.push({y:height,values:Object.fromEntries(attributes.map(([name])=>[name,a.values[name].map((v,k)=>v+(b.values[name][k]-v)*f)]))});
          }
        }
        for(let j=1;j+1<result.length;j++)for(const p of [result[0],result[j],result[j+1]])for(const [name] of attributes)output[name].push(...p.values[name]);
      }
      const geometry=new BufferGeometry();
      for(const [name,a] of attributes)geometry.setAttribute(name,new Float32BufferAttribute(output[name],a.itemSize));
      return geometry;
    }
    const upper=mesh.clone(false);upper.name=`DRL_Rear_${side}2`;upper.geometry=clipped(true);
    mesh.geometry=clipped(false);mesh.parent.add(upper);source.dispose();
  }
  root.updateMatrixWorld(true);
  return true;
}

// The source illumination atlas turns these broad projector overlays into
// light spots. RCP2 has no source UV atlas, so retain the clear square covers
// and supply round internal emitters instead of making the whole square glow.
export function correctCybertruckFrontLamps(root) {
  if(!root.getObjectByName('Brake_Lights_Trunk2'))return;
  const fixture=root.getObjectByName('Headlights2');
  if(!fixture?.isMesh||fixture.getObjectByName('Headlight_Projector_Left2'))return;
  const emitter=Array.isArray(fixture.material)?fixture.material[0]:fixture.material;
  const cover=emitter.clone();cover.name='glass_clear__Glass_Lights';fixture.material=cover;
  const positions=fixture.geometry.attributes.position, point=new Vector3();
  for(const [side,sign] of [['Left',-1],['Right',1]]) {
    const box=new Box3();
    for(let i=0;i<positions.count;i++) {point.fromBufferAttribute(positions,i);if(point.z*sign>0)box.expandByPoint(point);}
    if(box.isEmpty())continue;
    const size=box.getSize(new Vector3()),center=box.getCenter(new Vector3());
    const projector=new Mesh(new CircleGeometry(Math.min(size.y,size.z)*.38,40),emitter);
    projector.name=`Headlight_Projector_${side}2`;
    projector.rotation.y=Math.PI/2;projector.position.set(box.max.x+.002,center.y,center.z);
    fixture.add(projector);
  }
  root.updateMatrixWorld(true);
}

// Model Y exports an upper front Headlights shell that relied on an illumination
// alpha/emission atlas (Lights_E_Y_High.png). Without the atlas in RCP2, the
// entire headlight housing glows solid white. Strip the broad upper front
// overlay so the dark Lights housing shows through clear Lights_Glass, and
// supply focused internal LED projector bulbs inside each housing.
export function correctModelYFrontLamps(root, vehicleId = '') {
  if (vehicleId !== 'modely_high') return;
  const fixture = root.getObjectByName('Headlights');
  if (!fixture?.isMesh || fixture.getObjectByName('Headlight_Bulb_Inner_Left')) return;
  root.updateMatrixWorld(true);
  const emitter = Array.isArray(fixture.material) ? fixture.material[0] : fixture.material;
  const src = fixture.geometry;
  const count = src.index?.count ?? src.attributes.position.count;
  const point = new Vector3();
  const kept = [];
  for (let i = 0; i < count; i += 3) {
    const tri = [0, 1, 2].map(j => src.index ? src.index.getX(i + j) : i + j);
    let cx = 0, cy = 0;
    for (const idx of tri) {
      point.fromBufferAttribute(src.attributes.position, idx).applyMatrix4(fixture.matrixWorld);
      cx += point.x / 3;
      cy += point.y / 3;
    }
    if (cx <= 1.5 || cy <= 0.6) kept.push(...tri);
  }
  if (src.index) {
    src.setIndex(kept);
  } else {
    const attributes = Object.entries(src.attributes);
    const out = Object.fromEntries(attributes.map(([name]) => [name, []]));
    for (const idx of kept) {
      for (const [name, attr] of attributes) {
        for (let k = 0; k < attr.itemSize; k++) out[name].push(attr.array[idx * attr.itemSize + k]);
      }
    }
    for (const [name, attr] of attributes) src.setAttribute(name, new Float32BufferAttribute(out[name], attr.itemSize));
  }
  src.clearGroups();
  const bulbs = [
    ['Inner', 2.045, 0.780, 0.610],
    ['Outer', 1.975, 0.795, 0.710],
  ];
  const invWorld = fixture.matrixWorld.clone().invert();
  for (const [label, x, y, zAbs] of bulbs) {
    for (const [side, sign] of [['Left', -1], ['Right', 1]]) {
      const bulb = new Mesh(new SphereGeometry(0.022, 24, 16), emitter);
      bulb.name = `Headlight_Bulb_${label}_${side}`;
      bulb.position.set(x, y, zAbs * sign).applyMatrix4(invWorld);
      fixture.add(bulb);
    }
  }
  // Keep the lower turn signal strips dark when not blinking instead of lighting
  // them solid white alongside the inner headlight projector bulbs.
  for (const signalName of ['Left_Turn_Signal', 'Right_Turn_Signal']) {
    const signal = root.getObjectByName(signalName);
    if (!signal?.isMesh) continue;
    const mat = (Array.isArray(signal.material) ? signal.material[0] : signal.material)?.clone();
    if (mat) {
      mat.name = 'trim__Lights';
      signal.material = mat;
    }
  }
  // Keep the rear and roof glass passes intact so factory-tinted glazing stays dark.
  root.updateMatrixWorld(true);
}
