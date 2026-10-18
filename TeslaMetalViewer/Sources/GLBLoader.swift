import Foundation
import Metal
import MetalKit
import simd

public struct RaytraceVertex {
    public var position: SIMD4<Float>
    public var uv: SIMD4<Float> = .zero
    public var normal: SIMD4<Float>
    public init(position: SIMD3<Float>, normal: SIMD3<Float>) {
        self.position = SIMD4(position, 1); self.normal = SIMD4(normal, 0)
    }
}
public struct GeometryData {
    public var vertices: [RaytraceVertex] = []
    public var indices: [UInt32] = []
    public var baseColor = SIMD3<Float>(repeating: 0.2)
    public var metallic: Float = 0
    public var roughness: Float = 0.5
    public var clearcoat: Float = 0
    public var emissionColor = SIMD3<Float>(repeating: 1)
    public var emissionTexture: Int32 = -1
    public var lightRole: String?
    public var isLampOverlay = false
    public var emissive: Float = 0
    public var transmission: Float = 0
    public var isGround: UInt32 = 0
    public var isPaint: UInt32 = 0
    public var textures = SIMD4<Int32>(-1,-1,-1,0)
    public var sourceNode: Int = -1
    public var componentName = ""
    public var sourceMaterial = ""
}
public struct SourceAnimation: Identifiable {
    public var id: String { name }
    public let name: String
    public let duration: Float
    public let tracks: [[String: Any]]
    public let root: String
}
public struct ModelSceneData {
    public var topologyID = UUID()
    public var geometries: [GeometryData] = []
    public var boundsMin: SIMD3<Float> = .zero
    public var boundsMax: SIMD3<Float> = .zero
    public var radius: Float = 3
    public var center: SIMD3<Float> = .zero
    public var totalTriangles = 0
    public var totalVertices = 0
    public var animations: [SourceAnimation] = []
    public var textures: [MTLTexture] = []
    public var climatePlanes: [simd_float4x4] = []
    public var noiseTexture: Int32 = -1
    public var roadTexture: Int32 = -1
    public var hasChargingCable = false
}

/// Reads the converter's glTF and Godot animation metadata without reclassifying surfaces.
public class GLBLoader {
    private static var cachedURL: URL?
    private static var cachedDocument: ([String: Any], Data)?
    private static var cachedAccessors: [String: [[Float]]] = [:]
    private static var cachedTextures: [MTLTexture] = []
    private static var poseCache: (flags: [Bool], scene: ModelSceneData, rawScene: ModelSceneData, world: [simd_float4x4], offset: SIMD3<Float>)?
    private static var restBounds: (SIMD3<Float>, SIMD3<Float>)?

    public static func loadModel(from url: URL, device: MTLDevice,
                                 animation: String? = nil, selectedAnimations: Set<String> = [], time: Float = 0, charging: Bool = false, wheelDegrees: Float = 0,
                                 headlightsOn: Bool = true, drlOn: Bool = true, brakeLightsOn: Bool = false,
                                 turnSignalLeftOn: Bool = false, turnSignalRightOn: Bool = false,
                                 showRoofLightbar: Bool = false, usePoseCache: Bool = true) -> ModelSceneData? {
        do {
            if cachedURL != url {
                let data = try Data(contentsOf: url)
                guard data.count >= 28, data.prefix(4) == Data("glTF".utf8) else { return nil }
                let jsonLength = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self) })
                guard jsonLength > 0, 28 + jsonLength <= data.count else { return nil }
                let document = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20+jsonLength))
                guard let json = document as? [String: Any] else { return nil }
                cachedDocument = (json, data.subdata(in: 28+jsonLength..<data.count))
                cachedURL = url; poseCache = nil; restBounds = nil; cachedTextures = []; cachedAccessors = [:]
            }
            guard let (json, bin) = cachedDocument else { return nil }
            let nodes = json["nodes"] as? [[String: Any]] ?? []
            let meshes = json["meshes"] as? [[String: Any]] ?? []
            let materials = json["materials"] as? [[String: Any]] ?? []
            let accessors = json["accessors"] as? [[String: Any]] ?? []
            let views = json["bufferViews"] as? [[String: Any]] ?? []
            let extras = json["extras"] as? [String: Any] ?? [:]
            if cachedTextures.isEmpty {
                let loader = MTKTextureLoader(device: device)
                for item in extras["sourceTextures"] as? [[String:Any]] ?? [] {
                    guard let viewIndex = item["bufferView"] as? Int, views.indices.contains(viewIndex),
                          let width = item["width"] as? Int, let height = item["height"] as? Int else { return nil }
                    let v = views[viewIndex], offset = v["byteOffset"] as? Int ?? 0, length = v["byteLength"] as? Int ?? 0
                    guard offset >= 0, length > 0, offset+length <= bin.count else { return nil }
                    let bytes = bin.subdata(in: offset..<offset+length)
                    if item["encoding"] as? String == "etc2rgb8" {
                        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat(rawValue: 180)!, width: width, height: height, mipmapped: false)
                        desc.storageMode = .shared; desc.usage = .shaderRead
                        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
                        bytes.withUnsafeBytes { raw in
                            texture.replace(region: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0,
                                            withBytes: raw.baseAddress!, bytesPerRow: ((width+3)/4)*8)
                        }
                        cachedTextures.append(texture)
                    } else {
                        cachedTextures.append(try loader.newTexture(data: bytes, options: [.SRGB:false, .generateMipmaps:false]))
                    }
                }
            }
            guard cachedTextures.count <= 32 else { print("Too many source textures"); return nil }
            let animations = (extras["sourceAnimations"] as? [[String: Any]] ?? []).compactMap { item -> SourceAnimation? in
                guard let name = item["name"] as? String, let tracks = item["tracks"] as? [[String: Any]] else { return nil }
                return SourceAnimation(name: name, duration: (item["duration"] as? NSNumber)?.floatValue ?? 1,
                                       tracks: tracks, root: item["root"] as? String ?? ".")
            }
            // Validate each accessor span before accessing bytes, including strided attributes.
            func values(_ index: Int, components: Int) -> [[Float]] {
                let key = "\(index):\(components)"
                if let cached = cachedAccessors[key] { return cached }
                guard accessors.indices.contains(index) else { return [] }
                let a = accessors[index]
                guard let count = a["count"] as? Int, count > 0,
                      let v = a["bufferView"] as? Int, views.indices.contains(v) else { return [] }
                let type = a["componentType"] as? Int ?? 5126
                let size = type == 5126 || type == 5125 ? 4 : (type == 5123 ? 2 : 1)
                let view = views[v]
                let start = (view["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
                let stride = view["byteStride"] as? Int ?? components * size
                guard start >= 0, stride >= components * size,
                      start + (count - 1) * stride + components * size <= bin.count else { return [] }
                let decoded: [[Float]] = bin.withUnsafeBytes { raw in
                    (0..<count).map { i in
                        (0..<components).map { c in
                            let offset = start + i * stride + c * size
                            switch type {
                            case 5126: return raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                            case 5125: return Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                            case 5123: return Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                            default: return Float(raw.load(fromByteOffset: offset, as: UInt8.self))
                            }
                        }
                    }
                }
                cachedAccessors[key] = decoded
                return decoded
            }
            func floats(_ value: Any?) -> [Float]? { (value as? [NSNumber])?.map { $0.floatValue } }
            func matrix(_ node: [String: Any]) -> simd_float4x4 {
                if let m = floats(node["matrix"]), m.count == 16 {
                    return simd_float4x4(SIMD4(m[0],m[1],m[2],m[3]), SIMD4(m[4],m[5],m[6],m[7]),
                                         SIMD4(m[8],m[9],m[10],m[11]), SIMD4(m[12],m[13],m[14],m[15]))
                }
                let t = floats(node["translation"]) ?? [0,0,0]
                let r = floats(node["rotation"]) ?? [0,0,0,1]
                let s = floats(node["scale"]) ?? [1,1,1]
                var result = simd_matrix4x4(simd_quatf(ix:r[0],iy:r[1],iz:r[2],r:r[3]))
                result = result * simd_float4x4(diagonal: SIMD4(s[0],s[1],s[2],1))
                result.columns.3 = SIMD4(t[0],t[1],t[2],1)
                return result
            }
            var local = nodes.map(matrix)
            var parents = [Int](repeating: -1, count: nodes.count)
            for (i,n) in nodes.enumerated() {
                for c in n["children"] as? [Int] ?? [] where nodes.indices.contains(c) { parents[c] = i }
            }
            func path(_ i: Int) -> String {
                var result = [nodes[i]["name"] as? String ?? ""]
                var p = parents[i]; var visited = Set<Int>()
                while p >= 0 && visited.insert(p).inserted {
                    result.insert(nodes[p]["name"] as? String ?? "", at: 0); p = parents[p]
                }
                return result.joined(separator: "/")
            }
            let paths = nodes.indices.map(path)
            func effect(_ index: Int, name: String) -> Bool {
                var i = index
                var seen = Set<Int>()
                while i >= 0 && seen.insert(i).inserted {
                    if (nodes[i]["extras"] as? [String:Any])?["effect"] as? String == name { return true }
                    i = parents[i]
                }
                return false
            }
            func lightRole(_ index: Int) -> String? {
                var i = index
                var seen = Set<Int>()
                while i >= 0 && seen.insert(i).inserted {
                    if let role = (nodes[i]["extras"] as? [String:Any])?["lightRole"] as? String { return role }
                    i = parents[i]
                }
                return nil
            }
            var activeClips: [(SourceAnimation,Float)] = []
            var requested = selectedAnimations
            if let animation = animation { requested.insert(animation) }
            for clip in animations where requested.contains(clip.name) { activeClips.append((clip,min(time,clip.duration))) }
            if charging, let port = animations.first(where: { $0.name.lowercased().contains("chargeport") }), !requested.contains(port.name) {
                activeClips.append((port,port.duration))
            }
            for (clip,clipTime) in activeClips {
                for track in clip.tracks {
                    guard let target = track["target"] as? String,
                          let times = floats(track["times"]), !times.isEmpty,
                          let keys = (track["values"] as? [[NSNumber]])?.map({ $0.map { $0.floatValue } }), keys.count == times.count else { continue }
                    let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
                    let suffix = parts[0]
                    let candidates = nodes.indices.filter { paths[$0].hasSuffix("/" + suffix) || paths[$0] == suffix }
                    let resolved = track["node"] as? Int ?? (candidates.count == 1 ? candidates.first : nil)
                    guard let index = resolved, nodes.indices.contains(index) else { continue }
                    let t = min(max(clipTime, times[0]), times.last!)
                    let hi = times.firstIndex(where: { $0 >= t }) ?? times.count - 1
                    let lo = max(0, hi - 1)
                    var f = hi == lo ? 0 : (t - times[lo]) / max(0.00001, times[hi] - times[lo])
                    if (track["interpolation"] as? Int) == 0 { f = 0 }
                    let a = keys[lo], b = keys[hi]
                    guard a.count == b.count else { continue }
                    let v = zip(a,b).map { $0 + ($1 - $0) * f }
                    if track["type"] as? String == "transform", v.count == 10 {
                        let q0 = simd_quatf(ix:a[3],iy:a[4],iz:a[5],r:a[6])
                        let q1 = simd_quatf(ix:b[3],iy:b[4],iz:b[5],r:b[6])
                        var m = simd_matrix4x4(simd_slerp(q0,q1,f))
                        m = m * simd_float4x4(diagonal: SIMD4(v[7],v[8],v[9],1))
                        m.columns.3 = SIMD4(v[0],v[1],v[2],1); local[index] = m
                    } else if parts.count == 2, v.count == 3 {
                        if parts[1] == "rotation_degrees" || parts[1] == "rotation" {
                            let factor: Float = parts[1] == "rotation_degrees" ? .pi / 180 : 1
                            // Godot's default Euler convention is YXZ.
                            let q = simd_quatf(angle:v[1]*factor,axis:SIMD3(0,1,0)) * simd_quatf(angle:v[0]*factor,axis:SIMD3(1,0,0)) * simd_quatf(angle:v[2]*factor,axis:SIMD3(0,0,1))
                            let old = local[index]
                            var m = simd_matrix4x4(q)
                            for c in 0..<3 { m[c] *= simd_length(SIMD3(old[c].x,old[c].y,old[c].z)) }
                            m.columns.3 = old.columns.3; local[index] = m
                        } else if parts[1] == "translation" {
                            local[index].columns.3 = SIMD4(v[0],v[1],v[2],1)
                        }
                    }
                }
            }
            if wheelDegrees != 0 {
                // VehicleManager.gdc rotates source wheel sockets around local Z.
                for i in nodes.indices {
                    let name = nodes[i]["name"] as? String ?? ""
                    if name.hasPrefix("Wheel_") && name.hasSuffix("Spatial") {
                        let extra = nodes[i]["extras"] as? [String:Any] ?? [:]
                        let spin = floats(extra["spinAxis"]) ?? [0,0,1]
                        let axis = SIMD3<Float>(spin[0],spin[1],spin[2])
                        let direction: Float = local[i].columns.0.x < 0 ? 1 : -1
                        local[i] = local[i] * simd_matrix4x4(simd_quatf(angle: wheelDegrees * .pi / 180 * direction, axis: axis))
                    }
                }
            }
            var world = local
            var visited = Set<Int>()
            func visit(_ i: Int, _ parent: simd_float4x4) {
                guard nodes.indices.contains(i), visited.insert(i).inserted else { return }
                world[i] = parent * local[i]
                for c in nodes[i]["children"] as? [Int] ?? [] { visit(c, world[i]) }
            }
            for i in nodes.indices where parents[i] == -1 { visit(i, matrix_identity_float4x4) }
            let flags = [charging, headlightsOn, drlOn, brakeLightsOn, turnSignalLeftOn, turnSignalRightOn, showRoofLightbar]
            // Keep decoded surfaces, indices, UVs and materials. Only descendants
            // of a moving joint need new world-space positions and normals.
            if usePoseCache, let cache = poseCache, cache.flags == flags {
                var scene = cache.scene
                var centering = matrix_identity_float4x4
                centering.columns.3 = SIMD4(-cache.offset, 1)
                let uncentering = centering.inverse
                var transforms: [Int: simd_float4x4] = [:]
                for i in world.indices where world[i] != cache.world[i] {
                    transforms[i] = centering * world[i] * cache.world[i].inverse * uncentering
                }
                // Procedural lamp fits depend on nearby posed panels. Refit
                // those from the uncalibrated surfaces when their inputs move.
                let recalibrate = cache.rawScene.geometries.contains { g in
                    guard transforms[g.sourceNode] != nil else { return false }
                    return g.lightRole != nil || g.componentName.contains("Trunk_Cover")
                        || g.sourceMaterial.lowercased().contains("glass_lights")
                        || (url.lastPathComponent == "bayberry_e41.glb" && g.transmission < 0.1)
                }
                if recalibrate { scene = cache.rawScene }
                for g in scene.geometries.indices {
                    guard var transform = transforms[scene.geometries[g].sourceNode] else { continue }
                    if recalibrate { transform = uncentering * transform * centering }
                    let basis = simd_float3x3(SIMD3(transform[0].x,transform[0].y,transform[0].z),
                                              SIMD3(transform[1].x,transform[1].y,transform[1].z),
                                              SIMD3(transform[2].x,transform[2].y,transform[2].z))
                    let normalMatrix = basis.inverse.transpose
                    scene.geometries[g].vertices = scene.geometries[g].vertices.map { vertex in
                        var v = vertex
                        v.position = transform * vertex.position
                        v.normal = SIMD4(simd_normalize(normalMatrix * SIMD3(vertex.normal.x,vertex.normal.y,vertex.normal.z)), 0)
                        return v
                    }
                }
                if recalibrate {
                    VehicleLighting.calibrateRear(&scene,model: url.lastPathComponent,running: headlightsOn || drlOn,braking: brakeLightsOn)
                    for g in scene.geometries.indices where scene.geometries[g].isGround != 1 {
                        for v in scene.geometries[g].vertices.indices { scene.geometries[g].vertices[v].position -= SIMD4(cache.offset,0) }
                    }
                    if let ground = cache.scene.geometries.last { scene.geometries.append(ground) }
                    // Reuse GPU topology when the fitted triangle partitions agree.
                    let sameTopology = scene.geometries.count == cache.scene.geometries.count &&
                        zip(scene.geometries,cache.scene.geometries).allSatisfy { $0.indices == $1.indices && $0.vertices.count == $1.vertices.count }
                    scene.topologyID = sameTopology ? cache.scene.topologyID : UUID()
                }
                return scene
            }
            var scene = ModelSceneData(); scene.animations = animations; scene.textures = cachedTextures
            var minimum = SIMD3<Float>(repeating: .infinity), maximum = -minimum
            let isCybertruck = url.lastPathComponent.contains("cybertruck")
            let isSemi = url.lastPathComponent == "semi.glb"
            let isE41 = url.lastPathComponent == "bayberry_e41.glb"
            for i in nodes.indices where visited.contains(i) {
                if !charging && effect(i,name:"charging") { continue }
                if !showRoofLightbar && effect(i,name:"roofLightbar") { continue }
                guard let mi = nodes[i]["mesh"] as? Int, meshes.indices.contains(mi) else { continue }
                let w = world[i]
                let basis = simd_float3x3(SIMD3(w[0].x,w[0].y,w[0].z),SIMD3(w[1].x,w[1].y,w[1].z),SIMD3(w[2].x,w[2].y,w[2].z))
                guard abs(simd_determinant(basis)) > 1e-12 else { continue }
                let normalMatrix = basis.inverse.transpose
                for prim in meshes[mi]["primitives"] as? [[String:Any]] ?? [] {
                    guard (prim["mode"] as? Int ?? 4) == 4,
                          let attributes = prim["attributes"] as? [String:Int], let pi = attributes["POSITION"] else { continue }
                    let positions = values(pi, components:3)
                    let uvs = attributes["TEXCOORD_0"].map { values($0, components:2) } ?? []
                    let uv2s = attributes["TEXCOORD_1"].map { values($0, components:2) } ?? []
                    let normals = attributes["NORMAL"].map { values($0, components:3) } ?? []
                    guard !positions.isEmpty else { continue }
                    var geom = GeometryData(); geom.sourceNode = i; geom.componentName = paths[i]
                    if paths[i].contains("BackfaceCull") { geom.textures.w |= 8192 }
                    var isEmitterSurface = false
                    if let m = prim["material"] as? Int, materials.indices.contains(m) {
                        let mat = materials[m], pbr = mat["pbrMetallicRoughness"] as? [String:Any] ?? [:]
                        let color = floats(pbr["baseColorFactor"]) ?? [0.2,0.2,0.2,1]
                        geom.baseColor = SIMD3(color[0],color[1],color[2])
                        geom.metallic = (pbr["metallicFactor"] as? NSNumber)?.floatValue ?? 0
                        geom.roughness = (pbr["roughnessFactor"] as? NSNumber)?.floatValue ?? 0.5
                        let ex = mat["extras"] as? [String:Any] ?? [:]
                        geom.sourceMaterial = ex["sourcePath"] as? String ?? mat["name"] as? String ?? ""
                        let bindings = ex["textures"] as? [String:Int] ?? [:]
                        let aoChannel = ex["aoChannel"] as? Int ?? 0
                        // The source selects UV1/UV2 and the packed AO channel per material.
                        let ao = bindings["ao"] ?? -1
                        geom.textures = SIMD4(Int32(bindings["albedo"] ?? -1),Int32(bindings["mra"] ?? -1),Int32(ao),Int32(aoChannel | ((ex["customAlbedo"] as? Bool ?? false) ? 16 : 0) | ((ex["aoUV2"] as? Bool ?? false) ? 32 : 0)))
                        let category = ex["category"] as? String ?? ""
                        geom.isPaint = category == "paint" ? 1 : 0
                        geom.clearcoat = category == "paint" ? 1 : 0
                        if isCybertruck && ((ex["originalName"] as? String ?? "").lowercased().contains("stainless") || mat["name"] as? String == "paint__Stainless_Steel" || (mat["name"] as? String ?? "").contains("Stainless_Steel")) {
                            geom.textures.w |= 2048
                        }
                        if category == "glass" || category == "glass_tinted" || category == "glass_clear" {
                            // Godot alpha-blend colors are not volumetric absorption.
                            // Keep neutral optical transmission; privacy tint is independent.
                            geom.baseColor = SIMD3(0.94,0.97,1)
                            geom.transmission = 0.96
                            geom.metallic = 0; geom.roughness = 0.035
                            geom.textures = SIMD4(-1,-1,-1,category == "glass_tinted" ? 768 : 256)
                        }
                        let sourceProps = ex["sourceProperties"] as? [String:Any] ?? [:]
                        let cullMode = (sourceProps["params_cull_mode"] as? NSNumber)?.intValue ?? 0
                        if ex["sourceType"] != nil && cullMode != 2 { geom.textures.w |= cullMode == 1 ? 16384 : 8192 }
                        geom.emissionTexture = Int32(bindings["emission"] ?? -1)
                        // A few E41 lamp materials request UV2 on meshes that export
                        // only UV1. Fall back to their authored UV1 atlas coordinates.
                        if sourceProps["emission_on_uv2"] as? Bool == true && !uv2s.isEmpty { geom.textures.w |= 4096 }
                        if let e = floats(mat["emissiveFactor"]), e.count >= 3 {
                            geom.emissionColor = SIMD3(e[0],e[1],e[2])
                            geom.emissive = 1
                        }
                        if geom.emissionTexture >= 0 { geom.emissionColor = SIMD3(repeating: 1); geom.emissive = 1 }
                        geom.emissive *= (sourceProps["emission_energy"] as? NSNumber)?.floatValue ?? 1
                        let originalMaterial = (ex["originalName"] as? String ?? "").lowercased()
                        isEmitterSurface = geom.emissionTexture >= 0 || sourceProps["emission_enabled"] as? Bool == true
                            || category == "headlight" || category == "turn_signal" || originalMaterial == "turnsignalus_brakes"
                        // Cybertruck's luminous atlas is stored as albedo, not emission.
                        if isCybertruck && category == "headlight" && geom.emissionTexture < 0 {
                            geom.emissionTexture = geom.textures.x
                        }
                        let original = (ex["originalName"] as? String ?? "").lowercased()
                        let upholsteryName = original.isEmpty ? geom.sourceMaterial.lowercased() : original
                        let upholstery = category.hasPrefix("interior") &&
                            (upholsteryName.contains("leather") || upholsteryName.contains("seat") || upholsteryName.hasPrefix("interior_")) &&
                            !["plastic", "paint", "anodized", "seatbelt", "carpet", "textile", "cupholder"].contains(where: { upholsteryName.contains($0) })
                        if upholstery {
                            geom.metallic = 0; geom.roughness = max(0.82, geom.roughness)
                            geom.clearcoat = 0
                            geom.textures.y = -1 // Packed roughness must not polish upholstery.
                            geom.textures.w |= 1048576 // Subdued leather sheen, separate from paint/rubber.
                        }
                        if (category == "glass_clear" || original == "lens" || original.hasPrefix("glass_light")) && !original.contains("lightbar") {
                            // Godot's dark blend color is not absorption in a clear optical lens.
                            geom.baseColor = SIMD3(repeating: 1)
                            geom.metallic = 0; geom.roughness = 0.008
                            geom.clearcoat = 0; geom.transmission = 1; geom.emissive = 0
                            geom.textures = SIMD4(-1,-1,-1,64)
                        } else if category == "tire" {
                            geom.metallic = 0; geom.roughness = max(0.85,geom.roughness)
                            geom.clearcoat = 0; geom.emissive = 0
                            geom.textures.y = -1 // Packed maps must not polish the rubber.
                            geom.textures.w |= 128
                        }
                    }
                    for (k,p) in positions.enumerated() {
                        let v = w * SIMD4(p[0],p[1],p[2],1), point = SIMD3(v.x,v.y,v.z)
                        let n = normals.indices.contains(k) ? SIMD3(normals[k][0],normals[k][1],normals[k][2]) : SIMD3(0,1,0)
                        geom.vertices.append(RaytraceVertex(position:point,normal:simd_normalize(normalMatrix*n)))
                        if uvs.indices.contains(k) { geom.vertices[geom.vertices.count-1].uv = SIMD4(uvs[k][0],uvs[k][1],0,0) }
                        if uv2s.indices.contains(k) { geom.vertices[geom.vertices.count-1].uv.z = uv2s[k][0]; geom.vertices[geom.vertices.count-1].uv.w = uv2s[k][1] }
                        minimum = simd_min(minimum,point); maximum = simd_max(maximum,point)
                    }
                    if let ai = prim["indices"] as? Int { geom.indices = values(ai,components:1).map { UInt32(max(0,$0[0])) } }
                    else { geom.indices = (0..<positions.count).map(UInt32.init) }
                    guard geom.indices.count % 3 == 0, geom.indices.allSatisfy({ $0 < positions.count }) else { continue }
                    if simd_determinant(basis) < 0 {
                        for t in stride(from:0,to:geom.indices.count,by:3) { geom.indices.swapAt(t+1,t+2) }
                    }
                    if paths[i].contains("BackfaceCull") { geom.textures.w |= 8192 }
                    if geom.sourceMaterial.lowercased().contains("led_strip") || geom.sourceMaterial.lowercased().hasSuffix("/cybertruck/led.material") {
                        continue // Interior accent strips are disabled on every model.
                    }
                    if effect(i,name:"chargeFlow") { geom.isGround = 3 }
                    // Only actual source emitter surfaces respond to lamp controls. A lamp
                    // node may also contain painted covers, chrome bowls and black housings.
                    var role = lightRole(i)
                    if role == nil && effect(i,name:"roofLightbar") { role = "roofLightbar" }
                    // US source variants use the rear brake fixture as the turn signal.
                    // Prefer a dedicated rear signal wherever the source provides one.
                    if let current = role, current == "brake_left" || current == "brake_right" {
                        let side = current == "brake_left" ? "turn_rear_left" : "turn_rear_right"
                        let dedicated = nodes.indices.contains { lightRole($0)?.split(separator: ",").contains(Substring(side)) == true }
                        if !dedicated { role = current + "," + side }
                    }
                    if isEmitterSurface, let role {
                        geom.isLampOverlay = true
                        geom.textures.w |= 524288 // Runtime light overlay, transparent during its dark blink phase.
                        geom.lightRole = role
                        func setLamp(_ g: inout GeometryData, rear: Bool) {
                            let running = headlightsOn || drlOn
                            let active: Bool
                            var tint = SIMD3<Float>(repeating: 1)
                            let roles = Set(role.split(separator: ",").map(String.init))
                            let brake = roles.contains(where: { $0.hasPrefix("brake_") })
                            let left = !roles.isDisjoint(with: ["turn_left","turn_rear_left"])
                            let right = !roles.isDisjoint(with: ["turn_right","turn_rear_right"])
                            if left { g.textures.w |= 32768 }
                            if right { g.textures.w |= 262144 }
                            let sharedRear = (isSemi && brake && !roles.contains("brake_center")) || (isE41 && (left || right) && brake)
                            if role == "headlights" { active = rear ? running : headlightsOn }
                            else if brake || left || right {
                                active = (brake && brakeLightsOn) || (left && turnSignalLeftOn) || (right && turnSignalRightOn) || (sharedRear && running)
                                tint = brake ? SIMD3(1,0.015,0.005) : SIMD3(1,0.28,0.005)
                            } else {
                                switch role {
                                case "drl": active = drlOn
                                case "rear_running", "tail_bar", "parking", "rear_running_center": active = running && !(isCybertruck && role == "tail_bar" && brakeLightsOn); tint = SIMD3(1,0.015,0.005)
                                case "side_marker": active = running; tint = SIMD3(1,0.28,0.005)
                                case "roofLightbar": active = showRoofLightbar
                                default: active = false
                                }
                            }
                            // Colored emission atlases retain their own red/amber/white pixels.
                            // Runtime color is only needed for untextured source emitters.
                            g.emissionColor = g.emissionTexture >= 0 ? SIMD3(repeating: 1) : tint
                            g.emissive = active ? ((brake && brakeLightsOn) || (left && turnSignalLeftOn) || (right && turnSignalRightOn) ? 4 : (sharedRear ? 1.2 : 2.4)) : 0
                        }
                        if role == "headlights" {
                            // Some source meshes combine front projectors and rear running
                            // lamps. Partition their triangles without replacing materials.
                            var front = geom, rear = geom
                            front.indices = []; rear.indices = []
                            for t in stride(from: 0,to: geom.indices.count,by: 3) {
                                let face = Array(geom.indices[t..<t+3])
                                let x = face.reduce(Float(0)) { $0 + geom.vertices[Int($1)].position.x } / 3
                                if x > 0 { front.indices += face } else { rear.indices += face }
                            }
                            if !front.indices.isEmpty { setLamp(&front,rear: false); scene.geometries.append(front) }
                            if !rear.indices.isEmpty { setLamp(&rear,rear: true); rear.lightRole = "rear_running"; scene.geometries.append(rear) }
                            geom.indices = []
                        } else { setLamp(&geom,rear: false) }
                    }
                    if let extras = prim["extras"] as? [String:Any],
                       let triangles = extras["windowTrimTriangles"] as? [Int], !triangles.isEmpty {
                        let mask = Set(triangles)
                        var trim = geom; trim.indices = []; geom.indices = []
                        // Keep source vertices and UVs; isolate only audited surround triangles.
                        let originalIndices = (prim["indices"] as? Int).map { values($0,components:1).map { UInt32(max(0,$0[0])) } } ?? []
                        for t in 0..<(originalIndices.count/3) {
                            var face = Array(originalIndices[(t*3)..<(t*3+3)])
                            if simd_determinant(basis) < 0 { face.swapAt(1,2) }
                            if mask.contains(t) { trim.indices += face } else { geom.indices += face }
                        }
                        trim.textures.w |= 1024
                        scene.geometries.append(trim)
                    }
                    if !geom.indices.isEmpty { scene.geometries.append(geom) }
                }
            }
            let rawGeometries = scene.geometries
            VehicleLighting.calibrateRear(&scene,model: url.lastPathComponent,running: headlightsOn || drlOn,braking: brakeLightsOn)
            guard !scene.geometries.isEmpty else { return nil }
            if restBounds == nil { restBounds = (minimum,maximum) }
            let (restMin,restMax) = restBounds!
            let offset = SIMD3((restMin.x+restMax.x)/2,restMin.y-0.002,(restMin.z+restMax.z)/2)
            for g in scene.geometries.indices {
                for v in scene.geometries[g].vertices.indices { scene.geometries[g].vertices[v].position -= SIMD4(offset,0) }
            }
            let runtime = extras["runtimeEffects"] as? [String:Any] ?? [:]
            scene.noiseTexture = Int32(runtime["noiseTexture"] as? Int ?? -1)
            scene.roadTexture = Int32(runtime["roadTexture"] as? Int ?? -1)
            scene.hasChargingCable = runtime["chargingSource"] != nil
            var centering = matrix_identity_float4x4; centering.columns.3 = SIMD4(-offset,1)
            let rootTransform = local.first ?? matrix_identity_float4x4
            for plane in runtime["climate"] as? [[String:Any]] ?? [] {
                scene.climatePlanes.append((centering * rootTransform * matrix(plane)).inverse)
            }
            var ground = GeometryData(); ground.isGround = 1
            ground.vertices = [SIMD3<Float>(-100,0,-100),SIMD3(100,0,-100),SIMD3(100,0,100),SIMD3(-100,0,100)].map { RaytraceVertex(position:$0,normal:SIMD3(0,1,0)) }
            ground.indices = [0,2,1,0,3,2]; scene.geometries.append(ground)
            let size = restMax-restMin
            scene.boundsMin = restMin-offset; scene.boundsMax = restMax-offset
            scene.center = (restMin+restMax)/2-offset; scene.radius = simd_length(size)/2
            scene.totalTriangles = scene.geometries.reduce(0) { $0+$1.indices.count/3 }
            scene.totalVertices = scene.geometries.reduce(0) { $0+$1.vertices.count }
            var rawScene = scene
            rawScene.geometries = rawGeometries
            poseCache = (flags, scene, rawScene, world, offset)
            return scene
        } catch { print("GLB load failed: \(error)"); return nil }
    }
}
