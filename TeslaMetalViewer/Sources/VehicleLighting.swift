import simd

/// Rear lamp diffuser calibration and indicator timing.
enum VehicleLighting {
    static func blinkOn(time: Float) -> Bool {
        // 80 flashes/minute, with a short dark interval between flashes.
        let phase = time/0.75
        return phase-floor(phase) < 0.5
    }

    static func calibrateRear(_ scene: inout ModelSceneData, model: String, running: Bool, braking: Bool) {
        if model == "models_plaid.glb" {
            // Keep shared US signal overlays in front of the coplanar running
            // outline so a dark-phase ray can reach that steady source surface.
            for i in scene.geometries.indices where scene.geometries[i].lightRole?.contains("turn_rear_") == true {
                for j in scene.geometries[i].vertices.indices { scene.geometries[i].vertices[j].position.x -= 0.002 }
            }
        }
        if model == "cybertruck.glb" {
            // The side fixtures contain two vertically stacked circuits. Align
            // the split with the authored continuous running strip's lower edge.
            let bar = scene.geometries.first { $0.lightRole == "tail_bar" }
            let boundary = bar?.indices.map { bar!.vertices[Int($0)].position.y }.min()
            if let boundary {
                var upperSections: [GeometryData] = []
                for i in scene.geometries.indices where scene.geometries[i].lightRole?.contains("turn_rear_") == true {
                    let original = scene.geometries[i]
                    func clipped(upper: Bool) -> GeometryData {
                        var g = original; g.vertices = []; g.indices = []
                        for t in stride(from: 0,to: original.indices.count,by: 3) {
                            let input = (0..<3).map { original.vertices[Int(original.indices[t+$0])] }
                            var polygon: [RaytraceVertex] = []
                            for k in 0..<3 {
                                let a = input[k], b = input[(k+1)%3]
                                let insideA = upper ? a.position.y >= boundary : a.position.y <= boundary
                                let insideB = upper ? b.position.y >= boundary : b.position.y <= boundary
                                if insideA { polygon.append(a) }
                                if insideA != insideB {
                                    let f = (boundary-a.position.y)/(b.position.y-a.position.y)
                                    var v = a; v.position = a.position+(b.position-a.position)*f
                                    v.normal = a.normal+(b.normal-a.normal)*f
                                    v.uv = a.uv+(b.uv-a.uv)*f; polygon.append(v)
                                }
                            }
                            if polygon.count >= 3 {
                                let start = UInt32(g.vertices.count); g.vertices += polygon
                                for k in 1..<(polygon.count-1) { g.indices += [start,start+UInt32(k),start+UInt32(k+1)] }
                            }
                        }
                        return g
                    }
                    var upper = clipped(upper: true)
                    upper.lightRole = "rear_running"; upper.componentName += "/Upper running circuit"
                    upper.textures.w &= ~(32768|262144)
                    upper.emissive = running && !braking ? 2.4 : 0
                    upperSections.append(upper)
                    scene.geometries[i] = clipped(upper: false)
                }
                scene.geometries += upperSections
            }
        }
        if model == "bayberry_e41.glb" {
            // This source trim has outer running circuits but no center emitter.
            // Fit the missing narrow diffuser to the authored upper rear panel.
            let outer = scene.geometries.filter { $0.lightRole == "rear_running" }
                .flatMap { g in g.indices.map { g.vertices[Int($0)].position } }
            if let top = outer.map(\.y).max(), let halfWidth = outer.map({ abs($0.z) }).min() {
                let y = top-0.018
                var panel: [SIMD4<Float>] = []
                for g in scene.geometries where g.lightRole == nil && g.transmission < 0.1 {
                    for index in g.indices {
                        let p = g.vertices[Int(index)].position
                        if p.x < -1 && abs(p.y-y)<0.025 && abs(p.z)<halfWidth+0.04 { panel.append(p) }
                    }
                }
                if !panel.isEmpty {
                    var strip = GeometryData()
                    strip.componentName = "BayberryE41/Center rear running diffuser"
                    strip.sourceMaterial = "viewer://rear-center-diffuser"
                    strip.lightRole = "rear_running_center"; strip.isLampOverlay = true
                    strip.emissionColor = SIMD3(1,0.004,0.001); strip.emissive = running ? 2.4 : 0
                    strip.baseColor = SIMD3(repeating: 0.01); strip.textures.w |= 8192|524288
                    for section in 0..<48 {
                        let za = -halfWidth+2*halfWidth*Float(section)/48
                        let zb = -halfWidth+2*halfWidth*Float(section+1)/48
                        func point(_ z: Float, _ dy: Float) -> SIMD3<Float> {
                            let nearby = panel.filter { abs($0.z-z)<0.04 }
                            let x = nearby.map(\.x).min() ?? panel.min { abs($0.z-z)<abs($1.z-z) }!.x
                            return SIMD3(x-0.004,y+dy,z)
                        }
                        let start = UInt32(strip.vertices.count)
                        strip.vertices += [point(za,-0.004),point(zb,-0.004),point(zb,0.004),point(za,0.004)]
                            .map { RaytraceVertex(position: $0,normal: SIMD3(-1,0,0)) }
                        strip.indices += [0,1,2,0,2,3].map { start+UInt32($0) }
                    }
                    scene.geometries.append(strip)
                }
            }
            // The US lamp diffuser is coplanar with the optical cover. Separate
            // the emitter by 2 mm so transmission rays cannot skip past it.
            for i in scene.geometries.indices where scene.geometries[i].lightRole?.contains("turn_rear_") == true {
                for j in scene.geometries[i].vertices.indices { scene.geometries[i].vertices[j].position.x -= 0.002 }
            }
        }
        guard model == "bayberry.glb" || model == "bayberry_e80.glb" else { return }
        for i in scene.geometries.indices where scene.geometries[i].lightRole?.contains("turn_rear_") == true {
            // E80 uses a differently named optical cover, but shares the red
            // rear signal circuit. Override the amber atlas on emitters only.
            scene.geometries[i].emissionTexture = -1
            scene.geometries[i].emissionColor = SIMD3(1,0.004,0.001)
        }
        for i in scene.geometries.indices where scene.geometries[i].lightRole == "parking" {
            scene.geometries[i].textures.w |= 8192
            scene.geometries[i].emissionTexture = -1
            scene.geometries[i].emissionColor = SIMD3(1,0.004,0.001)
        }
        let lens = scene.geometries.filter { $0.sourceMaterial.lowercased().contains("glass_lights") }
            .flatMap { g in g.indices.map { g.vertices[Int($0)].position } }.filter { $0.x < -1 }
        guard !lens.isEmpty else { return }
        for index in scene.geometries.indices {
            let role = scene.geometries[index].lightRole ?? ""
            guard ["turn_rear_left","turn_rear_right"].contains(role) else { continue }
            var g = scene.geometries[index]
            let original = g.indices.map { g.vertices[Int($0)].position }
            let z0 = original.map(\.z).min()!
            let z1 = original.map(\.z).max()!
            let y = (original.map(\.y).min()!+original.map(\.y).max()!)/2
            let halfHeight: Float = 0.007
            let housing = scene.geometries.filter { $0.componentName.contains("Trunk_Cover") && $0.transmission < 0.1 && $0.isPaint == 0 }
                .flatMap { g in g.indices.map { g.vertices[Int($0)].position } }
                .filter { $0.x < -1 && abs($0.y-y)<0.05 }
            let envelope = lens + housing
            g.vertices = []; g.indices = []
            let segments = 24
            for section in 0..<segments {
                let f0 = Float(section)/Float(segments), f1 = Float(section+1)/Float(segments)
                let za = z0+(z1-z0)*f0, zb = z0+(z1-z0)*f1
                func point(_ z: Float, _ dy: Float) -> SIMD3<Float> {
                    let nearest = envelope.min { abs($0.z-z)<abs($1.z-z) }!
                    let neighbors = envelope.filter { abs($0.z-nearest.z)<0.022 }
                    return SIMD3((neighbors.map(\.x).min() ?? nearest.x)-0.004,y+dy,z)
                }
                let offset = UInt32(g.vertices.count)
                for pt in [point(za,-halfHeight),point(zb,-halfHeight),point(zb,halfHeight),point(za,halfHeight)] {
                    g.vertices.append(RaytraceVertex(position: pt,normal: SIMD3(-1,0,0)))
                }
                g.indices += [0,1,2,0,2,3].map { UInt32($0)+offset }
            }
            g.emissionTexture = -1
            g.emissionColor = SIMD3(1,0.004,0.001)
            g.textures.w |= 8192 // Light exits toward the rear, never into the cabin.
            scene.geometries[index] = g
        }
    }

}
