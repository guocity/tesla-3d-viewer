import Foundation
import SwiftUI
import simd

public enum NavigationMode: String, CaseIterable, Identifiable {
    case orbit = "Orbit"
    case pan = "Pan"

    public var id: String { rawValue }
}

public enum LightingPreset: String, CaseIterable, Identifiable {
    case studio = "Studio", overcast = "Overcast", goldenHour = "Golden hour", blueHour = "Blue hour", neonRain = "Neon rain", coastalStorm = "Coastal storm"
    public var id: String { rawValue }
    public var shaderIndex: Float { Float(Self.allCases.firstIndex(of: self) ?? 0) }
    public var isWeatherScene: Bool { self == .neonRain || self == .coastalStorm }
}
public enum WindowTrim: String, CaseIterable, Identifiable {
    case source = "Original", chrome = "Chrome", delete = "Chrome delete"
    public var id: String { rawValue }
    public var shaderIndex: Float { Float(Self.allCases.firstIndex(of: self) ?? 0) }
}

public enum SeatFinish: String, CaseIterable, Identifiable {
    case original = "Original", whiteVegan = "White vegan"
    public var id: String { rawValue }
    public var shaderIndex: Float { self == .whiteVegan ? 1 : 0 }
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

    @Published public var lighting: LightingPreset = .studio { didSet { onMaterialChanged?() } }
    @Published public var rainIntensity: Float = 0.65 { didSet { onMaterialChanged?() } }
    @Published public var wetness: Float = 0.85 { didSet { onMaterialChanged?() } }
    @Published public var animateWeather = true { didSet { onMaterialChanged?() } }
    @Published public var exposure: Float = 1 { didSet { onMaterialChanged?() } }
    @Published public var seatFinish: SeatFinish = .original { didSet { onMaterialChanged?() } }
    @Published public var windowTrim: WindowTrim = .source { didSet { onMaterialChanged?() } }
    @Published public var headlightReflection: Float = 0.15 { didSet { onMaterialChanged?() } }

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

    // Exterior Lighting & Accessory Controls
    @Published public var areHeadlightsOn: Bool = true { didSet { onLightingChanged?() } }
    @Published public var areDRLOn: Bool = true { didSet { onLightingChanged?() } }
    @Published public var areLeftTurnSignalOn: Bool = false { didSet { onLightingChanged?() } }
    @Published public var areRightTurnSignalOn: Bool = false { didSet { onLightingChanged?() } }
    @Published public var areBrakeLightsOn: Bool = false { didSet { onLightingChanged?() } }
    @Published public var showRoofLightbar: Bool = false { didSet { onLightingChanged?() } }
    @Published public var showLightBeams: Bool = true { didSet { onLightingChanged?() } }

    public let camera = Camera()

    public var onModelChanged: (() -> Void)?
    public var onMaterialChanged: (() -> Void)?
    public var onLightingChanged: (() -> Void)?

    public init() {}

    public func frameLoadedModel(radius: Float, center: SIMD3<Float>, preset: CameraPreset = .hero) {
        if isTouring {
            // Keep the tour clock and stage while adapting framing to the new car.
            let (progress,stage) = camera.updateTour(deltaTime: 0,radius: radius,center: center)
            tourProgress = progress; tourStageName = stage
        } else {
            camera.applyPreset(preset,radius: radius,center: center)
        }
        onMaterialChanged?()
    }

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
