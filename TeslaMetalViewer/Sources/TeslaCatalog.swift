import Foundation
import simd

public struct TeslaCarModel: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let filename: String
    public let defaultPaintIndex: Int
    public let specs: [String: String]
    
    public static func == (lhs: TeslaCarModel, rhs: TeslaCarModel) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct PaintColorPreset: Identifiable {
    public let id: String
    public let name: String
    public let color: SIMD3<Float> // Linear RGB
    public let metallic: Float
    public let roughness: Float
    public let clearcoat: Float
}

public struct TeslaCatalog {
    public static let paints: [PaintColorPreset] = [
        PaintColorPreset(
            id: "steel",
            name: "Stainless Steel (Cybertruck)",
            color: SIMD3<Float>(0.74, 0.76, 0.78),
            metallic: 0.96,
            roughness: 0.24,
            clearcoat: 0.20
        ),
        PaintColorPreset(
            id: "quicksilver",
            name: "Quicksilver Metallic",
            color: SIMD3<Float>(0.65, 0.69, 0.74),
            metallic: 0.94,
            roughness: 0.12,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "ultra_red",
            name: "Ultra Red",
            color: SIMD3<Float>(0.72, 0.04, 0.08),
            metallic: 0.82,
            roughness: 0.11,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "stealth_grey",
            name: "Stealth Grey",
            color: SIMD3<Float>(0.14, 0.15, 0.17),
            metallic: 0.78,
            roughness: 0.14,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "deep_blue",
            name: "Deep Blue Metallic",
            color: SIMD3<Float>(0.04, 0.12, 0.38),
            metallic: 0.85,
            roughness: 0.12,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "pearl_white",
            name: "Pearl White Multi-Coat",
            color: SIMD3<Float>(0.92, 0.94, 0.97),
            metallic: 0.45,
            roughness: 0.12,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "solid_black",
            name: "Solid Black",
            color: SIMD3<Float>(0.03, 0.035, 0.04),
            metallic: 0.65,
            roughness: 0.08,
            clearcoat: 1.0
        ),
        PaintColorPreset(
            id: "founders_gold",
            name: "Founders Gold",
            color: SIMD3<Float>(0.78, 0.62, 0.32),
            metallic: 0.90,
            roughness: 0.14,
            clearcoat: 1.0
        )
    ]
    
    public static let models: [TeslaCarModel] = [
        TeslaCarModel(
            id: "cybertruck",
            name: "Cybertruck",
            subtitle: "Tri-Motor AWD • Stainless Steel Exoskeleton",
            filename: "cybertruck.glb",
            defaultPaintIndex: 0,
            specs: [:]
        ),
        TeslaCarModel(
            id: "model3_high",
            name: "Model 3 · 3_High",
            subtitle: "Dual Motor AWD • All-Electric Performance Sedan",
            filename: "model3_high.glb",
            defaultPaintIndex: 2,
            specs: [:]
        ),
        TeslaCarModel(
            id: "modely_high",
            name: "Model Y · Y_High",
            subtitle: "Compact SUV • Long Range All-Wheel Drive",
            filename: "modely_high.glb",
            defaultPaintIndex: 1,
            specs: [:]
        ),
        TeslaCarModel(
            id: "models_plaid",
            name: "Model S · Palladium",
            subtitle: "Tri-Motor Palladium • Carbon-Sleeve Rotors",
            filename: "models_plaid.glb",
            defaultPaintIndex: 1,
            specs: [:]
        ),
        TeslaCarModel(
            id: "modelx_plaid",
            name: "Model X · Palladium",
            subtitle: "Tri-Motor SUV • Falcon Wing Doors",
            filename: "modelx_plaid.glb",
            defaultPaintIndex: 3,
            specs: [:]
        ),
        TeslaCarModel(
            id: "semi",
            name: "Tesla Semi",
            subtitle: "Class 8 Heavy Duty • Tri-Motor Independent Axles",
            filename: "semi.glb",
            defaultPaintIndex: 5,
            specs: [:]
        ),
        TeslaCarModel(
            id: "bayberry",
            name: "Model Y · Bayberry",
            subtitle: "Refreshed All-Electric Mid-Size SUV",
            filename: "bayberry.glb",
            defaultPaintIndex: 4,
            specs: [:]
        ),
        TeslaCarModel(
            id: "bayberry_e41",
            name: "Bayberry E41",
            subtitle: "APK source variant: Ego/BayberryE41",
            filename: "bayberry_e41.glb",
            defaultPaintIndex: 2,
            specs: [:]
        ),
        TeslaCarModel(
            id: "bayberry_e80",
            name: "Bayberry E80",
            subtitle: "APK source variant: Ego/BayberryE80",
            filename: "bayberry_e80.glb",
            defaultPaintIndex: 7,
            specs: [:]
        ),
        TeslaCarModel(
            id: "poppyseed",
            name: "Model 3 · Poppyseed",
            subtitle: "Refreshed All-Electric Performance Sedan",
            filename: "poppyseed.glb",
            defaultPaintIndex: 2,
            specs: [:]
        ),
        TeslaCarModel(
            id: "models_legacy",
            name: "Model S · legacy",
            subtitle: "Adaptive Air Suspension • Performance Ludicrous+",
            filename: "models_legacy.glb",
            defaultPaintIndex: 6,
            specs: [:]
        ),
        TeslaCarModel(
            id: "modelx_legacy",
            name: "Model X · legacy",
            subtitle: "Dual Motor Performance • Active Aero Spoiler",
            filename: "modelx_legacy.glb",
            defaultPaintIndex: 4,
            specs: [:]
        )
    ]
    
    public static func resolveModelPath(filename: String) -> URL? {
        let fileManager = FileManager.default
        
        // 1. Bundle Resources (self-contained inside .app, zero privacy permissions requested)
        if let resourceURL = Bundle.main.resourceURL {
            let bundleModel = resourceURL.appendingPathComponent("models/\(filename)")
            if fileManager.fileExists(atPath: bundleModel.path) {
                return bundleModel
            }
            let directBundle = resourceURL.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: directBundle.path) {
                return directBundle
            }
        }
        
        // 2. Relative to executable binary location inside .app/Contents/MacOS
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let execDir = execURL.deletingLastPathComponent()
        let bundleResFromExec = execDir.deletingLastPathComponent().appendingPathComponent("Resources/models/\(filename)")
        if fileManager.fileExists(atPath: bundleResFromExec.path) {
            return bundleResFromExec
        }
        
        // 3. Current working directory & relative paths (for command-line development)
        let currentDir = fileManager.currentDirectoryPath
        let candidates = [
            "tesla-3d-viewer/models/\(filename)",
            "models/\(filename)",
            "../models/\(filename)",
            "../../models/\(filename)",
            "\(currentDir)/models/\(filename)",
            "\(currentDir)/../models/\(filename)"
        ]
        for candidate in candidates {
            if fileManager.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
