import SwiftUI
import MetalKit

public class InteractiveMTKView: MTKView {
    public var onDrag: ((CGFloat, CGFloat) -> Void)?
    public var onPan: ((CGFloat, CGFloat) -> Void)?
    public var onZoom: ((CGFloat) -> Void)?
    public var onInteractionStart: (() -> Void)?
    public var onInteractionEnd: (() -> Void)?
    public var navMode: () -> NavigationMode = { .orbit }
    
    public enum GestureAction { case orbit, pan, zoom }
    private var interactionEndWork: DispatchWorkItem?
    private var lastPoint: CGPoint = .zero
    private var dragAction: GestureAction = .orbit
    private var scrollAction: GestureAction?
    private var isPinching = false

    public override var acceptsFirstResponder: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    // One navigation policy for trackpad gestures and mouse emulation.
    public static func action(precise: Bool, modifiers: NSEvent.ModifierFlags,
                              mode: NavigationMode) -> GestureAction {
        if !precise || modifiers.contains(.control) { return .zoom }
        if modifiers.contains(.shift) || mode == .pan { return .pan }
        return .orbit
    }

    private func beginInteraction() {
        interactionEndWork?.cancel()
        window?.makeFirstResponder(self)
        onInteractionStart?()
    }

    private func finishSoon() {
        interactionEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scrollAction = nil
            self?.isPinching = false
            self?.onInteractionEnd?()
        }
        interactionEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func beginDrag(_ event: NSEvent, right: Bool = false) {
        lastPoint = convert(event.locationInWindow, from: nil)
        dragAction = right || event.modifierFlags.contains(.shift) || navMode() == .pan ? .pan :
            (event.modifierFlags.contains(.control) ? .zoom : .orbit)
        beginInteraction()
    }

    private func drag(_ event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - lastPoint.x, dy = current.y - lastPoint.y
        lastPoint = current
        switch dragAction {
        case .orbit: onDrag?(dx,dy)
        case .pan: onPan?(dx,dy)
        case .zoom: onZoom?(exp(-dy * 0.008))
        }
    }

    public override func mouseDown(with event: NSEvent) { beginDrag(event) }
    public override func mouseDragged(with event: NSEvent) { drag(event) }
    public override func mouseUp(with event: NSEvent) { onInteractionEnd?() }
    public override func rightMouseDown(with event: NSEvent) { beginDrag(event,right: true) }
    public override func rightMouseDragged(with event: NSEvent) { drag(event) }
    public override func rightMouseUp(with event: NSEvent) { onInteractionEnd?() }
    public override func otherMouseDown(with event: NSEvent) { beginDrag(event) }
    public override func otherMouseDragged(with event: NSEvent) { drag(event) }
    public override func otherMouseUp(with event: NSEvent) { onInteractionEnd?() }

    public override func scrollWheel(with event: NSEvent) {
        // Inertia must not keep rotating the camera after fingers leave the pad.
        guard event.momentumPhase.isEmpty, !isPinching else { return }
        if event.phase.contains(.began) || scrollAction == nil {
            scrollAction = Self.action(precise: event.hasPreciseScrollingDeltas,
                                       modifiers: event.modifierFlags, mode: navMode())
        }
        beginInteraction()
        // Orbit and pan follow finger motion independently of the system's
        // document-scrolling preference. Mouse wheels retain native direction.
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let dx = event.scrollingDeltaX * direction, dy = event.scrollingDeltaY * direction
        switch scrollAction ?? .orbit {
        case .orbit: onDrag?(dx,dy)
        case .pan: onPan?(dx,dy)
        case .zoom:
            onZoom?(exp(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.008 : 0.08)))
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { scrollAction = nil }
        finishSoon()
    }

    public override func magnify(with event: NSEvent) {
        beginInteraction()
        isPinching = !event.phase.contains(.ended) && !event.phase.contains(.cancelled)
        scrollAction = nil
        onZoom?(exp(-event.magnification))
        finishSoon()
    }

}

public struct MetalViewport: NSViewRepresentable {
    @ObservedObject var state: AppState
    let rayTracer: RayTracer
    
    public class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalViewport
        var lastStatsUpdate: Double = 0
        var lastFrame = ProcessInfo.processInfo.systemUptime
        var lastPoseTime: Float = -1
        var lastClips: Set<String> = []
        var lastTourUpdate: Double = 0
        var lastBlinkOn = true
        var lastCharging = false
        var lastHeadlights = true
        var lastDRL = true
        var lastBrakeLights = false
        var lastTurnSignalLeft = false
        var lastTurnSignalRight = false
        var lastRoofLightbar = false
        var lastLightBeams = true
        
        init(_ parent: MetalViewport) {
            self.parent = parent
        }
        
        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            parent.state.camera.fovYDegrees = 45.0
            parent.state.camera.viewportAspect = Float(size.width / max(size.height,1))
            parent.state.camera.viewportHeight = Float(max(view.bounds.height,1))
            parent.rayTracer.resetAccumulation()
        }
        
        public func draw(in view: MTKView) {
            guard parent.rayTracer.beginInteractiveFrame() else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = min(0.1, now - lastFrame); lastFrame = now
            let state = parent.state
            if state.isPlayingAnimation && !state.selectedAnimations.isEmpty {
                state.animationTime = min(state.animationDuration, state.animationTime + Float(dt))
                if state.animationTime >= state.animationDuration { state.isPlayingAnimation = false }
            }
            parent.rayTracer.effectTime += Float(dt)
            if state.animateWeather { parent.rayTracer.weatherTime += Float(dt) }
            parent.rayTracer.drivingSpeed = state.isDriving ? state.drivingSpeed : 0
            if state.isDriving {
                parent.rayTracer.wheelDegrees = (parent.rayTracer.wheelDegrees + min(state.drivingSpeed / 60,1) * 1000 * Float(dt)).truncatingRemainder(dividingBy: 360)
            }
            if (state.areLeftTurnSignalOn && !lastTurnSignalLeft) || (state.areRightTurnSignalOn && !lastTurnSignalRight) {
                parent.rayTracer.signalStartTime = parent.rayTracer.effectTime
            }
            let blinkOn = VehicleLighting.blinkOn(time: parent.rayTracer.effectTime-parent.rayTracer.signalStartTime)
            if (state.areLeftTurnSignalOn || state.areRightTurnSignalOn) && blinkOn != lastBlinkOn { parent.rayTracer.resetAccumulation() }
            lastBlinkOn = blinkOn
            parent.rayTracer.lighting = state.lighting
            parent.rayTracer.rainIntensity = state.rainIntensity
            parent.rayTracer.wetness = state.wetness
            parent.rayTracer.exposure = state.exposure
            parent.rayTracer.windowTrim = state.windowTrim
            parent.rayTracer.headlightReflection = state.headlightReflection
            parent.rayTracer.climateMode = state.climateMode
            parent.rayTracer.charging = state.isCharging
            parent.rayTracer.headlightsOn = state.areHeadlightsOn
            parent.rayTracer.drlOn = state.areDRLOn
            parent.rayTracer.brakeLightsOn = state.areBrakeLightsOn
            parent.rayTracer.turnSignalLeftOn = state.areLeftTurnSignalOn
            parent.rayTracer.turnSignalRightOn = state.areRightTurnSignalOn
            parent.rayTracer.showRoofLightbar = state.showRoofLightbar
            parent.rayTracer.showLightBeams = state.showLightBeams
            let effectsActive = state.isDriving || state.climateMode > 0 || state.isCharging || (state.lighting.isWeatherScene && state.animateWeather && state.rainIntensity > 0)
            if effectsActive { parent.rayTracer.resetAccumulation() }
            let beamsChanged = lastLightBeams != state.showLightBeams
            if beamsChanged { parent.rayTracer.resetAccumulation(); lastLightBeams = state.showLightBeams }
            let lightingChanged = lastHeadlights != state.areHeadlightsOn || lastDRL != state.areDRLOn || lastBrakeLights != state.areBrakeLightsOn || lastTurnSignalLeft != state.areLeftTurnSignalOn || lastTurnSignalRight != state.areRightTurnSignalOn || lastRoofLightbar != state.showRoofLightbar
            if state.isDriving || lastCharging != state.isCharging || lastClips != state.selectedAnimations || lightingChanged || lastPoseTime != state.animationTime {
                parent.rayTracer.applyAnimations(names: state.selectedAnimations, time: state.animationTime)
                lastCharging = state.isCharging; lastClips = state.selectedAnimations; lastPoseTime = state.animationTime
                lastHeadlights = state.areHeadlightsOn; lastDRL = state.areDRLOn; lastBrakeLights = state.areBrakeLightsOn
                lastTurnSignalLeft = state.areLeftTurnSignalOn; lastTurnSignalRight = state.areRightTurnSignalOn
                lastRoofLightbar = state.showRoofLightbar
            }
            let camera = parent.state.camera
            let radius = parent.rayTracer.currentScene?.radius ?? 3.0
            let center = parent.rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
            
            if parent.state.isTouring {
                let (prog, stage) = camera.updateTour(deltaTime: Float(dt) * parent.state.tourSpeed, radius: radius, center: center)
                parent.rayTracer.resetAccumulation()
                if now - lastTourUpdate >= 0.25 {
                    lastTourUpdate = now
                    DispatchQueue.main.async {
                        self.parent.state.tourProgress = prog
                        self.parent.state.tourStageName = stage
                    }
                }
            } else if parent.state.isTurntable {
                camera.updateTurntable(deltaTime: Float(dt))
                parent.rayTracer.resetAccumulation()
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
                isPrivacyTint: parent.state.isPrivacyTintEnabled,
                privacyTintDarkness: parent.state.privacyTintDarkness,
                isInteracting: parent.state.isInteracting || parent.state.isPlayingAnimation || parent.state.isTurntable || parent.state.isTouring || effectsActive
            )
            
            let samples = Int(parent.rayTracer.sampleIndex)
            if now - lastStatsUpdate >= 0.25 && parent.state.sampleCount != samples {
                lastStatsUpdate = now
                DispatchQueue.main.async { self.parent.state.sampleCount = samples }
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
        mtkView.autoResizeDrawable = false
        mtkView.preferredFramesPerSecond = NSScreen.main?.maximumFramesPerSecond ?? 60
        
        mtkView.navMode = { [weak state] in state?.navMode ?? .orbit }
        
        mtkView.onInteractionStart = {
            self.state.isTurntable = false; self.state.isTouring = false
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onInteractionEnd = {
            self.parentInteractionChanged(isInteracting: false)
        }
        mtkView.onDrag = { dx, dy in
            if self.state.isTouring {
                DispatchQueue.main.async { self.state.isTouring = false }
            }
            self.state.camera.rotate(deltaX: -Float(dx) * 0.005, deltaY: -Float(dy) * 0.005)
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onPan = { [weak mtkView] dx, dy in
            if self.state.isTouring {
                DispatchQueue.main.async { self.state.isTouring = false }
            }
            self.state.camera.viewportHeight = Float(max(mtkView?.bounds.height ?? 1,1))
            self.state.camera.pan(deltaX: Float(dx), deltaY: Float(dy))
            self.parentInteractionChanged(isInteracting: true)
        }
        mtkView.onZoom = { factor in
            if self.state.isTouring {
                DispatchQueue.main.async { self.state.isTouring = false }
            }
            self.state.camera.zoom(delta: Float(factor))
            self.parentInteractionChanged(isInteracting: true)
        }
        
        return mtkView
    }
    
    public func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        context.coordinator.parent = self
        // Redraw triggered automatically via MTKView display timer
    }
}
