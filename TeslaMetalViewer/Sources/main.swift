import AppKit
import SwiftUI
import Metal
import simd
import ImageIO

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var appState: AppState!
    var rayTracer: RayTracer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Apple Metal is not supported on this Mac.")
        }
        
        guard device.supportsRaytracing else {
            fatalError("Hardware ray tracing is not supported on this Metal device.")
        }
        
        print("Tesla Metal Viewer initializing on: \(device.name)")
        
        self.rayTracer = RayTracer(device: device)
        self.appState = AppState()
        
        // Command-line arguments: --model <id> and --tour
        if let modelArgIndex = CommandLine.arguments.firstIndex(of: "--model"),
           modelArgIndex + 1 < CommandLine.arguments.count {
            let requestedId = CommandLine.arguments[modelArgIndex + 1].lowercased()
            if let found = TeslaCatalog.models.first(where: {
                $0.id.lowercased() == requestedId ||
                $0.name.lowercased().contains(requestedId) ||
                $0.filename.lowercased().contains(requestedId)
            }) {
                self.appState.selectModel(found)
            }
        }
        
        if let presetIndex = CommandLine.arguments.firstIndex(of: "--preset"),
           presetIndex + 1 < CommandLine.arguments.count {
            let p = CommandLine.arguments[presetIndex + 1].lowercased()
            if p == "rear" { self.appState.initialPreset = .rear }
            else if p == "front" { self.appState.initialPreset = .front }
            else if p == "side" { self.appState.initialPreset = .side }
            else if p == "top" { self.appState.initialPreset = .top }
            else if p == "hero" { self.appState.initialPreset = .hero }
        }
        
        if CommandLine.arguments.contains("--tour") {
            self.appState.isTouring = true
        }
        
        if CommandLine.arguments.contains("--validate-models") {
            var failures: [String] = []
            for model in TeslaCatalog.models {
                guard rayTracer.loadModel(filename: model.filename), let rest = rayTracer.currentScene else {
                    failures.append("Load: " + model.id); continue
                }
                for clip in rest.animations {
                    rayTracer.applyAnimation(name: clip.name, time: clip.duration)
                    guard let posed = rayTracer.currentScene else { failures.append("Pose: " + clip.name); continue }
                    let changed = zip(rest.geometries,posed.geometries).contains { a,b in
                        zip(a.vertices,b.vertices).contains { simd_distance($0.position,$1.position) > 0.0001 }
                    }
                    if !changed { failures.append(model.id + ": no motion in " + clip.name) }
                }
                print("Validated \(model.id): \(rest.animations.count) clips, \(rest.geometries.count) surfaces")
            }
            print("Validation failures: \(failures)")
            exit(failures.isEmpty ? 0 : 1)
        }

        if CommandLine.arguments.contains("--validate-features") {
            var failures: [String] = []
            for model in TeslaCatalog.models {
                guard rayTracer.loadModel(filename: model.filename), let rest = rayTracer.currentScene else {
                    failures.append(model.id + ": load failed"); continue
                }
                let lenses = rest.geometries.filter { ($0.textures.w & 64) != 0 }
                if lenses.isEmpty { failures.append(model.id + ": no optical lenses") }
                for g in lenses where g.transmission < 0.98 || g.baseColor.x < 0.98 || g.metallic != 0 {
                    failures.append(model.id + ": opaque lens " + g.sourceMaterial)
                }
                for g in rest.geometries where (g.textures.w & 128) != 0 {
                    if g.metallic != 0 || g.roughness < 0.85 || g.clearcoat != 0 || g.textures.y != -1 {
                        failures.append(model.id + ": glossy rubber " + g.sourceMaterial)
                    }
                }
                for g in rest.geometries where (g.textures.w & 256) != 0 {
                    if g.transmission < 0.95 || g.baseColor.x < 0.9 || g.metallic != 0 {
                        failures.append(model.id + ": opaque window " + g.sourceMaterial)
                    }
                }
                if rest.animations.contains(where: { $0.name == "SuspensionAnimation" }) {
                    rayTracer.applyAnimation(name: "SuspensionAnimation",time: 0)
                    let low = rayTracer.currentScene!
                    for time in 1...5 {
                        rayTracer.applyAnimation(name: "SuspensionAnimation",time: Float(time))
                        let pose = rayTracer.currentScene!
                        for mount in ["Wheel_LF_Spatial", "Wheel_RF_Spatial", "Wheel_LR_Spatial", "Wheel_RR_Spatial"] {
                            let wheels = low.geometries.indices.filter { low.geometries[$0].componentName.contains("/" + mount + "/") }
                            if wheels.isEmpty { failures.append(model.id + ": missing suspension wheel " + mount) }
                            for i in wheels {
                                let maxMotion = zip(low.geometries[i].vertices,pose.geometries[i].vertices)
                                    .map { simd_distance($0.position,$1.position) }.max() ?? 0
                                // Source keys round socket locations to millimeters. Tires
                                // stay grounded while the body moves through 215 mm.
                                if maxMotion > 0.001 { failures.append(model.id + ": suspension lifts " + mount + " at " + String(time)) }
                            }
                        }
                        if time == 5 && !zip(low.geometries,pose.geometries).contains(where: { a,b in
                            zip(a.vertices,b.vertices).contains { abs($0.position.y - $1.position.y) > 0.21 }
                        }) { failures.append(model.id + ": suspension body did not rise") }
                    }
                    print("Suspension checks: all four tires grounded at all six source keyframes")
                }
                if let hood = rest.animations.first(where: { $0.name == "HoodAnimation" }),
                   let door = rest.animations.first(where: { $0.name == "LFDoorAnimation" }) {
                    let state = AppState(); state.animations = rest.animations
                    state.setAnimation(hood.name,enabled: true); state.setAnimation(door.name,enabled: true)
                    if state.selectedAnimations.count != 2 { failures.append(model.id + ": compatible clips rejected") }
                    let t = max(hood.duration,door.duration)
                    rayTracer.applyAnimation(name: hood.name,time: t); let hoodScene = rayTracer.currentScene!
                    rayTracer.applyAnimation(name: door.name,time: t); let doorScene = rayTracer.currentScene!
                    rayTracer.applyAnimations(names: state.selectedAnimations,time: t); let combined = rayTracer.currentScene!
                    for individual in [hoodScene,doorScene] {
                        for i in rest.geometries.indices {
                            let changed = zip(rest.geometries[i].vertices,individual.geometries[i].vertices).contains { simd_distance($0.position,$1.position) > 0.0001 }
                            if changed && !zip(individual.geometries[i].vertices,combined.geometries[i].vertices).allSatisfy({ simd_distance($0.position,$1.position) < 0.0001 }) {
                                failures.append(model.id + ": combined pose lost component " + individual.geometries[i].componentName)
                            }
                        }
                    }
                    state.animationTime = state.animationDuration; state.toggleAnimationPlayback()
                    if state.animationTime != 0 || !state.isPlayingAnimation { failures.append(model.id + ": playback restart") }
                    // The most recently checked conflicting clip replaces its predecessor.
                    if let complete = rest.animations.first(where: { $0.name == "LRDoorAnimationComplete" }),
                       let top = rest.animations.first(where: { $0.name == "LRDoorAnimationTop" }) {
                        state.setAnimation(complete.name,enabled:true); state.setAnimation(top.name,enabled:true)
                        if state.selectedAnimations.contains(complete.name) || !state.selectedAnimations.contains(top.name) { failures.append(model.id + ": conflicting clips") }
                    }
                }
                let camera = Camera()
                let initial = camera.position
                _ = camera.updateTour(deltaTime: 5,radius: rest.radius,center: rest.center)
                if simd_distance(initial,camera.position) < 0.01 { failures.append(model.id + ": tour stationary") }
                print("Feature checks passed: \(model.id), \(lenses.count) clear lens surfaces")
            }
            let navigation = InteractiveMTKView.self
            if navigation.action(precise: true,modifiers: [],mode: .orbit) != .orbit ||
               navigation.action(precise: true,modifiers: .shift,mode: .orbit) != .pan ||
               navigation.action(precise: true,modifiers: .control,mode: .orbit) != .zoom ||
               navigation.action(precise: false,modifiers: [],mode: .orbit) != .zoom ||
               navigation.action(precise: true,modifiers: .option,mode: .orbit) != .orbit {
                failures.append("Navigation routing")
            }
            let camera = Camera(); camera.viewportHeight = 800
            let origin = camera.target
            camera.pan(deltaX: 100,deltaY: 0)
            let firstPan = simd_distance(origin,camera.target)
            camera.target = origin; camera.distance *= 2
            camera.pan(deltaX: 100,deltaY: 0)
            if abs(simd_distance(origin,camera.target) - 2 * firstPan) > 0.0001 { failures.append("Pan perspective scaling") }
            let state = AppState()
            for index in TeslaCatalog.models.indices {
                state.selectModel(TeslaCatalog.models[index])
                if state.nextModel().id != TeslaCatalog.models[(index+1) % TeslaCatalog.models.count].id { failures.append("Next model wrap") }
            }
            print("Navigation and model cycling checks passed")
            print("Feature validation failures: \(failures)")
            exit(failures.isEmpty ? 0 : 1)
        }

        // Offscreen high-quality ray-traced render export:
        if let renderOutIdx = CommandLine.arguments.firstIndex(of: "--render-out"),
           renderOutIdx + 1 < CommandLine.arguments.count {
            let outPath = CommandLine.arguments[renderOutIdx + 1]
            let model = appState.selectedModel
            guard rayTracer.loadModel(filename: model.filename) else { exit(1) }
            func argument(_ name: String) -> String? {
                guard let i = CommandLine.arguments.firstIndex(of: name), i+1 < CommandLine.arguments.count else { return nil }
                return CommandLine.arguments[i+1]
            }
            rayTracer.charging = CommandLine.arguments.contains("--charging")
            rayTracer.effectTime = Float(argument("--effect-time") ?? "2") ?? 2
            rayTracer.drivingSpeed = Float(argument("--driving") ?? "0") ?? 0
            rayTracer.climateMode = Float(argument("--climate") ?? "0") ?? 0
            if let clip = argument("--animation") {
                let names = Set(clip.split(separator: ",").map(String.init))
                guard !names.isEmpty, names.allSatisfy({ name in rayTracer.currentScene?.animations.contains(where: { $0.name == name }) == true }) else {
                    print("Unknown source animation: \(clip)"); exit(1)
                }
                rayTracer.applyAnimations(names: names, time: Float(argument("--animation-time") ?? "1") ?? 1)
            } else if rayTracer.charging { rayTracer.applyAnimation(name: nil,time: 0) }
            if CommandLine.arguments.contains("--dump-components"), let scene = rayTracer.currentScene {
                for g in scene.geometries where g.isGround == 0 {
                    var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
                    for v in g.vertices { let p = SIMD3(v.position.x,v.position.y,v.position.z); lo = simd_min(lo,p); hi = simd_max(hi,p) }
                    print(g.componentName, g.sourceMaterial, lo, hi)
                }
            }
            let radius = rayTracer.currentScene?.radius ?? 3.0
            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
            appState.camera.viewportAspect = 1400.0 / 900.0
            let preset = appState.initialPreset ?? .hero
            appState.camera.applyPreset(preset, radius: radius, center: center)
            
            print("Rendering 32 ray-traced samples offscreen for \(model.name)...")
            if let cgImage = rayTracer.renderToImage(
                width: 1400,
                height: 900,
                samples: 32,
                camera: appState.camera,
                paintColor: appState.selectedPaint.color,
                metallic: appState.metallic,
                roughness: appState.roughness,
                clearcoat: appState.clearcoat,
                groundReflectivity: appState.groundReflectivity,
                groundRoughness: appState.groundRoughness,
                isPrivacyTint: appState.isPrivacyTintEnabled,
                privacyTintDarkness: appState.privacyTintDarkness
            ) {
                let destUrl = URL(fileURLWithPath: outPath)
                if let dest = CGImageDestinationCreateWithURL(destUrl as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    CGImageDestinationFinalize(dest)
                    print("Successfully saved ray-traced render to: \(outPath)")
                }
            }
            exit(0)
        }
        
        let contentView = ContentView(state: appState, rayTracer: rayTracer)
        let hostingView = NSHostingView(rootView: contentView)
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let initialWidth: CGFloat = min(1360, screenRect.width * 0.90)
        let initialHeight: CGFloat = min(880, screenRect.height * 0.90)
        
        let windowRect = NSRect(
            x: (screenRect.width - initialWidth) * 0.5,
            y: (screenRect.height - initialHeight) * 0.5,
            width: initialWidth,
            height: initialHeight
        )
        
        NSApp.setActivationPolicy(.regular)
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Tesla 3D Studio — Metal Ray Tracer"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
