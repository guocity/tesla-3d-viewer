import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Group, Mesh, BoxGeometry, MeshBasicMaterial, BufferGeometry, Float32BufferAttribute } from 'three';
import { vehicleBodyBounds, groundChargingCable } from '../src/charging-geometry.js';

test('loose cable does not change vehicle bounds or orientation',()=>{
  const root=new Group(),body=new Mesh(new BoxGeometry(2,1,5),new MeshBasicMaterial());root.add(body);
  const anchor=new Group();anchor.name='APK_ChargeCable';root.add(anchor);
  const cable=new Mesh(new BoxGeometry(20,1,1),new MeshBasicMaterial());cable.position.x=10;anchor.add(cable);root.updateMatrixWorld(true);
  const bounds=vehicleBodyBounds(root);
  assert.deepEqual(bounds.min.toArray(),[-1,-.5,-2.5]);assert.deepEqual(bounds.max.toArray(),[1,.5,2.5]);
});

test('cable loose end rests on the floor while the connected end remains fixed',()=>{
  const geometry=new BufferGeometry();geometry.setAttribute('position',new Float32BufferAttribute([2,.3,0,3,.3,0,0,1,0],3));geometry.setAttribute('uv',new Float32BufferAttribute([0,0,.4,0,1,0],2));
  const mesh=new Mesh(geometry,new MeshBasicMaterial());mesh.userData.effect='chargeFlow';
  const root=new Group();root.add(mesh);root.updateMatrixWorld(true);groundChargingCable(root,0);
  const p=geometry.attributes.position;assert.ok(Math.abs(p.getY(0)-.012)<1e-6);assert.ok(Math.abs(p.getY(1)-.012)<1e-6);assert.equal(p.getY(2),1);
});
