import SwiftUI
import MetalKit

public class InteractiveMTKView: MTKView {
    public var onDrag: ((CGFloat, CGFloat) -> Void)?
    public var onPan: ((CGFloat, CGFloat) -> Void)?
    public var onZoom: ((CGFloat) -> Void)?
    public var onInteractionStart: (() -> Void)?
    public var onInteractionEnd: (() -> Void)?
    
    private var lastPoint: CGPoint = .zero
    
    public override var acceptsFirstResponder: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    
    public override func mouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        onInteractionStart?()
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - lastPoint.x
        let dy = current.y - lastPoint.y
        lastPoint = current
        
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) {
            onPan?(dx, dy)
        } else {
            onDrag?(dx, dy)
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        onInteractionEnd?()
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        lastPoint = convert(event.locationInWindow, from: nil)
        onInteractionStart?()
    }
    
    public override func rightMouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - lastPoint.x
        let dy = current.y - lastPoint.y
        lastPoint = current
        onPan?(dx, dy)
    }
    
    public override func rightMouseUp(with event: NSEvent) {
        onInteractionEnd?()
    }
    
    public override func scrollWheel(with event: NSEvent) {
        onInteractionStart?()
        let delta = event.scrollingDeltaY
        let factor = 1.0 - (delta * 0.015)
        onZoom?(factor)
        
        // Reset interaction flag after slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onInteractionEnd?()
        }
    }
    
    public override func magnify(with event: NSEvent) {
        onInteractionStart?()
        let factor = 1.0 - event.magnification
        onZoom?(factor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onInteractionEnd?()
        }
    }
}

public struct MetalViewport: NSViewRepresentable {
    @ObservedObject var state: AppState
    let rayTracer: RayTracer
    
    public class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalViewport
        
        init(_ parent: MetalViewport) {
            self.parent = parent
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            parent.state.camera.fovYDegrees = 45.0
            parent.rayTracer.resetAccumulation()
        }
        
        public func draw(in view: MTKView) {
            let camera = parent.state.camera
            if parent.state.isTurntable {
                camera.updateTurntable()
                parent.parentInteractionChanged(isInteracting: true)
            }
            
            parent.rayTracer.render(
                in: view,
                camera: camera,
                paintColor: parent.state.selectedPaint.color,
                metallic: parent.state.metallic,
                roughness: parent.state.roughness,
                clearcoat: parent.state.clearcoat,
                groundReflectivity: parent.state.groundReflectivity,
                groundRoughness: parent.state.groundRoughness,
                isInteracting: parent.state.isInteracting
            )
            
            DispatchQueue.main.async {
                self.parent.state.sampleCount = Int(self.parent.rayTracer.sampleIndex)
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func parentInteractionChanged(isInteracting: Bool) {
        if state.isInteracting != isInteracting {
            DispatchQueue.main.async {
                self.state.isInteracting = isInteracting
                if isInteracting {
                    self.rayTracer.resetAccumulation()
                }
            }
        }
    }
    
    public func makeNSView(context: Context) -> InteractiveMTKView {
        let mtkView = InteractiveMTKView(frame: .zero, device: rayTracer.device)
        mtkView.colorPixelFormat = .rgba8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1.0)
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        
        mtkView.onInteractionStart = {
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onInteractionEnd = {
            self.parentInteractionChanged(isInteracting: false)
        }
        mtkView.onDrag = { dx, dy in
            self.state.camera.rotate(deltaX: Float(dx) * 0.005, deltaY: -Float(dy) * 0.005)
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onPan = { dx, dy in
            self.state.camera.pan(deltaX: -Float(dx) * 0.004, deltaY: Float(dy) * 0.004)
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onZoom = { factor in
            self.state.camera.zoom(delta: Float(factor))
            self.parentInteractionChanged(isInteracting: true)
        }
        
        return mtkView
    }
    
    public func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        // Redraw triggered automatically via MTKView display timer
    }
}
