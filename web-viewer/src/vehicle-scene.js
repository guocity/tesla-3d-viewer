import { vehicleBodyBounds, groundChargingCable } from './charging-geometry.js';
import { splitCybertruckRearLamps, correctCybertruckFrontLamps } from './cybertruck-optics.js';
import { Box3, Matrix3, Matrix4, Vector3 } from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

import { replaceVehicleBlob } from './scene-buffer.js';
export { replaceVehicleBlob };
const encoder = new TextEncoder();
const MAGIC = encoder.encode('RCP2');

import { sceneMaterial, wheelCoverMaterial } from './vehicle-materials.js';

function octNormal(n) {
  const d = Math.abs(n.x) + Math.abs(n.y) + Math.abs(n.z) || 1;
  let x = n.x / d, y = n.y / d;
  if (n.z < 0) {
    const oldX = x;
    x = (1 - Math.abs(y)) * (oldX >= 0 ? 1 : -1);
    y = (1 - Math.abs(oldX)) * (y >= 0 ? 1 : -1);
  }
  return [Math.round(x * 32767), Math.round(y * 32767)];
}

export async function convertVehicle(url, { includeRig = false } = {}) {
  const loader = new GLTFLoader();
  const gltf = url instanceof ArrayBuffer ? await loader.parseAsync(url, '') : await loader.loadAsync(url);
  const root = gltf.scene;
  try {
    splitCybertruckRearLamps(root);
    correctCybertruckFrontLamps(root);
    root.updateMatrixWorld(true);
    let box = vehicleBodyBounds(root);
    let size = box.getSize(new Vector3());
    // APK models can use X or Z for the long axis; Rive's car faces +Z.
    if (size.x > size.z * 1.25) {
      root.rotation.y += Math.PI / 2;
      root.updateMatrixWorld(true);
      box = vehicleBodyBounds(root);
      size = box.getSize(new Vector3());
    }
    groundChargingCable(root, box.min.y);
    const center = box.getCenter(new Vector3());
    // Fit the same display footprint. Preserve each car's proportions.
    const scale = 5.11564 / Math.max(size.z, size.x);
    const quant = [size.x * scale * 1.5 + 0.001, size.y * scale * 2 + 0.001, size.z * scale + 0.001];
    // Quantization must also contain the cable beyond the body footprint.
    const fullBox = new Box3().setFromObject(root);
    quant[0]=Math.max(quant[0],Math.max(Math.abs(fullBox.min.x-center.x),Math.abs(fullBox.max.x-center.x))*scale+.001);
    quant[1]=Math.max(quant[1],Math.max(Math.abs(fullBox.min.y-box.min.y),Math.abs(fullBox.max.y-box.min.y))*scale+.001);
    quant[2]=Math.max(quant[2],Math.max(Math.abs(fullBox.min.z-center.z),Math.abs(fullBox.max.z-center.z))*scale+.001);
    const rearAxis = size.x > size.z ? 0 : 2;
    const rearSign = rearAxis === 0 ? -1 : 1;
    const meshes = [];
    const materialOrder = new Map();
    root.traverse(mesh => {
      if (!mesh.isMesh || !mesh.visible) return;
      const geometry = mesh.geometry;
      if (!geometry.getAttribute('normal')) geometry.computeVertexNormals();
      const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      const groups = geometry.groups.length ? geometry.groups : [{ start: 0, count: geometry.index?.count ?? geometry.attributes.position.count, materialIndex: 0 }];
      for (const group of groups) {
        const material = materials[group.materialIndex ?? 0];
        if (!material || material.opacity === 0 || group.count === 0) continue;
        // Material names alone cannot distinguish combined front/rear light
        // meshes. Split their triangle indices, preserving source vertices and
        // node bindings so doors and liftgates keep their original animation.
        const buckets = new Map();
        const point = new Vector3();
        for (let i = group.start; i < group.start + group.count; i += 3) {
          const indices = [0, 1, 2].map(j => geometry.index ? geometry.index.getX(i + j) : i + j);
          let longitudinal = 0;
          for (const index of indices) longitudinal += point.fromBufferAttribute(geometry.attributes.position, index).applyMatrix4(mesh.matrixWorld).getComponent(rearAxis) / 3;
          // Imported scene roots can retain a fixed matrix: classify on the
          // actual world-space long axis, not an assumed applied rotation.
          const rear = (longitudinal - center.getComponent(rearAxis)) * rearSign > size.getComponent(rearAxis) * 0.2;
          const originalName = sceneMaterial(material.name, mesh.name, rear);
          if (!materialOrder.has(originalName)) materialOrder.set(originalName, materialOrder.size);
          const name = wheelCoverMaterial(material.name, mesh.name) ?? originalName;
          if (!buckets.has(name)) buckets.set(name, []);
          buckets.get(name).push(...indices);
        }
        for (const [name, indices] of buckets) meshes.push({ mesh, geometry, group: { start: 0, count: indices.length, indices }, name });
      }
    });
    // Preserve the original material batch order when covers move to BottomCar.
    meshes.sort((a, b) => (materialOrder.get(a.name) ?? Infinity) - (materialOrder.get(b.name) ?? Infinity));
    const lengths = meshes.map(({ geometry, group }) => 64 + geometry.attributes.position.count * 20 + group.count * 4);
    const buffer = new ArrayBuffer(112 + lengths.reduce((a, b) => a + b, 0));
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    bytes.set(MAGIC);
    view.setUint32(4, meshes.length, true);
    quant.forEach((value, i) => view.setFloat32(8 + i * 4, value, true));
    // Wheel pivots are intentionally unbound: the reference's BMW articulation
    // does not describe the Tesla source meshes. Whole-car orbit remains native.
    view.setUint32(32, 4, true);
    // The RCP2 header carries four 16-byte wheel records even for static cars.
    for (let i = 0; i < 4; i++) {
      view.setFloat32(48 + i * 16, (i % 2 ? 1 : -1) * quant[0] * 0.8, true);
      view.setFloat32(52 + i * 16, 0.39, true);
      view.setFloat32(56 + i * 16, (i < 2 ? 1 : -1) * quant[2] * 0.6, true);
      view.setFloat32(60 + i * 16, 0.39, true);
    }
    const p = new Vector3(), normal = new Vector3();
    let offset = 112;
    for (const { mesh, geometry, group, name } of meshes) {
      const positions = geometry.attributes.position;
      const normals = geometry.attributes.normal;
      const normalMatrix = new Matrix3().getNormalMatrix(mesh.matrixWorld);
      bytes.set(encoder.encode(name), offset);
      view.setUint32(offset + 36, positions.count, true);
      view.setUint32(offset + 40, group.count, true);
      // Preserve the APK cable flow coordinate in spare color channels.
      // It stays independent of the showroom material texture transforms.
      const flowUV = mesh.userData.effect === 'chargeFlow' ? geometry.attributes.uv : null;
      let at = offset + 64;
      for (let i = 0; i < positions.count; i++, at += 20) {
        p.fromBufferAttribute(positions, i).applyMatrix4(mesh.matrixWorld);
        p.set((p.x - center.x) * scale, (p.y - box.min.y) * scale, (p.z - center.z) * scale);
        [p.x, p.y, p.z].forEach((value, axis) => view.setInt16(at + axis * 2, Math.max(-32767, Math.min(32767, Math.round(value / quant[axis] * 32767))), true));
        normal.fromBufferAttribute(normals, i).applyNormalMatrix(normalMatrix);
        const oct = octNormal(normal);
        view.setInt16(at + 8, oct[0], true);
        view.setInt16(at + 10, oct[1], true);
        bytes.set([255, 255, 255, 255], at + 16);
        if (flowUV) {
          bytes[at + 17] = Math.round(Math.max(0, Math.min(1, flowUV.getX(i))) * 255);
          bytes[at + 18] = 0;
        }
      }
      const reverse = mesh.matrixWorld.determinant() < 0;
      for (let i = 0; i < group.count; i += 3) {
        for (let j = 0; j < 3; j++) {
          const index = group.start + i + (reverse && j > 0 ? 3 - j : j);
          view.setUint32(at, group.indices ? group.indices[index] : geometry.index ? geometry.index.getX(index) : index, true);
          at += 4;
        }
      }
      offset = at;
    }
    const packed = mergeMaterialMeshes(buffer);
    if (!includeRig) return packed;
    const nodeObjects = [];
    root.traverse(node => nodeObjects.push(node));
    const nodeIndices = new Map(nodeObjects.map((node, i) => [node, i]));
    const nodes = nodeObjects.map(node => ({ name: node.name, parent: nodeIndices.get(node.parent) ?? -1, matrix: node.matrix.toArray() }));
    const counts = new Map(), segments = [];
    for (const { mesh, geometry, name } of meshes) {
      const first = counts.get(name) || 0;
      segments.push({ material: name, node: nodeIndices.get(mesh), first, count: geometry.attributes.position.count });
      counts.set(name, first + geometry.attributes.position.count);
    }
    const normalize = new Matrix4().makeScale(scale, scale, scale);
    normalize.setPosition(-center.x * scale, -box.min.y * scale, -center.z * scale);
    return { packed, rig: { version: 1, nodes, segments, normalize: normalize.toArray(), quant } };
  } finally {
    const textures = new Set(), materials = new Set(), geometries = new Set();
    root.traverse(mesh => {
      if (!mesh.isMesh) return;
      geometries.add(mesh.geometry);
      for (const material of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
        materials.add(material);
        for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
      }
    });
    textures.forEach(t => t.dispose());
    materials.forEach(m => m.dispose());
    geometries.forEach(g => g.dispose());
  }
}

// The authored scene identifies parts by material name. Merge disconnected GLB
// primitives into one buffer per material, matching its original vehicle layout.
function mergeMaterialMeshes(buffer) {
  const source = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const groups = new Map();
  let at = 112;
  for (let i = 0; i < source.getUint32(4, true); i++) {
    const name = new TextDecoder().decode(bytes.subarray(at, at + 32)).replace(/\0.*$/, '');
    const vertices = source.getUint32(at + 36, true);
    const indices = source.getUint32(at + 40, true);
    if (!groups.has(name)) groups.set(name, []);
    groups.get(name).push({ at, vertices, indices });
    at += 64 + vertices * 20 + indices * 4;
  }
  const result = new Uint8Array(buffer.byteLength - (source.getUint32(4, true) - groups.size) * 64);
  const target = new DataView(result.buffer);
  result.set(bytes.subarray(0, 112));
  target.setUint32(4, groups.size, true);
  at = 112;
  for (const pieces of groups.values()) {
    const vertexCount = pieces.reduce((n, p) => n + p.vertices, 0);
    const indexCount = pieces.reduce((n, p) => n + p.indices, 0);
    result.set(bytes.subarray(pieces[0].at, pieces[0].at + 64), at);
    target.setUint32(at + 36, vertexCount, true);
    target.setUint32(at + 40, indexCount, true);
    let vertexOffset = 0;
    let indexOffset = at + 64 + vertexCount * 20;
    for (const piece of pieces) {
      const start = piece.at + 64;
      result.set(bytes.subarray(start, start + piece.vertices * 20), at + 64 + vertexOffset * 20);
      for (let i = 0; i < piece.indices; i++, indexOffset += 4) {
        target.setUint32(indexOffset, source.getUint32(start + piece.vertices * 20 + i * 4, true) + vertexOffset, true);
      }
      vertexOffset += piece.vertices;
    }
    at += 64 + vertexCount * 20 + indexCount * 4;
  }
  return result.buffer;
}
