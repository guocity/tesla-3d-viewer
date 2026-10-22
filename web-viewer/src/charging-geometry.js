import { Box3, Matrix4, Vector3 } from 'three';

function isCable(node) {
  for (let at=node;at;at=at.parent) if(at.name==='APK_ChargeCable') return true;
  return false;
}

// A loose cable must not change the car's orientation, center or display scale.
export function vehicleBodyBounds(root) {
  const box=new Box3();
  root.traverseVisible(mesh=>{
    if(!mesh.isMesh||isCable(mesh))return;
    mesh.geometry.computeBoundingBox();
    box.union(mesh.geometry.boundingBox.clone().applyMatrix4(mesh.matrixWorld));
  });
  return box;
}

// The source cable is authored at one port height. Keep its plug fixed and
// lower/raise the loose end to the floor for each vehicle's actual port height.
export function groundChargingCable(root, groundY) {
  const point=new Vector3();
  root.traverse(mesh=>{
    if(!mesh.isMesh||mesh.userData.effect!=='chargeFlow')return;
    const geometry=mesh.geometry,positions=geometry.attributes.position,uv=geometry.attributes.uv;
    if(!uv)return;
    let bottom=Infinity;
    for(let i=0;i<positions.count;i++){
      point.fromBufferAttribute(positions,i).applyMatrix4(mesh.matrixWorld);
      if(uv.getX(i)<.5)bottom=Math.min(bottom,point.y);
    }
    if(!Number.isFinite(bottom))return;
    const shift=groundY+.012-bottom,inverse=new Matrix4().copy(mesh.matrixWorld).invert();
    for(let i=0;i<positions.count;i++){
      const t=Math.max(0,Math.min(1,(uv.getX(i)-.5)/.45));
      const weight=1-t*t*(3-2*t);
      point.fromBufferAttribute(positions,i).applyMatrix4(mesh.matrixWorld);
      point.y+=shift*weight;point.applyMatrix4(inverse);
      positions.setXYZ(i,point.x,point.y,point.z);
    }
    geometry.computeVertexNormals();geometry.computeBoundingBox();
  });
}
