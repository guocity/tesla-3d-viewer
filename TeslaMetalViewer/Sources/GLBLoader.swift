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
                
                // Charge Port and Rear Side Reflectors (refer to user Image 2)
                let isChargeCap = nodeName.contains("charge_cap") || nodeName.contains("chargecap") ||
                                  meshName.contains("charge_cap") || meshName.contains("chargecap") ||
                                  nodeName.contains("charge_port_cover") || meshName.contains("charge_port_cover") ||
                                  nodeName.contains("charge_port") || meshName.contains("charge_port")
                
                // Cybertruck & Front Lightbars (Cybertruck's signature horizontal front LED lightbar & roof lightbars: WHITE, NEVER BLACK!)
                let isCybertruckLightbar = meshName.contains("lightbar") || nodeName.contains("lightbar") ||
                                           matName.contains("lightbar") || meshName.contains("lights_hood") ||
                                           nodeName.contains("lights_hood")
                
                // Model Y Refresh (bayberry) Front Lightbar & DRL (Signature front full-width horizontal lightbar: WHITE!)
                let isRefreshFrontLightbar = (meshName.contains("static_exterior") || meshName.contains("fascia")) &&
                                             (matName.contains("glass_lights") || matName.contains("drl") || matName.contains("headlight"))
                
                // Rear Lightbar & Taillight assembly
                let isRearLightbar = (meshName.contains("trunk") || meshName.contains("lights_trunk") || prefix == "taillight") &&
                                     (matName.contains("light") || matName.contains("illum") || matName.contains("reflector") || matName.contains("brake"))
                
                // Headlight & Front LED lighting
                let isHeadlight = prefix == "headlight" || (prefix == "light" && !matName.contains("taillight") && !meshName.contains("trunk"))
                
                // Paint Fade materials (*_Fade) are inner roof bow crossmembers, windshield headers, and glass frame channels - NOT car body panels!
                let isPaintFade = matName.contains("fade") && (matName.contains("paint") || matName.contains("exterior") || matName.contains("trim"))
                
                // Tesla Car Body Paint: ALWAYS checked FIRST before glass checks to preserve body panels!
                let isPaintMaterial = (prefix == "paint" || 
                                      matName.starts(with: "paint__") || 
                                      matName == "mirror__paintskybox" || 
                                      matName.contains("carpaint") || 
                                      matName.contains("steel_exterior") || 
                                      matName == "body") && !isPaintFade
                
                // Tesla Semi Cab Panels & Window Frames: Door frames, cab surrounds, roof aero, hood surround are painted car body color!
                let isSemiCabBody = isSemi && (meshName.contains("door") || nodeName.contains("door") ||
                                              meshName.contains("hood") || nodeName.contains("hood") ||
                                              meshName.contains("roof_aero") || nodeName.contains("roof_aero") ||
                                              meshName.contains("rear_closeout") || nodeName.contains("rear_closeout")) &&
                                     !meshName.contains("card") && !nodeName.contains("card") &&
                                     !matName.contains("glass")
                
                // Tesla Semi Windows: All side and rear door windows have deep factory privacy tint like Image 2!
                let isSemiSideOrRearWindow = isSemi && (meshName.contains("window_l") || 
                                                       meshName.contains("window_r") || 
                                                       meshName == "window_l" || 
                                                       meshName == "window_r" || 
                                                       meshName.contains("body_extension") ||
                                                       nodeName.contains("body_extension")) && 
                                                       matName.contains("glass")
                
                // Front Side Windows & Windshield: ALWAYS 100% CLEAR TRANSPARENT GLASS (Cat 2)
                let isFrontSideWindow = !isSemi && (meshName.contains("window_lf") || 
                                        meshName.contains("window_rf") || 
                                        meshName.contains("window_small_lf") || 
                                        meshName.contains("window_small_rf") || 
                                        meshName.contains("front_left_window") || 
                                        meshName.contains("front_right_window") || 
                                        meshName.contains("window_front") || 
                                        meshName == "window_l" || 
                                        meshName == "window_r" || 
                                        meshName == "window_lf2" || 
                                        meshName == "window_rf2")
                
                // Rear Windows, Hatch/Liftgate, and Rear Quarter (Opera) Glass: ALWAYS PRIVACY TINTED (Cat 3)
                // Includes Tesla Semi door/side windows, Model Y Refresh (bayberry) Mesh 6 Trunk_Cover, Mesh 35 Static_Exterior quarter windows, etc.
                let isRearWindow = isSemiSideOrRearWindow ||
                                   meshName.contains("window_lr") || 
                                   meshName.contains("window_rr") || 
                                   meshName.contains("back_left_window") || 
                                   meshName.contains("back_right_window") || 
                                   meshName.contains("windows_rear") || 
                                   meshName.contains("window_rear") || 
                                   meshName.contains("windows_side") || 
                                   meshName.contains("window_r2") || 
                                   meshName.contains("window_lr2") || 
                                   meshName.contains("window_rr2") || 
                                   matName.contains("windows_dark") ||
                                   ((meshName.contains("trunk_cover") || meshName.contains("static_exterior")) && (matName.contains("windows_dark") || matName.contains("glass_interior")))
                
                if isChargeCap {
                    if matName.contains("light") || matName.contains("reflector") {
                        // Red retro-reflector on charge port door & passenger reflector (refer to Image 2)
                        cat = 9
                    } else if matName.contains("exterior") || matName.contains("trim") || matName.contains("plastic") {
                        // Gloss black surround bezel of charge port door (refer to Image 2)
                        cat = 13
                    } else if matName.contains("paint") || matName.contains("color") {
                        cat = 1 // Body paint
                    } else {
                        cat = 9 // Red reflector
                    }
                } else if isCybertruckLightbar || isRefreshFrontLightbar {
                    if matName.contains("cover") && !matName.contains("drl") && !matName.contains("lights") {
                        cat = 4 // Clear Headlight Glass Lens
                    } else {
                        cat = 8 // White LED Lightbar / Illumination (Cybertruck & Model Y Refresh front lightbars are brilliant WHITE!)
                    }
                } else if isRearLightbar {
                    cat = 9 // Taillight & Brake Light Ruby Red Reflector / LEDs
                } else if nodeName.contains("chargeport") || meshName.contains("chargeport") {
                    cat = 13 // Internal matte black charging socket plastic
                } else if isPaintMaterial || isSemiCabBody {
                    cat = 1 // Car paint / stainless steel / Tesla Semi cab door & window frame
                } else if isFrontSideWindow {
                    // Front door windows: ALWAYS 100% CLEAR TRANSPARENT GLASS
                    cat = 2
                } else if meshName.contains("windows_top") || nodeName.contains("windows_top") {
                    let avgLocalX = posList.isEmpty ? 0.0 : (posList.reduce(0.0) { $0 + $1.x } / Float(posList.count))
                    if avgLocalX > 0.10 {
                        // Front Windshield!
                        cat = 2 // Clear Transparent Windshield Glass
                    } else {
                        // Panoramic Glass Roof & Rear Glass!
                        cat = 3 // Tinted Glass Roof & Privacy Tint
                    }
                } else if isRearWindow {
                    cat = 3 // Tinted Rear Privacy Glass (All 3 rear glass panels in Model Y Refresh, hatch, quarter, doors)
                } else if matName == "headlight__headlight_cover" || matName.starts(with: "glass_clear") || meshName.contains("lights_glass") {
                    cat = 4 // Clear Headlight & Taillight Outer Glass Lens
                } else if matName.contains("windows_dark") || matName.contains("glass_top") || matName.starts(with: "glass_tinted") {
                    cat = 3 // Tinted Glass Roof & Rear Privacy Glass
                } else if matName.starts(with: "glass") || matName.contains("window") || matName.contains("windshield") {
                    cat = 2 // Clear Windows Glass
                } else if isHeadlight {
                    if matName.contains("cover") || matName.contains("glass") {
                        cat = 4 // Clear Headlight Outer Glass Lens
                    } else if matName.contains("chrome") || matName.contains("aluminum") || matName.contains("reflector") {
                        cat = 7 // Chrome Reflector
                    } else {
                        cat = 8 // Headlight White LEDs & DRL (White, NOT Black!)
                    }
                } else if matName.contains("upper_trim") || matName.contains("headliner") {
                    cat = 11 // Interior Cabin & Seats (Dark automotive charcoal headliner/trim, NOT silver alloy!)
                } else if (prefix.starts(with: "wheel") || matName.contains("rotor") || matName.contains("brake_disc")) && !matName.contains("trim") {
                    cat = 5 // Wheels
                } else if prefix.starts(with: "tire") || matName.contains("rubber") {
                    cat = 6 // Tires
                } else if prefix == "taillight" || meshName.contains("lights_trunk") || matName.contains("taillight") || matName.contains("brake") {
                    cat = 9 // Taillight & Brake Light Ruby Red Reflector (Rich red, gloss clearcoat, no emissive blow-out!)
                } else if matName.contains("trim__lights") || matName.contains("trim__reflector") || matName.contains("trim__light") || prefix.starts(with: "chrome") || matName == "mirror__mirror" || matName.contains("aluminum") || matName.contains("silver") {
                    cat = 7 // Chrome Mirror glass / Headlight Reflector / Badging
                } else if prefix.starts(with: "screen") || matName.contains("display") {
                    cat = 10 // Center Touchscreen
                } else if prefix.starts(with: "interior_white") {
                    if meshName.contains("body") || nodeName.contains("body") {
                        cat = 13 // Interior B-pillar upper plastic is satin black trim matching pillar exterior
                    } else {
                        cat = 12 // Interior White Seats
                    }
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
                
                let isDoorMesh = (meshName.contains("door") || nodeName.contains("door")) &&
                                 !meshName.contains("card") && !nodeName.contains("card")
                let isClassicModel3 = url.lastPathComponent.lowercased().contains("model3_high")
                let isModelY = url.lastPathComponent.lowercased().contains("modely")
                let beltlineThreshold: Float = isModelY ? 1.05 : 0.94
                let isRefreshDoorOuter = isDoorMesh && (matName.contains("trim__cover") || matName.contains("wheel_rim__trim"))
                let isStandardDoorTrim = isDoorMesh && matName.contains("trim__exterior")
                let isStandardDoorPaint = isDoorMesh && isPaintMaterial
                let isPaintMeshForSeparation = (cat == 1 || isPaintMaterial) && !isDoorMesh &&
                                               !meshName.contains("hood") && !nodeName.contains("hood") &&
                                               !meshName.contains("bumper") && !nodeName.contains("bumper")

                // If Model Y Refresh front lights, split into center white lightbar and clear transparent headlights:
                if isRefreshFrontLightbar {
                    var lightbarIndices: [UInt32] = []
                    var headlightIndices: [UInt32] = []
                    
                    for t in 0..<(finalIndices.count / 3) {
                        let idx0 = finalIndices[t * 3]
                        let idx1 = finalIndices[t * 3 + 1]
                        let idx2 = finalIndices[t * 3 + 2]
                        let p0 = worldPositions[Int(idx0)]
                        let p1 = worldPositions[Int(idx1)]
                        let p2 = worldPositions[Int(idx2)]
                        let midX = (p0.x + p1.x + p2.x) / 3.0
                        if abs(midX) < 0.52 {
                            // Center horizontal lightbar across the nose: brilliant white LED lightbar!
                            lightbarIndices.append(idx0)
                            lightbarIndices.append(idx1)
                            lightbarIndices.append(idx2)
                        } else {
                            // Left & Right headlights: 100% CLEAR TRANSPARENT optical glass lens!
                            headlightIndices.append(idx0)
                            headlightIndices.append(idx1)
                            headlightIndices.append(idx2)
                        }
                    }
                    
                    if !lightbarIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: lightbarIndices, matCategory: 8)) // White LED Lightbar
                    }
                    if !headlightIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: headlightIndices, matCategory: 4)) // Clear Transparent Headlight Glass Lens
                    }
                } else if isRefreshDoorOuter {
                    // Model Y Refresh Doors:
                    // Triangles with Y > 1.16 are the thin window weatherstrip trim (Category 13 Black).
                    // Triangles with Y <= 1.16 are the outer door skin, handles, and character lines (Category 1 Factory Body Paint)!
                    var trimIndices: [UInt32] = []
                    var paintIndices: [UInt32] = []
                    
                    for t in 0..<(finalIndices.count / 3) {
                        let idx0 = finalIndices[t * 3]
                        let idx1 = finalIndices[t * 3 + 1]
                        let idx2 = finalIndices[t * 3 + 2]
                        let p0 = worldPositions[Int(idx0)]
                        let p1 = worldPositions[Int(idx1)]
                        let p2 = worldPositions[Int(idx2)]
                        let midY = (p0.y + p1.y + p2.y) / 3.0
                        
                        if midY > 1.16 {
                            trimIndices.append(idx0)
                            trimIndices.append(idx1)
                            trimIndices.append(idx2)
                        } else {
                            paintIndices.append(idx0)
                            paintIndices.append(idx1)
                            paintIndices.append(idx2)
                        }
                    }
                    if !trimIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: trimIndices, matCategory: 13))
                    }
                    if !paintIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: paintIndices, matCategory: 1))
                    }
                } else if isStandardDoorTrim {
                    // Standard Door Trim Meshes (Model 3, Highland, Model Y):
                    // Triangles above window sill are beltline trim.
                    // Triangles in door handle zones are door handles!
                    // Classic Model 3 has factory Chrome handles & beltline trim (Category 7 Chrome).
                    // Modern variants (Highland, Model Y) have Satin Black Trim (Category 13 Black).
                    let trimCat = isClassicModel3 ? 7 : 13
                    
                    var trimIndices: [UInt32] = []
                    var paintIndices: [UInt32] = []
                    
                    for t in 0..<(finalIndices.count / 3) {
                        let idx0 = finalIndices[t * 3]
                        let idx1 = finalIndices[t * 3 + 1]
                        let idx2 = finalIndices[t * 3 + 2]
                        let p0 = worldPositions[Int(idx0)]
                        let p1 = worldPositions[Int(idx1)]
                        let p2 = worldPositions[Int(idx2)]
                        let midX = (p0.x + p1.x + p2.x) / 3.0
                        let midY = (p0.y + p1.y + p2.y) / 3.0
                        
                        let isFrontHandle = (midY >= 0.65 && midY <= (isModelY ? 1.00 : 0.90)) && (midX >= -0.20 && midX <= 0.25)
                        let isRearHandle = (midY >= 0.65 && midY <= (isModelY ? 1.00 : 0.90)) && (midX >= -1.25 && midX <= -0.65)
                        let isHandle = isFrontHandle || isRearHandle
                        let isBeltline = (midY > beltlineThreshold)
                        
                        if isBeltline || isHandle {
                            trimIndices.append(idx0)
                            trimIndices.append(idx1)
                            trimIndices.append(idx2)
                        } else {
                            paintIndices.append(idx0)
                            paintIndices.append(idx1)
                            paintIndices.append(idx2)
                        }
                    }
                    if !trimIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: trimIndices, matCategory: trimCat))
                    }
                    if !paintIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: paintIndices, matCategory: 1))
                    }
                } else if isPaintMeshForSeparation {
                    // Wiper separation, window pillars, and window perimeter trim:
                    // Body panels (outer roof arches, quarter panels, cant rails, doors, fenders) remain 100% factory car body paint!
                    // Only separate windshield wiper assemblies, door frame pillars (B-pillar, C-pillar quarter glass divider),
                    // and upper window perimeter trim strip.
                    var wiperIndices: [UInt32] = []
                    var pillarIndices: [UInt32] = []
                    var windowTrimIndices: [UInt32] = []
                    var bodyIndices: [UInt32] = []
                    
                    for t in 0..<(finalIndices.count / 3) {
                        let idx0 = finalIndices[t * 3]
                        let idx1 = finalIndices[t * 3 + 1]
                        let idx2 = finalIndices[t * 3 + 2]
                        let p0 = worldPositions[Int(idx0)]
                        let p1 = worldPositions[Int(idx1)]
                        let p2 = worldPositions[Int(idx2)]
                        let midX = (p0.x + p1.x + p2.x) / 3.0
                        let midY = (p0.y + p1.y + p2.y) / 3.0
                        let midZ = (p0.z + p1.z + p2.z) / 3.0
                        let n0 = worldNormals[Int(idx0)]
                        let n1 = worldNormals[Int(idx1)]
                        let n2 = worldNormals[Int(idx2)]
                        let avgNy = (n0.y + n1.y + n2.y) / 3.0
                        let avgNz = (n0.z + n1.z + n2.z) / 3.0
                        
                        let isWiper: Bool
                        let isPillar: Bool
                        let isWindowTrim: Bool
                        
                        if isSemi {
                            // 1. Semi Windshield Wiper (blade, arm, and pivot on windshield glass surface):
                            let isBlade = (midX >= 2.65 && midX <= 3.26 && midY >= 1.80 && midY <= 2.60 && midZ >= 0.40 && midZ <= 0.66)
                            let isArm = (midX >= 3.10 && midX <= 3.38 && midY >= 1.68 && midY <= 2.02 && midZ >= -0.12 && midZ <= 0.52)
                            isWiper = isBlade || isArm
                            // 2. Semi Window Pillar (A-pillar between windshield and side door window):
                            isPillar = (midX >= 2.35 && midX <= 3.26 && midY >= 1.65 && midY <= 2.78 && abs(midZ) >= 0.62 && abs(midZ) <= 0.84)
                            isWindowTrim = false
                        } else if url.lastPathComponent.lowercased().contains("bayberry") {
                            // Model Y Refresh (Z-forward): Wiper arms and blades across cowl
                            isWiper = (midZ >= -1.40 && midZ <= -0.75 && midY >= 0.82 && midY <= 1.06 && abs(midX) <= 0.75)
                            isPillar = false
                            isWindowTrim = false
                        } else {
                            // Standard X-forward vehicles (Model 3, Highland, Model Y, Model S, Model X):
                            // 1. Wiper arms and blades across cowl
                            let maxZ: Float = matName.contains("paintskybox") ? 0.68 : 0.74
                            isWiper = (midX >= 1.02 && midX <= 1.45 && midY >= 0.82 && midY <= 1.06 && abs(midZ) <= maxZ)
                            
                            let isBodyMesh = meshName.contains("body") || nodeName.contains("body")
                            
                            // 2. Side window perimeter trim strip around side windows (Model 3, Model Y, etc.):
                            // Encompasses the continuous hockey-stick trim around the fixed rear quarter window,
                            // the upper roof arch over the doors, and continues down the A-pillar to the front mirror base.
                            // Trim strictly faces outward towards vehicle sides: abs(avgNz) >= 0.75.
                            // Windshield header/gutter has abs(avgNz) < 0.70 or avgNy < -0.50, and cant rail / C-pillar paint has avgNy >= 0.52.
                            let isSideTrim = isBodyMesh && (midX >= -1.62 && midX <= 0.79 &&
                                                           midY >= 1.02 && midY <= (isModelY ? 1.62 : 1.45) &&
                                                           abs(midZ) >= 0.60 && abs(midZ) <= 0.82 &&
                                                           abs(avgNz) >= 0.75 &&
                                                           avgNy <= 0.485 && avgNy >= -0.50)
                            isWindowTrim = isSideTrim
                            
                            // 3. Window Pillars on Body Mesh:
                            // B-pillar vertical divider between front and rear windows (below the upper window trim)
                            // C-pillar divider between rear window and quarter glass
                            let isBPillar = isBodyMesh && (midX >= -0.34 && midX <= -0.16 && midY >= 0.95 && midY <= 1.33 && abs(midZ) >= 0.65 && abs(midZ) <= 0.82)
                            let isCPillar = isBodyMesh && (midX >= -1.25 && midX <= -1.05 && midY >= 0.95 && midY <= 1.25 && abs(midZ) >= 0.65 && abs(midZ) <= 0.82)
                            isPillar = (isBPillar || isCPillar) && !isWindowTrim
                        }
                        
                        if isWiper {
                            wiperIndices.append(idx0)
                            wiperIndices.append(idx1)
                            wiperIndices.append(idx2)
                        } else if isWindowTrim {
                            windowTrimIndices.append(idx0)
                            windowTrimIndices.append(idx1)
                            windowTrimIndices.append(idx2)
                        } else if isPillar {
                            pillarIndices.append(idx0)
                            pillarIndices.append(idx1)
                            pillarIndices.append(idx2)
                        } else {
                            bodyIndices.append(idx0)
                            bodyIndices.append(idx1)
                            bodyIndices.append(idx2)
                        }
                    }
                    
                    if !wiperIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: wiperIndices, matCategory: 13)) // Windshield Wiper: Satin Black Trim
                    }
                    if !pillarIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: pillarIndices, matCategory: 13)) // Window Pillar: Satin Black Trim
                    }
                    if !windowTrimIndices.isEmpty {
                        // Upper window perimeter trim: Category 7 Chrome for classic Model 3, Category 13 Satin Black for others!
                        let trimCat = isClassicModel3 ? 7 : 13
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: windowTrimIndices, matCategory: trimCat))
                    }
                    if !bodyIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: bodyIndices, matCategory: cat)) // Car Body Paint: 100% Factory Paint!
                    }
                } else if (cat == 7 || cat == 8) && (meshName.contains("light") || matName.contains("light")) {
                    // Combined light mesh spanning both front and rear (e.g. Model Y lights or Cybertruck Lights2)
                    var frontIndices: [UInt32] = []
                    var rearIndices: [UInt32] = []
                    
                    for t in 0..<(finalIndices.count / 3) {
                        let idx0 = finalIndices[t * 3]
                        let idx1 = finalIndices[t * 3 + 1]
                        let idx2 = finalIndices[t * 3 + 2]
                        let p0 = worldPositions[Int(idx0)]
                        let p1 = worldPositions[Int(idx1)]
                        let p2 = worldPositions[Int(idx2)]
                        let midX = (p0.x + p1.x + p2.x) / 3.0
                        if midX < -0.2 {
                            rearIndices.append(idx0)
                            rearIndices.append(idx1)
                            rearIndices.append(idx2)
                        } else {
                            frontIndices.append(idx0)
                            frontIndices.append(idx1)
                            frontIndices.append(idx2)
                        }
                    }
                    
                    if !frontIndices.isEmpty && !rearIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: frontIndices, matCategory: cat))
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: rearIndices, matCategory: 9))
                    } else if !rearIndices.isEmpty {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: rearIndices, matCategory: 9))
                    } else {
                        rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: frontIndices, matCategory: cat))
                    }
                } else {
                    rawPrims.append(RawPrimitive(positions: worldPositions, normals: worldNormals, indices: finalIndices, matCategory: cat))
                }
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
        
        // 2: Windows & Windshield Glass (100% transparent crystal-clear ray-traced transmission)
        geomBuckets[2].baseColor = SIMD3<Float>(0.92, 0.95, 0.98)
        geomBuckets[2].metallic = 0.01
        geomBuckets[2].roughness = 0.01
        geomBuckets[2].clearcoat = 1.0
        geomBuckets[2].transmission = 0.92
        
        // 3: Tinted Glass Roof & Rear Privacy Windows (Factory privacy transmission)
        geomBuckets[3].baseColor = SIMD3<Float>(0.07, 0.08, 0.10) // Deep factory privacy glass charcoal
        geomBuckets[3].metallic = 0.05
        geomBuckets[3].roughness = 0.01 // Mirror smooth optical glass
        geomBuckets[3].clearcoat = 1.0
        geomBuckets[3].transmission = 0.18 // Deep factory privacy tint!
        
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
        
        // 8: Headlight White LEDs & Front Lightbars (Luminous optical white with transparency)
        geomBuckets[8].baseColor = SIMD3<Float>(0.98, 0.99, 1.0) // Brilliant white
        geomBuckets[8].metallic = 0.02
        geomBuckets[8].roughness = 0.02
        geomBuckets[8].emissive = 3.5 // Glowing white lightbar!
        geomBuckets[8].clearcoat = 1.0
        geomBuckets[8].transmission = 0.65 // Transparent optical lightbar glass!
        
        // 9: Taillight & Brake Light Ruby Red Reflector & Charge Port Reflector (No flat emissive blow-out!)
        geomBuckets[9].baseColor = SIMD3<Float>(0.76, 0.025, 0.035) // Deep rich automotive ruby red
        geomBuckets[9].metallic = 0.05
        geomBuckets[9].roughness = 0.05 // High optical gloss
        geomBuckets[9].emissive = 0.0 // ZERO emissive blow-out! Preserves 100% surface texture, normals, and specular highlights!
        geomBuckets[9].clearcoat = 1.0 // Glossy automotive clearcoat
        
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
        
        // 13: Exterior Trim & Chassis & Underbody
        geomBuckets[13].baseColor = SIMD3<Float>(0.025, 0.027, 0.030) // Deep automotive underbody & trim black
        geomBuckets[13].metallic = 0.08
        geomBuckets[13].roughness = 0.55 // Satin/matte underbody & chassis texture
        geomBuckets[13].clearcoat = 0.0  // Matte underbody, no glossy clearcoat
        
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
