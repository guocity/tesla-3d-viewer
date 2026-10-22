import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Box3, BoxGeometry, BufferGeometry, Float32BufferAttribute, Group, Mesh, MeshBasicMaterial } from 'three';
import { splitCybertruckRearLamps, correctCybertruckFrontLamps } from '../src/cybertruck-optics.js';
import { sceneMaterial } from '../src/vehicle-materials.js';

test('side fixtures are clipped into upper red DRL and lower red brakes at center-strip height', () => {
  const root=new Group(), material=new MeshBasicMaterial();
  const center=new Mesh(new BoxGeometry(1,.2,.1),material);center.name='Headlights_Trunk2';center.position.y=1;root.add(center);
  for(const side of ['Left','Right']) {
    const geometry=new BufferGeometry();geometry.setAttribute('position',new Float32BufferAttribute([0,.8,0,1,1.2,0,0,1.2,0],3));geometry.computeVertexNormals();
    const mesh=new Mesh(geometry,material);mesh.name=`Brake_Lights_${side}2`;root.add(mesh);
  }
  assert.equal(splitCybertruckRearLamps(root),true);
  const seam=new Box3().setFromObject(center).min.y;
  for(const side of ['Left','Right']) {
    const upper=root.getObjectByName(`DRL_Rear_${side}2`),lower=root.getObjectByName(`Brake_Lights_${side}2`);
    assert.ok(new Box3().setFromObject(upper).min.y>=seam-1e-6);
    assert.ok(new Box3().setFromObject(lower).max.y<=seam+1e-6);
    assert.ok(upper.geometry.attributes.position.count>0&&lower.geometry.attributes.position.count>0);
    assert.equal(sceneMaterial('headlight__Illumination',upper.name,true),'LightRed');
    assert.equal(sceneMaterial('headlight__Illumination',lower.name,true),'LightRed');
  }
  const count=root.children.length;splitCybertruckRearLamps(root);assert.equal(root.children.length,count);
});

test('front lamp housings are clear while the internal emitters stay white', () => {
  assert.equal(sceneMaterial('headlight__Lights1','Lights2',false),'GlassWhite');
  assert.equal(sceneMaterial('headlight__Illumination','Headlights2',false),'Light');
});

test('front fixture retains clear square covers with round internal projector meshes', () => {
  const root=new Group(),fixture=new Mesh(new BoxGeometry(.06,.07,1.2),new MeshBasicMaterial());
  fixture.name='Headlights2';root.add(fixture);const marker=new Group();marker.name='Brake_Lights_Trunk2';root.add(marker);
  correctCybertruckFrontLamps(root);
  assert.equal(fixture.material.name,'glass_clear__Glass_Lights');
  for(const side of ['Left','Right']){const emitter=fixture.getObjectByName(`Headlight_Projector_${side}2`);assert.ok(emitter);assert.equal(emitter.geometry.type,'CircleGeometry');}
});
