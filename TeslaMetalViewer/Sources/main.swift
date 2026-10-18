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
            if p == "cabin" { self.appState.initialPreset = .cabin }
            else if p == "rear" { self.appState.initialPreset = .rear }
            else if p == "front" { self.appState.initialPreset = .front }
            else if p == "side" { self.appState.initialPreset = .side }
            else if p == "top" { self.appState.initialPreset = .top }
            else if p == "hero" { self.appState.initialPreset = .hero }
        }
        
        if CommandLine.arguments.contains("--tour") {
            self.appState.isTouring = true
        }
        
        if CommandLine.arguments.contains("--validate-lights") {
            let failures = LightingValidation.run(device: device)
            print("Lighting validation failures: \(failures)")
            exit(failures.isEmpty ? 0 : 1)
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
                let surrounds = rest.geometries.filter { ($0.textures.w & 1024) != 0 }
                if surrounds.isEmpty { failures.append(model.id + ": missing window surround mask") }
                for g in surrounds where g.isPaint != 0 || g.transmission > 0 || (g.textures.w & 128) != 0 {
                    failures.append(model.id + ": window trim overlaps paint, glass, or rubber material")
                }
                let tourState = AppState(); tourState.isTouring = true; tourState.camera.tourTime = 11.5
                tourState.selectModel(model); tourState.frameLoadedModel(radius: rest.radius,center: rest.center)
                if !tourState.isTouring || abs(tourState.camera.tourTime-11.5) > 0.0001 {
                    failures.append(model.id + ": model change interrupted tour")
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
            if let visibility=rayTracer.validateClimateOcclusion() {
                let expected: [Float]=[0,0.96,0,1,1]
                if zip(visibility,expected).contains(where: { abs($0-$1)>0.001 }) { failures.append("Climate occlusion: \(visibility)") }
                print("GPU climate visibility (opaque / glass / glass + body / open / behind airflow): \(visibility)")
            } else { failures.append("Climate GPU visibility probe failed") }
            if MemoryLayout<UniformsGPU>.stride != 480 { failures.append("GPU uniforms layout") }
            print("Navigation, tour-preserving model cycling, trim isolation and GPU layout checks passed")
            print("Feature validation failures: \(failures)")
            exit(failures.isEmpty ? 0 : 1)
        }

        // Offscreen high-quality ray-traced render export:
        if let renderOutIdx = CommandLine.arguments.firstIndex(of: "--render-out"),
           renderOutIdx + 1 < CommandLine.arguments.count {
            let outPath = CommandLine.arguments[renderOutIdx + 1]
            let model = appState.selectedModel
            rayTracer.showLightBeams = CommandLine.arguments.contains("--light-beams")
            let lampsOff = CommandLine.arguments.contains("--lights-off")
            guard rayTracer.loadModel(filename: model.filename, headlightsOn: !lampsOff, drlOn: !lampsOff,
                                      brakeLightsOn: CommandLine.arguments.contains("--brake-lights"),
                                      turnSignalLeftOn: CommandLine.arguments.contains("--signal-left"),
                                      turnSignalRightOn: CommandLine.arguments.contains("--signal-right")) else { exit(1) }
            func argument(_ name: String) -> String? {
                guard let i = CommandLine.arguments.firstIndex(of: name), i+1 < CommandLine.arguments.count else { return nil }
                return CommandLine.arguments[i+1]
            }
            if let value = argument("--lighting") {
                let key=value.lowercased().replacingOccurrences(of: "-",with: " ")
                guard let lighting=LightingPreset.allCases.first(where: { $0.rawValue.lowercased() == key }) else { print("Unknown lighting: " + value); exit(1) }
                rayTracer.lighting=lighting
            }
            if let value = argument("--trim") {
                guard let trim=WindowTrim.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased().replacingOccurrences(of: "-",with: " ") }) else { print("Unknown trim: " + value); exit(1) }
                rayTracer.windowTrim=trim
            }
            if let value=argument("--paint"),let paint=TeslaCatalog.paints.first(where: { $0.id == value }) { appState.selectedPaint=paint }
            rayTracer.exposure = max(0.4,min(2.5,Float(argument("--exposure") ?? "1") ?? 1))
            rayTracer.headlightReflection = max(0,min(1,Float(argument("--lens-reflection") ?? "0.15") ?? 0.15))
            rayTracer.rainIntensity = max(0,min(1,Float(argument("--rain") ?? "0.65") ?? 0.65))
            rayTracer.wetness = max(0,min(1,Float(argument("--wetness") ?? "0.85") ?? 0.85))
            rayTracer.charging = CommandLine.arguments.contains("--charging")
            rayTracer.effectTime = Float(argument("--effect-time") ?? "2") ?? 2
            rayTracer.weatherTime = rayTracer.effectTime
            rayTracer.cabinBrightness = max(0,min(3,Float(argument("--cabin-brightness") ?? "0.7") ?? 0.7))
            if let color = argument("--cabin-color"), color.count == 6, let hex = UInt32(color,radix: 16) {
                rayTracer.cabinColor = SIMD3(pow(Float((hex>>16)&255)/255,2.2),pow(Float((hex>>8)&255)/255,2.2),pow(Float(hex&255)/255,2.2))
            }
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
            if CommandLine.arguments.contains("--rear-straight") {
                appState.camera.azimuth = -Float.pi/2
                appState.camera.elevation = 0.10
            }
            if CommandLine.arguments.contains("--dump-lights"), let scene = rayTracer.currentScene {
                let vp = appState.camera.projectionMatrix(aspect: 1400.0/900.0) * appState.camera.viewMatrix()
                for g in scene.geometries where g.lightRole != nil || (g.textures.w & 65536) != 0 {
                    var lo = SIMD2<Float>(repeating: .infinity), hi = -lo
                    for i in g.indices {
                        let p = vp * g.vertices[Int(i)].position
                        let screen = SIMD2((p.x/p.w+1)*700,(1-p.y/p.w)*450)
                        lo = simd_min(lo,screen); hi = simd_max(hi,screen)
                    }
                    print(g.componentName, g.lightRole ?? "", "emission",g.emissive,"texture",g.emissionTexture,"pixels",lo,hi)
                    if g.lightRole == "parking" {
                        for t in stride(from: 0,to: min(g.indices.count,30),by: 3) {
                            let indices = Array(g.indices[t..<t+3])
                            let v = indices.reduce(SIMD4<Float>(repeating: 0)) { $0 + g.vertices[Int($1)].position } / 3
                            let clip = vp * v
                            print("parking sample",SIMD2((clip.x/clip.w+1)*700,(1-clip.y/clip.w)*450))
                        }
                    }
                }
                exit(0)
            }
            if let picks = argument("--pick"), let scene = rayTracer.currentScene {
                // CPU ray pick for identifying source surfaces under a render pixel.
                let invView = appState.camera.viewMatrix().inverse
                let invProj = appState.camera.projectionMatrix(aspect: 1400.0/900.0).inverse
                for pair in picks.split(separator: ";") {
                    let xy = pair.split(separator: ",").compactMap { Float($0) }
                    guard xy.count == 2 else { continue }
                    let ndc = SIMD2<Float>((xy[0]+0.5)/1400*2-1, -((xy[1]+0.5)/900*2-1))
                    let t = invProj * SIMD4(ndc.x,ndc.y,1,1)
                    let d4 = invView * SIMD4(t.x/t.w,t.y/t.w,t.z/t.w,0)
                    let dir = simd_normalize(SIMD3(d4.x,d4.y,d4.z)), org = appState.camera.position
                    var hits: [(Float,String)] = []
                    for g in scene.geometries where g.isGround == 0 {
                        for tri in stride(from: 0, to: g.indices.count, by: 3) {
                            let p = [0,1,2].map { let v = g.vertices[Int(g.indices[tri+$0])].position; return SIMD3(v.x,v.y,v.z) }
                            let e1 = p[1]-p[0], e2 = p[2]-p[0], pv = simd_cross(dir,e2), det = simd_dot(e1,pv)
                            if abs(det) < 1e-9 { continue }
                            let tv = org-p[0], u = simd_dot(tv,pv)/det
                            if u < 0 || u > 1 { continue }
                            let qv = simd_cross(tv,e1), v = simd_dot(dir,qv)/det
                            if v < 0 || u+v > 1 { continue }
                            let dist = simd_dot(e2,qv)/det
                            if dist > 0.01 { hits.append((dist,"\(g.componentName) | \(g.sourceMaterial) | tr=\(g.transmission) flags=\(g.textures.w) col=\(g.baseColor) met=\(g.metallic) tri=\(tri/3) pos=\(org+dir*dist)")) }
                        }
                    }
                    print("PICK \(xy):")
                    for h in hits.sorted(by: { $0.0 < $1.0 }).prefix(5) { print(String(format: "   %.3f ", h.0) + h.1) }
                }
                exit(0)
            }
            
            let renderSamples = max(1,min(1024,Int(argument("--samples") ?? "128") ?? 128))
            print("Rendering \(renderSamples) ray-traced samples offscreen for \(model.name)...")
            if let cgImage = rayTracer.renderToImage(
                width: 1400,
                height: 900,
                samples: renderSamples,
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
