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
    
    @Published public var groundReflectivity: Float = 0.75 {
        didSet { onMaterialChanged?() }
    }
    @Published public var groundRoughness: Float = 0.06 {
        didSet { onMaterialChanged?() }
    }
    
    // Privacy Glass & Panoramic Roof Tint controls
    @Published public var isPrivacyTintEnabled: Bool = false {
        didSet { onMaterialChanged?() }
    }
    @Published public var privacyTintDarkness: Float = 0.75 {
        didSet { onMaterialChanged?() }
    }
    
    // Viewport Navigation Mode (Orbit / Rotate vs Pan / Move)
    @Published public var navMode: NavigationMode = .orbit
    public var initialPreset: CameraPreset? = nil
    
    // Cinematic Showcase Car Tour
    @Published public var isTouring: Bool = false {
        didSet {
            if isTouring { isTurntable = false }
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
    
    public let camera = Camera()
    
    public var onModelChanged: (() -> Void)?
    public var onMaterialChanged: (() -> Void)?
    
    public init() {}
    
    public func selectModel(_ model: TeslaCarModel) {
        selectedModel = model
        let defaultPaint = TeslaCatalog.paints[model.defaultPaintIndex]
        selectedPaint = defaultPaint
        metallic = defaultPaint.metallic
        roughness = defaultPaint.roughness
        clearcoat = defaultPaint.clearcoat
        
        // Model Y and Model X feature factory dark privacy glass for rear windows & roof
        let isSUV = model.id.contains("modely") || model.id.contains("bayberry") || model.id.contains("modelx")
        isPrivacyTintEnabled = isSUV ? true : isPrivacyTintEnabled
        
        onMaterialChanged?()
    }
}
