import Foundation
import Metal
import simd

/// Regression checks on the actual loaded source surfaces, across all lamp states.
enum LightingValidation {
    static func run(device: MTLDevice) -> [String] {
        var failures: [String] = []
        if MemoryLayout<GeometryInfoGPU>.stride != 80 { failures.append("Geometry GPU layout") }
        for model in TeslaCatalog.models {
            guard let url = TeslaCatalog.resolveModelPath(filename: model.filename),
                  let off = GLBLoader.loadModel(from: url,device: device,headlightsOn: false,drlOn: false) else {
                failures.append(model.id + ": load failed"); continue
            }
            if off.geometries.contains(where: {
                ($0.textures.w & 65536) != 0 || $0.sourceMaterial.lowercased().contains("led_strip")
                    || $0.sourceMaterial.lowercased().hasSuffix("/cybertruck/led.material")
                    || $0.sourceMaterial.hasPrefix("viewer://single-interior")
            }) { failures.append(model.id + ": interior lightbar remains") }
            let states: [(String,Bool,Bool,Bool,Bool,Bool)] = [
                ("running",true,true,false,false,false), ("DRL only",false,true,false,false,false),
                ("braking",false,false,true,false,false), ("left",false,false,false,true,false),
                ("right",false,false,false,false,true)]
            for (name,head,drl,brake,left,right) in states {
                guard let on = GLBLoader.loadModel(from: url,device: device,headlightsOn: head,drlOn: drl,
                                                  brakeLightsOn: brake,turnSignalLeftOn: left,turnSignalRightOn: right) else {
                    failures.append(model.id + ": " + name + " failed"); continue
                }
                guard on.geometries.count == off.geometries.count else {
                    failures.append(model.id + ": " + name + " changes surface count"); continue
                }
                for (a,b) in zip(off.geometries,on.geometries) {
                    if a.baseColor != b.baseColor || a.isPaint != b.isPaint || a.metallic != b.metallic
                        || a.roughness != b.roughness || a.transmission != b.transmission || a.textures != b.textures
                        || a.sourceMaterial != b.sourceMaterial || a.indices != b.indices {
                        failures.append(model.id + ": " + name + " modifies surface material/geometry: " + a.componentName)
                    }
                    if b.lightRole != nil && (b.isPaint != 0 || b.transmission > 0 || (b.textures.w & 128) != 0) {
                        failures.append(model.id + ": lamp control includes paint/glass/rubber")
                    }
                }
                let emitters = on.geometries.filter { $0.lightRole != nil && $0.emissive > 0 }
                if emitters.isEmpty { failures.append(model.id + ": " + name + " has no active emitters") }
                if name == "left" || name == "right" {
                    let role = name == "left" ? "turn_rear_left" : "turn_rear_right"
                    let combined = name == "left" ? "turn_left" : "turn_right"
                    if !emitters.contains(where: { g in
                        let roles = Set((g.lightRole ?? "").split(separator: ",").map(String.init))
                        guard roles.contains(role) || roles.contains(combined) else { return false }
                        return g.indices.contains { g.vertices[Int($0)].position.x < -0.1 }
                    }) {
                        failures.append(model.id + ": missing active " + role)
                    }
                }
                if name == "running" {
                    for rear in [false,true] {
                        let present = emitters.contains { g in
                            let centerX = g.indices.reduce(Float(0)) { $0 + g.vertices[Int($1)].position.x } / Float(g.indices.count)
                            return rear ? centerX < -0.1 : centerX > 0.1
                        }
                        if !present { failures.append(model.id + ": missing " + (rear ? "rear" : "front") + " running lamps") }
                    }
                }
            }
            if off.geometries.contains(where: { $0.lightRole != nil && $0.emissive != 0 }) {
                failures.append(model.id + ": managed lamp still emits when switched off")
            }
            if model.id == "cybertruck" {
                if let running=GLBLoader.loadModel(from:url,device:device) {
                    for g in running.geometries where g.lightRole == "side_marker" || g.lightRole == "turn_left" || g.lightRole == "turn_right" {
                        if g.emissive != 0 { failures.append("Cybertruck: front turn fixture lit without turn input: " + g.componentName) }
                    }
                }
                let blackHousings=off.geometries.filter { $0.sourceMaterial.lowercased().contains("/glass_black") }
                if blackHousings.isEmpty || blackHousings.contains(where: { $0.transmission != 0 || ($0.textures.w & 256) != 0 }) {
                    failures.append("Cybertruck: black tailgate/lamp housings transmit light")
                }
            }
            if model.id == "models_plaid" {
                let tires = off.geometries.filter { $0.sourceMaterial.contains("Tire_Palladium") }
                if tires.count != 4 || tires.contains(where: { $0.textures.x < 0 }) { failures.append("Model S: missing four source tire textures") }
            }
            if model.id == "semi" {
                let body = off.geometries.filter { $0.componentName.hasSuffix("/Body") }
                if !body.contains(where: { $0.isPaint == 1 && $0.sourceMaterial.contains("::material_1") })
                    || !body.contains(where: { $0.isPaint == 0 && $0.textures.x >= 0 }) {
                    failures.append("Semi: lost inline paint / textured exterior split")
                }
            }
            print("Lighting/material checks: \(model.id), \(off.textures.count) textures, five lamp states")
        }
        return failures
    }
}
