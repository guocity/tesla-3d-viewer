import simd

/// Lightweight, original set dressing kept separate from the extracted vehicle.
/// These meshes join the acceleration structure, so they cast shadows and appear
/// in the car, windows and wet road from the same world-space positions.
enum SceneGeometry {
    private static var cached: [LightingPreset: [GeometryData]] = [:]
    static func make(for preset: LightingPreset) -> [GeometryData] {
        if let surfaces = cached[preset] { return surfaces }
        guard preset.isWeatherScene else { return [] }
        var surfaces: [GeometryData] = []
        func box(_ center: SIMD3<Float>, _ size: SIMD3<Float>, _ color: SIMD3<Float>, emission: Float = 0, metal: Float = 0) {
            var g = GeometryData()
            g.baseColor = color; g.roughness = 0.38; g.metallic = metal
            g.emissive = emission; g.isGround = 4
            let lo = center-size/2, hi = center+size/2
            let faces: [(SIMD3<Float>,[SIMD3<Float>])] = [
                (SIMD3(1,0,0),[SIMD3(hi.x,lo.y,lo.z),SIMD3(hi.x,hi.y,lo.z),SIMD3(hi.x,hi.y,hi.z),SIMD3(hi.x,lo.y,hi.z)]),
                (SIMD3(-1,0,0),[SIMD3(lo.x,lo.y,hi.z),SIMD3(lo.x,hi.y,hi.z),SIMD3(lo.x,hi.y,lo.z),SIMD3(lo.x,lo.y,lo.z)]),
                (SIMD3(0,1,0),[SIMD3(lo.x,hi.y,lo.z),SIMD3(lo.x,hi.y,hi.z),SIMD3(hi.x,hi.y,hi.z),SIMD3(hi.x,hi.y,lo.z)]),
                (SIMD3(0,-1,0),[SIMD3(lo.x,lo.y,hi.z),SIMD3(lo.x,lo.y,lo.z),SIMD3(hi.x,lo.y,lo.z),SIMD3(hi.x,lo.y,hi.z)]),
                (SIMD3(0,0,1),[SIMD3(hi.x,lo.y,hi.z),SIMD3(hi.x,hi.y,hi.z),SIMD3(lo.x,hi.y,hi.z),SIMD3(lo.x,lo.y,hi.z)]),
                (SIMD3(0,0,-1),[SIMD3(lo.x,lo.y,lo.z),SIMD3(lo.x,hi.y,lo.z),SIMD3(hi.x,hi.y,lo.z),SIMD3(hi.x,lo.y,lo.z)])]
            for (normal, points) in faces {
                let offset = UInt32(g.vertices.count)
                g.vertices += points.map { RaytraceVertex(position: $0, normal: normal) }
                g.indices += [0,1,2,0,2,3].map { UInt32($0)+offset }
            }
            surfaces.append(g)
        }
        let concrete = SIMD3<Float>(0.10,0.12,0.15)
        if preset == .neonRain {
            for side: Float in [-1,1] {
                // Raised pavement and low bollards frame an open, driveable road.
                box(SIMD3(0,0.09,side*8),SIMD3(100,0.18,4),concrete)
                for i in -4...4 {
                    let x = Float(i)*10
                    let height = Float(12 + (i*i+3)%7)
                    box(SIMD3(x,height/2,side*14),SIMD3(8,height,7),SIMD3(0.035,0.047,0.065),metal: 0.2)
                    let neon = side < 0 ? SIMD3<Float>(0.03,0.65,1) : SIMD3<Float>(1,0.045,0.20)
                    box(SIMD3(x,3.3,side*10.45),SIMD3(7,0.10,0.08),neon,emission: 3)
                    box(SIMD3(x-3.3,2.1,side*10.43),SIMD3(0.08,2.5,0.08),neon,emission: 3)
                    // Recessed window rows with deterministic occupancy.
                    for row in 0..<7 {
                        for col in 0..<5 where (row*7+col*3+i*i)%5 > 1 {
                            let tint = (row+col)%3 == 0 ? SIMD3<Float>(0.9,0.57,0.26) : SIMD3<Float>(0.30,0.48,0.64)
                            box(SIMD3(x-2.7+Float(col)*1.35,4.8+Float(row)*1.5,side*10.46),SIMD3(0.65,0.85,0.04),tint,emission: 0.65)
                        }
                    }
                    box(SIMD3(x,0.45,side*6.6),SIMD3(0.15,0.9,0.15),concrete,metal: 0.4)
                }
            }
        } else {
            for side: Float in [-1,1] {
                for level: Float in [0.48,0.82] {
                    box(SIMD3(0,level,side*6),SIMD3(110,0.10,0.12),SIMD3(0.28,0.32,0.35),metal: 0.7)
                }
                for i in -10...10 {
                    box(SIMD3(Float(i)*5,0.45,side*6),SIMD3(0.12,0.9,0.12),concrete,metal: 0.5)
                }
            }
        }
        cached[preset] = surfaces
        return surfaces
    }
}
