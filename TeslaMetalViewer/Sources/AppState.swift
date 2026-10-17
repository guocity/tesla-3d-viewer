import Foundation
import SwiftUI
import simd

public enum NavigationMode: String, CaseIterable, Identifiable {
    case orbit = "Orbit"
    case pan = "Pan"
    
    public var id: String { rawValue }
}

public class AppState: ObservableObject {
    @Published public var selectedModel: TeslaCarModel = TeslaCatalog.models[0] {
        didSet {
            onModelChanged?()
        }
    }
    
    @Published public var selectedPaint: PaintColorPreset = TeslaCatalog.paints[0] {
        didSet {
            metallic = selectedPaint.metallic
            roughness = selectedPaint.roughness
            clearcoat = selectedPaint.clearcoat
            onMaterialChanged?()
        }
    }
    
    @Published public var metallic: Float = 0.96 {
        didSet { onMaterialChanged?() }
    }
    @Published public var roughness: Float = 0.22 {
        didSet { onMaterialChanged?() }
    }
    @Published public var clearcoat: Float = 0.20 {
        didSet { onMaterialChanged?() }
    }
    
    @Published public var groundReflectivity: Float = 0.25 {
        didSet { onMaterialChanged?() }
    }
    @Published public var groundRoughness: Float = 0.18 {
        didSet { onMaterialChanged?() }
    }
    
    // Privacy Glass & Panoramic Roof Tint controls
    @Published public var isPrivacyTintEnabled: Bool = false {
        didSet { onMaterialChanged?() }
    }
    @Published public var privacyTintDarkness: Float = 0.4 {
        didSet { onMaterialChanged?() }
    }
    
    // Viewport Navigation Mode (Orbit / Rotate vs Pan / Move)
    @Published public var navMode: NavigationMode = .orbit
    public var initialPreset: CameraPreset? = nil
    
    // Cinematic Showcase Car Tour
    @Published public var isTouring: Bool = false {
        didSet {
            if isTouring {
                isTurntable = false
                camera.tourTime = 0
                tourProgress = 0
                tourStageName = Camera.tourWaypoints[0].name
            }
            onMaterialChanged?()
        }
    }
    @Published public var tourProgress: Float = 0.0
    @Published public var tourStageName: String = "Hero 3/4 Overview"
    @Published public var tourSpeed: Float = 1.0
    
    @Published public var isTurntable: Bool = false {
        didSet {
            if isTurntable { isTouring = false }
            camera.isTurntableEnabled = isTurntable
            onMaterialChanged?()
        }
    }
    
    @Published public var sampleCount: Int = 0
    @Published public var totalTriangles: Int = 0
    @Published public var totalVertices: Int = 0
    @Published public var isInteracting: Bool = false
    
    @Published public var animations: [SourceAnimation] = []
    @Published public var selectedAnimations: Set<String> = [] {
        didSet {
            animationTime = min(animationTime, animationDuration)
            if selectedAnimations.isEmpty { isPlayingAnimation = false; animationTime = 0 }
        }
    }
    @Published public var animationTime: Float = 0
    @Published public var isPlayingAnimation = false
    @Published public var loadError: String?
    public var animationDuration: Float {
        animations.filter { selectedAnimations.contains($0.name) }.map(\.duration).max() ?? 1
    }

    public func setAnimation(_ name: String, enabled: Bool) {
        guard let clip = animations.first(where: { $0.name == name }) else { return }
        if !enabled { selectedAnimations.remove(name); return }
        // A transform track owns all channels; value tracks own their individual channel.
        func overlaps(_ lhs: SourceAnimation, _ rhs: SourceAnimation) -> Bool {
            lhs.tracks.contains { a in rhs.tracks.contains { b in
                guard let an = a["node"] as? Int, let bn = b["node"] as? Int, an == bn else { return false }
                if a["type"] as? String == "transform" || b["type"] as? String == "transform" { return true }
                return (a["target"] as? String)?.split(separator: ":").last == (b["target"] as? String)?.split(separator: ":").last
            } }
        }
        let conflicting = animations.filter { selectedAnimations.contains($0.name) && overlaps(clip,$0) }.map(\.name)
        var selection = selectedAnimations.subtracting(conflicting)
        selection.insert(name)
        selectedAnimations = selection
    }

    public func toggleAnimationPlayback() {
        guard !selectedAnimations.isEmpty else { return }
        if !isPlayingAnimation && animationTime >= animationDuration { animationTime = 0 }
        isPlayingAnimation.toggle()
    }
    @Published public var isDriving = false { didSet { if isDriving { isCharging = false } } }
    @Published public var drivingSpeed: Float = 30
    @Published public var climateMode: Float = 0
    @Published public var isCharging = false { didSet { if isCharging { isDriving = false } } }
    @Published public var supportsClimate = false
    @Published public var supportsCharging = false
    public let camera = Camera()
    
    public var onModelChanged: (() -> Void)?
    public var onMaterialChanged: (() -> Void)?
    
    public init() {}
    
    public func nextModel() -> TeslaCarModel {
        let models = TeslaCatalog.models
        let index = models.firstIndex(where: { $0.id == selectedModel.id }) ?? 0
        return models[(index + 1) % models.count]
    }

    public func selectModel(_ model: TeslaCarModel) {
        selectedModel = model
        let defaultPaint = TeslaCatalog.paints[model.defaultPaintIndex]
        selectedPaint = defaultPaint
        metallic = defaultPaint.metallic
        roughness = defaultPaint.roughness
        clearcoat = defaultPaint.clearcoat
        
        // Start with optically clear windows; privacy tint remains an explicit choice.
        isPrivacyTintEnabled = false
        
        onMaterialChanged?()
    }
}
