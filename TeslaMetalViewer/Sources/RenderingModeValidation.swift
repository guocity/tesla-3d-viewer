import Foundation
import Metal
import simd

/// Exercise actual GPU frames, deterministic previews, progressive quality and
/// switching modes without changing the selected pose or geometry.
enum RenderingModeValidation {
    static func run(device: MTLDevice) -> [String] {
        var failures: [String] = []
        let tracer = RayTracer(device: device)
        if let probes=tracer.validateCabinOptics(), probes.count==16 {
            // Same upholstery occlusion function used by direct, transmitted,
            // reflected and real-time seats; verify blockers, not image inequality.
            let ambient=Array(probes.suffix(8))
            if ambient[0]>0.01 || ambient[2]>=ambient[1] || ambient[7]>=ambient[5]
                || ambient[3]<0.99 || ambient[1]<0.94
                || ambient[5]>=ambient[1] || ambient[6]>=ambient[5] {
                failures.append("Missing upholstery ambient shadows/transmission: " + String(describing:ambient))
            }
            print("GPU upholstery ambient visibility (solid, clear, glass/body, open, duplicate, privacy, two panes, privacy/body): \(ambient)")
        } else { failures.append("Upholstery shadow GPU probe failed") }
        var presetImages: [LightingPreset: Data] = [:]
        for (id,lighting) in [("bayberry",LightingPreset.studio),("bayberry",.overcast),
                              ("bayberry",.goldenHour),("bayberry",.blueHour),("bayberry",.neonRain),
                              ("bayberry",.coastalStorm),("cybertruck",.coastalStorm)] {
            tracer.seatFinish = .original
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
            if id == "bayberry" { presetImages[lighting] = refined.0 }
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
            tracer.seatFinish = .whiteVegan
            guard let whiteFast = render(.realtime), let whiteRepeat = render(.realtime),
                  let whiteQuality = render(.rayTraced,samples: 8) else {
                failures.append(id + ": white upholstery render"); continue
            }
            if whiteFast.0 != whiteRepeat.0 { failures.append(id + ": unstable white upholstery") }
            if whiteFast.0 == fast.0 || whiteQuality.0 == refined.0 {
                failures.append(id + ": seat finish not visible in " + lighting.rawValue)
            }
            tracer.seatFinish = .original
            tracer.renderMode = .rayTraced; tracer.sampleIndex = 100; tracer.renderMode = .realtime
            if tracer.sampleIndex != 0 { failures.append(id + ": stale accumulation on mode switch") }
            var fastTimes: [Double] = [], qualityTimes: [Double] = []
            for _ in 0..<3 {
                if let result = render(.realtime) { fastTimes.append(result.1) }
                if let result = render(.rayTraced) { qualityTimes.append(result.1) }
            }
            if fastTimes.count == 3 && qualityTimes.count == 3 {
                let fastMS = fastTimes.sorted()[1]*1000, qualityMS = qualityTimes.sorted()[1]*1000
                print(String(format: "GPU modes %@, 640x400 single frame: real-time %.2f ms, ray traced %.2f ms (%.2fx); progressive 8-sample %.2f ms",id + "/" + lighting.rawValue,fastMS,qualityMS,qualityMS/max(fastMS,0.001),refined.1*1000))
            }
        }
        if Set(presetImages.values).count != LightingPreset.allCases.count {
            failures.append("Outdoor ray-traced presets did not produce distinct images")
        }
        return failures
    }
}
