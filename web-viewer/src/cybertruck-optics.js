import { Box3, BufferGeometry, CircleGeometry, Float32BufferAttribute, Mesh, Vector3 } from 'three';

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
