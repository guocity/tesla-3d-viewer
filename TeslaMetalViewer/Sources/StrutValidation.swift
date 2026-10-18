import Foundation
import Metal
import simd

/// Check rendered strut vertices against independently evaluated source X-axis
/// rotations, including the liftgate parent, fixed body mount and return motion.
enum StrutValidation {
    static func run(device: MTLDevice) -> [String] {
        var failures: [String] = []
        for id in ["bayberry","bayberry_e41","bayberry_e80"] {
            guard let model = TeslaCatalog.models.first(where: { $0.id == id }),
                  let url = TeslaCatalog.resolveModelPath(filename: model.filename),
                  let data = try? Data(contentsOf: url),
                  let rest = GLBLoader.loadModel(from: url,device: device,usePoseCache: false) else {
                failures.append(id + ": load failed"); continue
            }
            let jsonLength = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 12,as: UInt32.self)) }
            guard let json = (try? JSONSerialization.jsonObject(with: data.subdata(in: 20..<20+jsonLength))) as? [String:Any],
                  let nodes = json["nodes"] as? [[String:Any]],
                  let meshes = json["meshes"] as? [[String:Any]],
                  let accessors = json["accessors"] as? [[String:Any]],
                  let views = json["bufferViews"] as? [[String:Any]],
                  let materials = json["materials"] as? [[String:Any]],
                  let clip = rest.animations.first(where: { $0.name == "TrunkAnimation" }) else {
                failures.append(id + ": source metadata"); continue
            }
            func floats(_ value: Any?) -> [Float] { (value as? [NSNumber])?.map { $0.floatValue } ?? [] }
            func matrix(_ v: [Float]) -> simd_float4x4 {
                guard v.count == 16 else { return matrix_identity_float4x4 }
                return simd_float4x4(SIMD4(v[0],v[1],v[2],v[3]),SIMD4(v[4],v[5],v[6],v[7]),
                                     SIMD4(v[8],v[9],v[10],v[11]),SIMD4(v[12],v[13],v[14],v[15]))
            }
            let base = nodes.map { matrix(floats($0["matrix"])) }
            var parents = [Int](repeating: -1,count: nodes.count)
            for (i,node) in nodes.enumerated() {
                for child in node["children"] as? [Int] ?? [] { parents[child] = i }
            }
            func world(_ local: [simd_float4x4], _ index: Int) -> simd_float4x4 {
                parents[index] < 0 ? local[index] : world(local,parents[index])*local[index]
            }
            let strutTracks = clip.tracks.filter { ($0["target"] as? String ?? "").contains("Strut_") }
            if strutTracks.count != 4 || strutTracks.contains(where: { $0["valueType"] as? String != "Transform" }) {
                failures.append(id + ": missing four source strut Transform tracks"); continue
            }
            var maxError: Float = 0
            for time: Float in [0,0.2,0.4,0.6,0.8,1,1.2,0.6,0] {
                var local = base
                for track in clip.tracks {
                    guard let node = track["node"] as? Int,
                          let keys = track["values"] as? [[NSNumber]] else { continue }
                    let times = floats(track["times"])
                    let t = min(time,clip.duration)
                    let hi = times.firstIndex { $0 >= t } ?? times.count-1
                    let lo = max(0,hi-1)
                    let f: Float = lo == hi ? 0 : (t-times[lo])/(times[hi]-times[lo])
                    let a = keys[lo].map(\.floatValue), b = keys[hi].map(\.floatValue)
                    // These source joints rotate only around X. Evaluate their
                    // angle analytically, without using SourceTransform/slerp.
                    let transformValue = a.count == 12
                    let angleA = transformValue ? atan2(a[7],a[4]) : 2*atan2(a[3],a[6])
                    let angleB = transformValue ? atan2(b[7],b[4]) : 2*atan2(b[3],b[6])
                    let angle = angleA+(angleB-angleA)*f, c = cos(angle), s = sin(angle)
                    var m = simd_float4x4(SIMD4(1,0,0,0),SIMD4(0,c,s,0),SIMD4(0,-s,c,0),SIMD4(0,0,0,1))
                    let translation = transformValue ? 9 : 0
                    for axis in 0..<3 { m.columns.3[axis] = a[translation+axis]+(b[translation+axis]-a[translation+axis])*f }
                    local[node] = m
                }
                guard let posed = GLBLoader.loadModel(from: url,device: device,selectedAnimations: [clip.name],time: time) else {
                    failures.append(id + ": pose load"); continue
                }
                var checked = 0
                for g in posed.geometries where g.componentName.contains("Strut_") {
                    guard let original = rest.geometries.first(where: { $0.componentName == g.componentName && $0.sourceMaterial == g.sourceMaterial }),
                          let mesh = nodes[g.sourceNode]["mesh"] as? Int,
                          let primitives = meshes[mesh]["primitives"] as? [[String:Any]],
                          let primitive = primitives.first(where: {
                              guard let material = $0["material"] as? Int else { return false }
                              return (materials[material]["extras"] as? [String:Any])?["sourcePath"] as? String == g.sourceMaterial
                          }), let attributes = primitive["attributes"] as? [String:Int], let position = attributes["POSITION"] else { continue }
                    let accessor = accessors[position], view = views[accessor["bufferView"] as! Int]
                    let offset = 28+jsonLength+(view["byteOffset"] as? Int ?? 0)+(accessor["byteOffset"] as? Int ?? 0)
                    let stride = view["byteStride"] as? Int ?? 12
                    let restWorld = world(base,g.sourceNode), posedWorld = world(local,g.sourceNode)
                    func vertex(_ index: Int) -> SIMD4<Float> {
                        data.withUnsafeBytes { raw in
                            SIMD4(raw.loadUnaligned(fromByteOffset: offset+index*stride,as: Float.self),
                                  raw.loadUnaligned(fromByteOffset: offset+index*stride+4,as: Float.self),
                                  raw.loadUnaligned(fromByteOffset: offset+index*stride+8,as: Float.self),1)
                        }
                    }
                    let centering = restWorld*vertex(0)-original.vertices[0].position
                    for index in [0,g.vertices.count/2,g.vertices.count-1] {
                        let expected = posedWorld*vertex(index)-centering
                        let error = simd_distance(expected,g.vertices[index].position)
                        maxError = max(maxError,error)
                        if !error.isFinite || error > 0.0002 {
                            failures.append(id + ": source strut pose mismatch at \(time): " + g.componentName)
                        }
                    }
                    checked += 1
                }
                if checked < 4 { failures.append(id + ": strut geometry missing from validation") }
            }
            print("Source strut poses: \(id), four source tracks, opening/closing, max vertex error \(maxError) m")
        }
        return failures
    }
}
