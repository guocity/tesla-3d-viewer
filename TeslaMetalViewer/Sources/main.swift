import AppKit
import SwiftUI
import Metal
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
        
        // Offscreen high-quality ray-traced render export:
        if let renderOutIdx = CommandLine.arguments.firstIndex(of: "--render-out"),
           renderOutIdx + 1 < CommandLine.arguments.count {
            let outPath = CommandLine.arguments[renderOutIdx + 1]
            let model = appState.selectedModel
            _ = rayTracer.loadModel(filename: model.filename)
            let radius = rayTracer.currentScene?.radius ?? 3.0
            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
