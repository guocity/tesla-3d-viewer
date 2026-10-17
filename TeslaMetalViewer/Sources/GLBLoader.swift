import Foundation
import Metal
import simd

public struct RaytraceVertex {
    public var position: SIMD4<Float> // xyz = position, w = 1.0
    public var normal: SIMD4<Float>   // xyz = normal, w = 0.0
    
    public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
        self.position = SIMD4<Float>(position.x, position.y, position.z, 1.0)
        self.normal = SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)
    }
}

public struct GeometryData {
    public var vertices: [RaytraceVertex] = []
    public var indices: [UInt32] = []
    public var baseColor: SIMD3<Float> = SIMD3<Float>(0.5, 0.5, 0.5)
    public var metallic: Float = 0.5
    public var roughness: Float = 0.3
    public var clearcoat: Float = 0.0
    public var emissive: Float = 0.0
    public var transmission: Float = 0.0
    public var isGround: UInt32 = 0
    public var isPaint: UInt32 = 0
}

public struct ModelSceneData {
    public var geometries: [GeometryData] = []
    public var boundsMin: SIMD3<Float> = .zero
    public var boundsMax: SIMD3<Float> = .zero
    public var radius: Float = 3.0
    public var center: SIMD3<Float> = .zero
    public var totalTriangles: Int = 0
    public var totalVertices: Int = 0
}

public class GLBLoader {
    public static func loadModel(from url: URL, device: MTLDevice) -> ModelSceneData? {
        guard let data = try? Data(contentsOf: url), data.count > 20 else { return nil }
        
        let jsonLen = Int(data[12..<16].withUnsafeBytes { $0.load(as: UInt32.self) })
        let jsonBytes = data[20..<(20 + jsonLen)]
        guard let json = try? JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any] else { return nil }
        
        let binOffset = 20 + jsonLen + 8
        guard data.count >= binOffset else { return nil }
        let binData = data.subdata(in: binOffset..<data.count)
        
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let materials = json["materials"] as? [[String: Any]] ?? []
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        let sceneIdx = json["scene"] as? Int ?? 0
        let rootNodes = scenes.count > sceneIdx ? (scenes[sceneIdx]["nodes"] as? [Int] ?? []) : Array(0..<nodes.count)
        
        func readFloat3(accessorIdx: Int) -> [SIMD3<Float>] {
            guard accessorIdx < accessors.count else { return [] }
            let acc = accessors[accessorIdx]
            guard let count = acc["count"] as? Int,
                  let bvIdx = acc["bufferView"] as? Int,
                  bvIdx < bufferViews.count else { return [] }
            let bv = bufferViews[bvIdx]
            let accOffset = acc["byteOffset"] as? Int ?? 0
            let bvOffset = bv["byteOffset"] as? Int ?? 0
            let stride = bv["byteStride"] as? Int ?? (3 * MemoryLayout<Float>.size)
            let totalOffset = bvOffset + accOffset
            
            var res = [SIMD3<Float>](repeating: .zero, count: count)
            binData.withUnsafeBytes { raw in
                guard totalOffset + count * stride <= binData.count else { return }
                let base = raw.baseAddress!.advanced(by: totalOffset)
                for i in 0..<count {
                    let p = base.advanced(by: i * stride).assumingMemoryBound(to: Float.self)
                    res[i] = SIMD3<Float>(p[0], p[1], p[2])
                }
            }
            return res
        }
        
        func readIndices(accessorIdx: Int) -> [UInt32] {
            guard accessorIdx < accessors.count else { return [] }
            let acc = accessors[accessorIdx]
            guard let count = acc["count"] as? Int,
                  let compType = acc["componentType"] as? Int,
                  let bvIdx = acc["bufferView"] as? Int,
                  bvIdx < bufferViews.count else { return [] }
            let bv = bufferViews[bvIdx]
            let accOffset = acc["byteOffset"] as? Int ?? 0
            let bvOffset = bv["byteOffset"] as? Int ?? 0
            let totalOffset = bvOffset + accOffset
            
            var res = [UInt32](repeating: 0, count: count)
            binData.withUnsafeBytes { raw in
                guard totalOffset < binData.count else { return }
                let base = raw.baseAddress!.advanced(by: totalOffset)
                if compType == 5123 { // UNSIGNED_SHORT
                    let p = base.assumingMemoryBound(to: UInt16.self)
                    for i in 0..<count { res[i] = UInt32(p[i]) }
                } else if compType == 5125 { // UNSIGNED_INT
                    let p = base.assumingMemoryBound(to: UInt32.self)
                    for i in 0..<count { res[i] = p[i] }
                } else if compType == 5121 { // UNSIGNED_BYTE
                    let p = base.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<count { res[i] = UInt32(p[i]) }
                }
            }
            return res
        }
        
        func localMatrix(node: [String: Any]) -> simd_float4x4 {
            if let m = node["matrix"] as? [Double], m.count == 16 {
                return simd_float4x4(
                    SIMD4<Float>(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3])),
                    SIMD4<Float>(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7])),
                    SIMD4<Float>(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11])),
                    SIMD4<Float>(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))
                )
            }
            var mat = matrix_identity_float4x4
            if let t = node["translation"] as? [Double], t.count == 3 {
                mat.columns.3 = SIMD4<Float>(Float(t[0]), Float(t[1]), Float(t[2]), 1.0)
            }
            if let r = node["rotation"] as? [Double], r.count == 4 {
                let q = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
                mat = mat * simd_matrix4x4(q)
            }
            if let s = node["scale"] as? [Double], s.count == 3 {
                let sMat = simd_float4x4(diagonal: SIMD4<Float>(Float(s[0]), Float(s[1]), Float(s[2]), 1.0))
                mat = mat * sMat
            }
            return mat
        }
        
        var worldTransforms = [simd_float4x4](repeating: matrix_identity_float4x4, count: nodes.count)
        func computeWorld(idx: Int, parent: simd_float4x4) {
            guard idx < nodes.count else { return }
            let node = nodes[idx]
            let local = localMatrix(node: node)
            let world = parent * local
            worldTransforms[idx] = world
            if let children = node["children"] as? [Int] {
                for c in children { computeWorld(idx: c, parent: world) }
            }
        }
        for r in rootNodes { computeWorld(idx: r, parent: matrix_identity_float4x4) }
        
        struct RawPrimitive {
            var positions: [SIMD3<Float>]
            var normals: [SIMD3<Float>]
            var indices: [UInt32]
            var matCategory: Int
        }
        
        var rawPrims: [RawPrimitive] = []
        var bMin = SIMD3<Float>(repeating: .infinity)
        var bMax = SIMD3<Float>(repeating: -.infinity)
        
        let isSemi = url.lastPathComponent.lowercased().contains("semi")
        
        for (nodeIdx, node) in nodes.enumerated() {
            guard let meshIdx = node["mesh"] as? Int, meshIdx < meshes.count else { continue }
            let mesh = meshes[meshIdx]
            guard let primList = mesh["primitives"] as? [[String: Any]] else { continue }
            var world = worldTransforms[nodeIdx]
            
            let meshName = (mesh["name"] as? String ?? "").lowercased()
            let nodeName = (node["name"] as? String ?? "").lowercased()
            let isSemiWheel = isSemi && (meshName.contains("wheel_semi") || nodeName.contains("wheel_semi") || (meshIdx >= 34 && meshIdx <= 39))
            
            if isSemiWheel {
                let tx = world.columns.3.x
                let ty = world.columns.3.y
                let tz = world.columns.3.z
                
                if tz < 0 {
                    // Left Wheel: rotate +90 deg around Y so outer rim (+X in mesh) points to -Z (Left)
                    world = simd_float4x4(
                        SIMD4<Float>(0, 0, -1, 0), // col 0
                        SIMD4<Float>(0, 1, 0, 0),  // col 1
                        SIMD4<Float>(1, 0, 0, 0),  // col 2
                        SIMD4<Float>(tx, ty, tz, 1.0) // col 3
                    )
                } else {
                    // Right Wheel: rotate -90 deg around Y so outer rim (+X in mesh) points to +Z (Right)
                    world = simd_float4x4(
                        SIMD4<Float>(0, 0, 1, 0),  // col 0
                        SIMD4<Float>(0, 1, 0, 0),  // col 1
                        SIMD4<Float>(-1, 0, 0, 0), // col 2
                        SIMD4<Float>(tx, ty, tz, 1.0) // col 3
                    )
                }
            }
            
            let normalMat3 = simd_float3x3(
                SIMD3<Float>(world.columns.0.x, world.columns.0.y, world.columns.0.z),
                SIMD3<Float>(world.columns.1.x, world.columns.1.y, world.columns.1.z),
                SIMD3<Float>(world.columns.2.x, world.columns.2.y, world.columns.2.z)
            )
            let isMirrored = simd_determinant(normalMat3) < 0
            let normalMat = normalMat3.inverse.transpose
            
            for p in primList {
                guard let attrs = p["attributes"] as? [String: Any],
                      let posAcc = attrs["POSITION"] as? Int else { continue }
                let posList = readFloat3(accessorIdx: posAcc)
                let normList = attrs["NORMAL"] != nil ? readFloat3(accessorIdx: attrs["NORMAL"] as! Int) : [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: posList.count)
                let idxList = p["indices"] != nil ? readIndices(accessorIdx: p["indices"] as! Int) : Array(0..<UInt32(posList.count))
                
                var matName = ""
                if let matIdx = p["material"] as? Int, matIdx < materials.count {
                    matName = (materials[matIdx]["name"] as? String ?? "").lowercased()
                }
                
                // Categorize material by Tesla glTF prefix "<category>__<name>"
                let prefix = matName.contains("__") ? String(matName.components(separatedBy: "__")[0]) : ""
                var cat = 13 // Default: Trim / Chassis
                
                if prefix == "paint" || matName == "mirror__paintskybox" || matName.contains("carpaint") || matName.contains("steel_exterior") || matName == "body" {
                    cat = 1 // Car paint / stainless steel
                } else if matName == "headlight__headlight_cover" || matName.starts(with: "glass_clear") {
                    cat = 4 // Clear Headlight Glass Lens
                } else if matName.starts(with: "glass_tinted") {
                    cat = 3 // Tinted Glass Roof
                } else if matName.starts(with: "glass") || matName.contains("window") || matName.contains("windshield") {
                    cat = 2 // Windows & Windshield Glass
                } else if prefix.starts(with: "wheel") || matName.contains("rotor") || matName.contains("brake_disc") {
                    cat = 5 // Wheels
                } else if prefix.starts(with: "tire") || matName.contains("rubber") {
                    cat = 6 // Tires
                } else if prefix == "taillight" && (matName.contains("illum") || matName.contains("light")) && !matName.contains("light_off") && !matName.contains("trim") {
                    cat = 9 // Taillight Red LEDs
                } else if (prefix == "headlight" || prefix == "light") && (matName.contains("illum") || matName.contains("light") || matName.contains("drl")) && !matName.contains("cover") {
                    cat = 8 // Headlight White LEDs
                } else if matName.contains("trim__lights") || matName.contains("trim__reflector") || matName.contains("trim__light") || prefix.starts(with: "chrome") || prefix.starts(with: "mirror") || matName.contains("aluminum") || matName.contains("silver") {
                    cat = 7 // Chrome, Mirror, Headlight Reflector
                } else if prefix.starts(with: "screen") || matName.contains("display") {
                    cat = 10 // Center Touchscreen
                } else if prefix.starts(with: "interior_white") {
                    cat = 12 // Interior White Seats/Trim
                } else if prefix.starts(with: "interior") || prefix.starts(with: "wood") || prefix.starts(with: "caliper") {
                    cat = 11 // Interior Cabin & Seats
                } else {
                    cat = 13 // Trim / Chassis
                }
                
                var worldPositions = [SIMD3<Float>](repeating: .zero, count: posList.count)
                var worldNormals = [SIMD3<Float>](repeating: .zero, count: posList.count)
                
                for i in 0..<posList.count {
                    let pLocal = posList[i]
                    let pWorld4 = world * SIMD4<Float>(pLocal.x, pLocal.y, pLocal.z, 1.0)
                    let pWorld = SIMD3<Float>(pWorld4.x, pWorld4.y, pWorld4.z)
                    
                    let nLocal = (i < normList.count) ? normList[i] : SIMD3<Float>(0, 1, 0)
                    let nWorld = simd_normalize(normalMat * nLocal)
                    
                    worldPositions[i] = pWorld
                    worldNormals[i] = nWorld
                    
                    bMin = simd_min(bMin, pWorld)
                    bMax = simd_max(bMax, pWorld)
                }
                
                // When a node is mirrored (negative scale/determinant like right-side doors),
                // swap triangle winding order so front-facing detection and normals remain outward-facing!
                var finalIndices = idxList
                if isMirrored {
                    for t in 0..<(finalIndices.count / 3) {
                        finalIndices.swapAt(t * 3 + 1, t * 3 + 2)
                    }
                }
                
                rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: finalIndices, matCategory: cat))
            }
        }
        
        let center = (bMin + bMax) * 0.5
        let groundY = bMin.y
        let size = bMax - bMin
        let radius = max(size.x, max(size.y, size.z)) * 0.55
        
        // Group primitives into 14 distinct geometry buckets:
        // 0: Studio Ground
        // 1: Car Body Paint
        // 2: Windows / Windshield Glass
        // 3: Tinted Glass Roof
        // 4: Clear Headlight Glass Lens
        // 5: Wheels
        // 6: Tires
        // 7: Chrome & Headlight Reflectors
        // 8: Headlight White LEDs
        // 9: Taillight Red LEDs
        // 10: Center Touchscreen
        // 11: Interior Cabin & Seats
        // 12: Interior White Seats/Trim
        // 13: Exterior Trim & Chassis
        var geomBuckets = [GeometryData](repeating: GeometryData(), count: 14)
        
        // 0: Build Studio Ground Pedestal (large circular disk + contact plane)
        var groundGeom = GeometryData()
        groundGeom.isGround = 1
        groundGeom.baseColor = SIMD3<Float>(0.06, 0.07, 0.09)
        groundGeom.metallic = 0.20
        groundGeom.roughness = 0.08
        groundGeom.clearcoat = 0.85
        
        // Create high-detail circular pedestal ground disk (radius 28 meters)
        let groundRadius: Float = 28.0
        let segments = 72
        groundGeom.vertices.append(RaytraceVertex(position: SIMD3<Float>(0, 0, 0), normal: SIMD3<Float>(0, 1, 0)))
        for i in 0...segments {
            let angle = Float(i) * (2.0 * Float.pi / Float(segments))
            let x = cos(angle) * groundRadius
            let z = sin(angle) * groundRadius
            groundGeom.vertices.append(RaytraceVertex(position: SIMD3<Float>(x, 0, z), normal: SIMD3<Float>(0, 1, 0)))
        }
        for i in 1...segments {
            groundGeom.indices.append(0)
            groundGeom.indices.append(UInt32(i))
            groundGeom.indices.append(UInt32(i + 1))
        }
        geomBuckets[0] = groundGeom
        
        // 1: Car Body Paint (isPaint = 1, dynamically controlled)
        geomBuckets[1].isPaint = 1
        geomBuckets[1].baseColor = SIMD3<Float>(0.65, 0.65, 0.65)
        geomBuckets[1].metallic = 0.85
        geomBuckets[1].roughness = 0.12
        geomBuckets[1].clearcoat = 1.0
        
        // 2: Windows & Windshield Glass (Transparent ray-traced transmission)
        geomBuckets[2].baseColor = SIMD3<Float>(0.88, 0.92, 0.96)
        geomBuckets[2].metallic = 0.02
        geomBuckets[2].roughness = 0.02
        geomBuckets[2].clearcoat = 1.0
        geomBuckets[2].transmission = 0.88
        
        // 3: Tinted Glass Roof & Rear Privacy Windows (Factory privacy transmission)
        geomBuckets[3].baseColor = SIMD3<Float>(0.22, 0.25, 0.30)
        geomBuckets[3].metallic = 0.04
        geomBuckets[3].roughness = 0.02
        geomBuckets[3].clearcoat = 1.0
        geomBuckets[3].transmission = 0.40
        
        // 4: Clear Headlight Glass Lens (Crystal clear high transmission)
        geomBuckets[4].baseColor = SIMD3<Float>(0.98, 0.99, 1.0)
        geomBuckets[4].metallic = 0.0
        geomBuckets[4].roughness = 0.01
        geomBuckets[4].clearcoat = 1.0
        geomBuckets[4].transmission = 0.98
        
        // 5: Wheels (Alloy rims)
        geomBuckets[5].baseColor = SIMD3<Float>(0.24, 0.25, 0.28)
        geomBuckets[5].metallic = 0.92
        geomBuckets[5].roughness = 0.18
        geomBuckets[5].clearcoat = 0.6
        
        // 6: Tires (Rubber)
        geomBuckets[6].baseColor = SIMD3<Float>(0.04, 0.04, 0.045)
        geomBuckets[6].metallic = 0.0
        geomBuckets[6].roughness = 0.85
        geomBuckets[6].clearcoat = 0.0
        
        // 7: Chrome & Exterior Mirrors & Headlight Reflectors
        geomBuckets[7].baseColor = SIMD3<Float>(0.95, 0.95, 0.95)
        geomBuckets[7].metallic = 0.98
        geomBuckets[7].roughness = 0.04
        geomBuckets[7].clearcoat = 1.0
        
        // 8: Headlight White LEDs
        geomBuckets[8].baseColor = SIMD3<Float>(1.0, 0.98, 0.95)
        geomBuckets[8].metallic = 0.05
        geomBuckets[8].roughness = 0.08
        geomBuckets[8].emissive = 3.5
        geomBuckets[8].clearcoat = 1.0
        
        // 9: Taillight Red LEDs
        geomBuckets[9].baseColor = SIMD3<Float>(1.0, 0.06, 0.02)
        geomBuckets[9].metallic = 0.05
        geomBuckets[9].roughness = 0.08
        geomBuckets[9].emissive = 3.0
        geomBuckets[9].clearcoat = 1.0
        
        // 10: Center Touchscreen / Displays
        geomBuckets[10].baseColor = SIMD3<Float>(0.30, 0.42, 0.60)
        geomBuckets[10].metallic = 0.20
        geomBuckets[10].roughness = 0.05
        geomBuckets[10].emissive = 0.85
        geomBuckets[10].clearcoat = 1.0
        
        // 11: Interior Cabin & Seats
        geomBuckets[11].baseColor = SIMD3<Float>(0.12, 0.13, 0.15)
        geomBuckets[11].metallic = 0.05
        geomBuckets[11].roughness = 0.45
        geomBuckets[11].clearcoat = 0.0
        
        // 12: Interior White Seats/Trim
        geomBuckets[12].baseColor = SIMD3<Float>(0.92, 0.93, 0.95)
        geomBuckets[12].metallic = 0.05
        geomBuckets[12].roughness = 0.35
        geomBuckets[12].clearcoat = 0.0
        
        // 13: Exterior Trim & Chassis
        geomBuckets[13].baseColor = SIMD3<Float>(0.08, 0.09, 0.10)
        geomBuckets[13].metallic = 0.15
        geomBuckets[13].roughness = 0.65
        geomBuckets[13].clearcoat = 0.0
        
        // Center the vehicle: center in X/Z, align bottom of wheels to ground y = 0.001
        for prim in rawPrims {
            let cat = prim.matCategory
            let baseIndex = UInt32(geomBuckets[cat].vertices.count)
            
            for i in 0..<prim.positions.count {
                let p = prim.positions[i]
                let centeredPos = SIMD3<Float>(
                    p.x - center.x,
                    p.y - groundY + 0.001,
                    p.z - center.z
                )
                geomBuckets[cat].vertices.append(RaytraceVertex(position: centeredPos, normal: prim.normals[i]))
            }
            
            for idx in prim.indices {
                geomBuckets[cat].indices.append(baseIndex + idx)
            }
        }
        
        var totalTris = 0
        var totalVerts = 0
        for g in geomBuckets {
            totalTris += g.indices.count / 3
            totalVerts += g.vertices.count
        }
        
        var scene = ModelSceneData()
        scene.geometries = geomBuckets
        scene.boundsMin = SIMD3<Float>(-size.x * 0.5, 0, -size.z * 0.5)
        scene.boundsMax = SIMD3<Float>(size.x * 0.5, size.y, size.z * 0.5)
        scene.radius = radius
        scene.center = SIMD3<Float>(0, size.y * 0.5, 0)
        scene.totalTriangles = totalTris
        scene.totalVertices = totalVerts
        
        return scene
    }
}
