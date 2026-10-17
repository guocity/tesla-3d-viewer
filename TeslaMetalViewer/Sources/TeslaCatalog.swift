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
            name: "Cybertruck Cyberbeast",
            subtitle: "Tri-Motor AWD • Stainless Steel Exoskeleton",
            filename: "cybertruck.glb",
            defaultPaintIndex: 0,
            specs: ["0–60": "2.6 s", "Top Speed": "130 mph", "Power": "845 hp", "Range": "320 mi"]
        ),
        TeslaCarModel(
            id: "model3_high",
            name: "Model 3",
            subtitle: "Dual Motor AWD • All-Electric Performance Sedan",
            filename: "model3_high.glb",
            defaultPaintIndex: 2,
            specs: ["0–60": "2.9 s", "Top Speed": "163 mph", "Power": "510 hp", "Range": "341 mi"]
        ),
        TeslaCarModel(
            id: "modely_high",
            name: "Model Y",
            subtitle: "Compact SUV • Long Range All-Wheel Drive",
            filename: "modely_high.glb",
            defaultPaintIndex: 1,
            specs: ["0–60": "3.5 s", "Top Speed": "155 mph", "Power": "456 hp", "Range": "310 mi"]
        ),
        TeslaCarModel(
            id: "models_plaid",
            name: "Model S Plaid",
            subtitle: "Tri-Motor Palladium • Carbon-Sleeve Rotors",
            filename: "models_plaid.glb",
            defaultPaintIndex: 1,
            specs: ["0–60": "1.99 s", "Top Speed": "200 mph", "Power": "1,020 hp", "Range": "359 mi"]
        ),
        TeslaCarModel(
            id: "modelx_plaid",
            name: "Model X Plaid",
            subtitle: "Tri-Motor SUV • Falcon Wing Doors",
            filename: "modelx_plaid.glb",
            defaultPaintIndex: 3,
            specs: ["0–60": "2.5 s", "Top Speed": "163 mph", "Power": "1,020 hp", "Range": "326 mi"]
        ),
        TeslaCarModel(
            id: "semi",
            name: "Tesla Semi",
            subtitle: "Class 8 Heavy Duty • Tri-Motor Independent Axles",
            filename: "semi.glb",
            defaultPaintIndex: 5,
            specs: ["0–60 (Loaded)": "20 s", "Top Speed": "65 mph", "Consumption": "<2 kWh/mi", "Range": "500 mi"]
        ),
        TeslaCarModel(
            id: "bayberry",
            name: "Model Y (Refresh)",
            subtitle: "Refreshed All-Electric Mid-Size SUV",
            filename: "bayberry.glb",
            defaultPaintIndex: 4,
            specs: ["0–60": "3.2 s", "Top Speed": "160 mph", "Aero Cd": "0.219", "Range": "350 mi"]
        ),
        TeslaCarModel(
            id: "bayberry_e41",
            name: "Model Y Refresh (E41 Aero)",
            subtitle: "High-Downforce Package • Aero Diffusers",
            filename: "bayberry_e41.glb",
            defaultPaintIndex: 2,
            specs: ["0–60": "3.1 s", "Top Speed": "165 mph", "Aero Cd": "0.225", "Range": "345 mi"]
        ),
        TeslaCarModel(
            id: "bayberry_e80",
            name: "Model Y Refresh (E80 LWB)",
            subtitle: "Extended Wheelbase Performance Variant",
            filename: "bayberry_e80.glb",
            defaultPaintIndex: 7,
            specs: ["0–60": "2.8 s", "Top Speed": "175 mph", "Power": "680 hp", "Range": "360 mi"]
        ),
        TeslaCarModel(
            id: "poppyseed",
            name: "Model 3 (Refresh)",
            subtitle: "Refreshed All-Electric Performance Sedan",
            filename: "poppyseed.glb",
            defaultPaintIndex: 2,
            specs: ["0–60": "3.8 s", "Top Speed": "140 mph", "Efficiency": "4.8 mi/kWh", "Range": "300 mi"]
        ),
        TeslaCarModel(
            id: "models_legacy",
            name: "Model S (Raven)",
            subtitle: "Adaptive Air Suspension • Performance Ludicrous+",
            filename: "models_legacy.glb",
            defaultPaintIndex: 6,
            specs: ["0–60": "2.3 s", "Top Speed": "163 mph", "Power": "778 hp", "Range": "348 mi"]
        ),
        TeslaCarModel(
            id: "modelx_legacy",
            name: "Model X (Raven)",
            subtitle: "Dual Motor Performance • Active Aero Spoiler",
            filename: "modelx_legacy.glb",
            defaultPaintIndex: 4,
            specs: ["0–60": "2.7 s", "Top Speed": "155 mph", "Power": "778 hp", "Range": "305 mi"]
        )
    ]
    
    public static func resolveModelPath(filename: String) -> URL? {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let candidates = [
            "models/\(filename)",
            "../models/\(filename)",
            "../../models/\(filename)",
            "\(currentDir)/models/\(filename)",
            "\(currentDir)/../models/\(filename)",
            "/Users/m4air/Documents/github/android_apk/tesla-3d-viewer/models/\(filename)"
        ]
        for candidate in candidates {
            if fileManager.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
