import Foundation
import Metal
import simd

/// Exercise actual GPU frames, deterministic previews, progressive quality and
/// switching modes without changing the selected pose or geometry.
enum RenderingModeValidation {
    static func run(device: MTLDevice) -> [String] {
        var failures: [String] = []
        let tracer = RayTracer(device: device)
        for (id,lighting) in [("bayberry",LightingPreset.studio),("cybertruck",.coastalStorm)] {
            tracer.lighting = lighting
            guard let model = TeslaCatalog.models.first(where: { $0.id == id }),
                  tracer.loadModel(filename: model.filename), let scene = tracer.currentScene else {
                failures.append(id + ": load"); continue
            }
            let clips: Set<String> = id == "cybertruck" ? ["TonneauAnimation"] : ["TrunkAnimation"]
            tracer.applyAnimations(names: clips,time: id == "cybertruck" ? 5 : 0.6)
            let topology = tracer.currentScene!.topologyID
            let camera = Camera(); camera.applyPreset(.rear,radius: scene.radius,center: scene.center)
            let cameraPosition = camera.position
            func render(_ mode: RenderMode, samples: Int = 1) -> (Data,Double)? {
                tracer.renderMode = mode
                guard let image = tracer.renderToImage(width: 640,height: 400,samples: samples,camera: camera,
                    paintColor: SIMD3(0.04,0.15,0.35),metallic: 0.65,roughness: 0.25,clearcoat: 0.7,
                    groundReflectivity: 0.25,groundRoughness: 0.25,isPrivacyTint: false,privacyTintDarkness: 0),
                      let pixels = image.dataProvider?.data else { return nil }
                return (pixels as Data,tracer.lastExportGPUSeconds)
            }
            guard let fast = render(.realtime), let requestedMany = render(.realtime,samples: 64),
                  let quality = render(.rayTraced), let refined = render(.rayTraced,samples: 8),
                  let switchedBack = render(.realtime) else {
                failures.append(id + ": render"); continue
            }
            if fast.0 != requestedMany.0 || fast.0 != switchedBack.0 {
                failures.append(id + ": real-time frame accumulated samples or leaked previous mode")
            }
            if quality.0 == fast.0 || quality.0 == refined.0 {
                failures.append(id + ": ray tracing or progressive refinement inactive")
            }
            let bytes = [UInt8](fast.0)
            let colors = stride(from: 0,to: bytes.count,by: 4).map { Int(bytes[$0])+Int(bytes[$0+1])+Int(bytes[$0+2]) }
            if (colors.max() ?? 0)-(colors.min() ?? 0)<50 { failures.append(id + ": empty real-time image") }
            if tracer.currentScene?.topologyID != topology || camera.position != cameraPosition {
                failures.append(id + ": mode switch changed camera or scene")
            }
            tracer.renderMode = .rayTraced; tracer.sampleIndex = 100; tracer.renderMode = .realtime
            if tracer.sampleIndex != 0 { failures.append(id + ": stale accumulation on mode switch") }
            var fastTimes: [Double] = [], qualityTimes: [Double] = []
            for _ in 0..<3 {
                if let result = render(.realtime) { fastTimes.append(result.1) }
                if let result = render(.rayTraced) { qualityTimes.append(result.1) }
            }
            if fastTimes.count == 3 && qualityTimes.count == 3 {
                let fastMS = fastTimes.sorted()[1]*1000, qualityMS = qualityTimes.sorted()[1]*1000
                print(String(format: "GPU modes %@, 640x400 single frame: real-time %.2f ms, ray traced %.2f ms (%.2fx); progressive 8-sample %.2f ms",id,fastMS,qualityMS,qualityMS/max(fastMS,0.001),refined.1*1000))
            }
        }
        return failures
    }
}
