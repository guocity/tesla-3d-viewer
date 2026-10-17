import AppKit
import SwiftUI
import Metal

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
        
        if CommandLine.arguments.contains("--tour") {
            self.appState.isTouring = true
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
        window.makeKeyAndOrderFront(nil)
        
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
