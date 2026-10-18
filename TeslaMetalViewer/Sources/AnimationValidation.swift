import Foundation
import Metal
import simd

/// Compare the fast pose path with fresh source evaluation, including reversal,
/// combined clips, wheel motion and lamp/charging topology changes.
enum AnimationValidation {
    static func run(device: MTLDevice) -> [String] {
        var failures: [String] = []
        for model in TeslaCatalog.models {
            guard let url = TeslaCatalog.resolveModelPath(filename: model.filename),
                  let rest = GLBLoader.loadModel(from: url, device: device, usePoseCache: false) else {
                failures.append(model.id + ": load"); continue
            }
            var maxError: Float = 0
            func compare(_ names: Set<String>, _ time: Float, wheel: Float = 0, charging: Bool = false) {
                guard let fast = GLBLoader.loadModel(from: url, device: device, selectedAnimations: names,
                                                     time: time, charging: charging, wheelDegrees: wheel),
                      let reference = GLBLoader.loadModel(from: url, device: device, selectedAnimations: names,
                                                          time: time, charging: charging, wheelDegrees: wheel, usePoseCache: false) else {
                    failures.append(model.id + ": pose load"); return
                }
                guard fast.geometries.count == reference.geometries.count else {
                    failures.append(model.id + ": surface count"); return
                }
                for (a,b) in zip(fast.geometries,reference.geometries) {
                    guard a.indices == b.indices, a.vertices.count == b.vertices.count,
                          a.textures == b.textures, a.emissive == b.emissive else {
                        failures.append(model.id + ": surface mismatch " + a.componentName); continue
                    }
                    for (v,w) in zip(a.vertices,b.vertices) {
                        let error = max(simd_distance(v.position,w.position),simd_distance(v.normal,w.normal))
                        if !error.isFinite || error > 0.0002 {
                            failures.append(model.id + ": pose mismatch " + a.componentName); break
                        }
                        maxError = max(maxError,error)
                    }
                }
            }
            for clip in rest.animations {
                compare([clip.name],clip.duration * 0.37)
                compare([clip.name],clip.duration)
                compare([clip.name],0)
            }
            let combined = Set(rest.animations.filter { ["HoodAnimation","LFDoorAnimation"].contains($0.name) }.map(\.name))
            compare(combined,0.5,wheel: 135)
            compare([],0,wheel: -85,charging: true)
            compare([],0)
            print("Pose equivalence: \(model.id), \(rest.animations.count) clips, max error \(maxError)")
        }
        // Report CPU pose cost separately from rendering; this is not an FPS claim.
        for id in ["modelx_plaid","cybertruck"] {
            guard let model = TeslaCatalog.models.first(where: { $0.id == id }),
                  let url = TeslaCatalog.resolveModelPath(filename: model.filename) else { continue }
            var times: [Double] = []
            for cached in [false,true] {
                _ = GLBLoader.loadModel(from: url,device: device,usePoseCache: false)
                let start = ProcessInfo.processInfo.systemUptime
                for frame in 0..<60 {
                    _ = GLBLoader.loadModel(from: url,device: device,selectedAnimations: ["HoodAnimation"],
                                           time: Float(frame)/60,wheelDegrees: Float(frame)*5,usePoseCache: cached)
                }
                times.append((ProcessInfo.processInfo.systemUptime-start)/60*1000)
            }
            print(String(format: "Pose CPU %@: fresh %.2f ms, cached %.2f ms (%.1fx)",id,times[0],times[1],times[0]/times[1]))
        }
        // Render the same final pose through refit and a fresh BVH build.
        // This checks GPU geometry/buffer reuse, beyond CPU vertex equivalence.
        let tracer = RayTracer(device: device)
        for id in ["modelx_plaid","cybertruck"] {
            guard let model = TeslaCatalog.models.first(where: { $0.id == id }),
                  tracer.loadModel(filename: model.filename), let rest = tracer.currentScene else { continue }
            let camera = Camera(); camera.applyPreset(.hero,radius: rest.radius,center: rest.center)
            let clip = id == "cybertruck" ? "SuspensionAnimation" : "LFDoorAnimation"
            for time: Float in [0.1,0.3,0.7,1] { tracer.applyAnimation(name: clip,time: time) }
            func render() -> Data? {
                guard let image = tracer.renderToImage(width: 320,height: 200,samples: 1,camera: camera,
                    paintColor: SIMD3(0.3,0.35,0.4),metallic: 0.7,roughness: 0.2,clearcoat: 1,
                    groundReflectivity: 0.4,groundRoughness: 0.2,isPrivacyTint: false,privacyTintDarkness: 0),
                      let data = image.dataProvider?.data else { return nil }
                return data as Data
            }
            let refitted = render()
            tracer.lighting = .overcast; tracer.lighting = .studio
            guard let a = refitted, let b = render(), a.count == b.count else {
                failures.append(id + ": GPU render failed"); continue
            }
            let error = zip(a,b).reduce(0.0) { $0 + Double(abs(Int($1.0)-Int($1.1))) } / Double(a.count)
            if error > 1 { failures.append(id + ": refit/build GPU image mismatch") }
            print(String(format: "GPU refit/build %@: mean pixel error %.4f / 255",id,error))
        }
        return failures
    }
}
