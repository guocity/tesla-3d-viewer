import Foundation
import simd

public enum CameraPreset {
    case hero
    case side
    case front
    case rear
    case top
}

public struct TourKeyframe {
    public let name: String
    public let azimuth: Float
    public let elevation: Float
    public let distanceFactor: Float
    public let targetOffsetY: Float
    public let duration: Float
    
    public init(name: String, azimuth: Float, elevation: Float, distanceFactor: Float, targetOffsetY: Float, duration: Float) {
        self.name = name
        self.azimuth = azimuth
        self.elevation = elevation
        self.distanceFactor = distanceFactor
        self.targetOffsetY = targetOffsetY
        self.duration = duration
    }
}

public class Camera {
    public var target: SIMD3<Float> = SIMD3<Float>(0, 0.7, 0)
    public var distance: Float = 6.5
    public var azimuth: Float = 0.65 // Radians
    public var elevation: Float = 0.35 // Radians
    
    public var minDistance: Float = 1.0
    public var maxDistance: Float = 25.0
    public var fovYDegrees: Float = 45.0
    
    public var isTurntableEnabled: Bool = false
    public var turntableSpeed: Float = 0.008
    
    public var position: SIMD3<Float> {
        let x = target.x + distance * cos(elevation) * sin(azimuth)
        let y = target.y + distance * sin(elevation)
        let z = target.z + distance * cos(elevation) * cos(azimuth)
        return SIMD3<Float>(x, y, z)
    }
    
    public init() {}
    
    public func rotate(deltaX: Float, deltaY: Float) {
        azimuth += deltaX
        elevation = simd_clamp(elevation + deltaY, 0.02, Float.pi * 0.48)
    }
    
    public func zoom(delta: Float) {
        distance = simd_clamp(distance * delta, minDistance, maxDistance)
    }
    
    public func pan(deltaX: Float, deltaY: Float) {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(simd_cross(right, forward))
        let sensitivity = max(distance * 0.0016, 0.004)
        target += right * (deltaX * sensitivity) + up * (deltaY * sensitivity)
    }
    
    public func recenter(center: SIMD3<Float>) {
        target = SIMD3<Float>(0, center.y * 0.85, 0)
    }
    
    public func applyPreset(_ preset: CameraPreset, radius: Float, center: SIMD3<Float>) {
        let r = max(radius, 2.5)
        target = SIMD3<Float>(0, center.y * 0.85, 0)
        
        switch preset {
        case .hero:
            azimuth = 0.65
            elevation = 0.32
            distance = r * 2.2
        case .side:
            azimuth = Float.pi * 0.5
            elevation = 0.18
            distance = r * 2.1
        case .front:
            azimuth = 0.0
            elevation = 0.20
            distance = r * 2.0
        case .rear:
            azimuth = Float.pi
            elevation = 0.25
            distance = r * 2.1
        case .top:
            azimuth = 0.4
            elevation = Float.pi * 0.46
            distance = r * 2.5
        }
    }
    
    public var tourTime: Float = 0.0
    
    public static let tourWaypoints: [TourKeyframe] = [
        TourKeyframe(name: "Hero 3/4 Overview", azimuth: 0.65, elevation: 0.32, distanceFactor: 2.20, targetOffsetY: 0.85, duration: 4.0),
        TourKeyframe(name: "Front Fascia & Lights", azimuth: 0.10, elevation: 0.16, distanceFactor: 1.55, targetOffsetY: 0.60, duration: 4.5),
        TourKeyframe(name: "Aero Profile & Wheels", azimuth: 1.55, elevation: 0.14, distanceFactor: 1.80, targetOffsetY: 0.50, duration: 4.5),
        TourKeyframe(name: "Rear 3/4 & Tail Lightbar", azimuth: 2.70, elevation: 0.24, distanceFactor: 1.85, targetOffsetY: 0.75, duration: 4.5),
        TourKeyframe(name: "Top Panoramic Roof", azimuth: 0.90, elevation: 1.25, distanceFactor: 2.30, targetOffsetY: 0.70, duration: 4.5),
        TourKeyframe(name: "Studio 360° Orbit", azimuth: 0.65 + Float.pi * 2, elevation: 0.32, distanceFactor: 2.20, targetOffsetY: 0.85, duration: 5.5)
    ]
    
    public func updateTour(deltaTime: Float, radius: Float, center: SIMD3<Float>) -> (progress: Float, stage: String) {
        let waypoints = Camera.tourWaypoints
        let totalTime: Float = waypoints.reduce(0.0) { $0 + $1.duration }
        
        tourTime += deltaTime
        if tourTime >= totalTime {
            tourTime -= totalTime
        }
        
        var accumulated: Float = 0.0
        var currentIdx = 0
        var tSeg: Float = 0.0
        
        for i in 0..<waypoints.count {
            let nextAcc = accumulated + waypoints[i].duration
            if tourTime < nextAcc || i == waypoints.count - 1 {
                currentIdx = i
                tSeg = simd_clamp((tourTime - accumulated) / max(waypoints[i].duration, 0.01), 0.0, 1.0)
                break
            }
            accumulated = nextAcc
        }
        
        let k0 = waypoints[currentIdx]
        let nextIdx = (currentIdx + 1) % waypoints.count
        let k1 = waypoints[nextIdx]
        
        // Smooth cubic easing
        let ease = tSeg * tSeg * (3.0 - 2.0 * tSeg)
        
        var az0 = k0.azimuth
        var az1 = k1.azimuth
        if abs(az1 - az0) > Float.pi && currentIdx < waypoints.count - 1 {
            if az1 > az0 { az0 += Float.pi * 2 }
            else { az1 += Float.pi * 2 }
        }
        
        let r = max(radius, 2.5)
        azimuth = az0 + (az1 - az0) * ease
        elevation = k0.elevation + (k1.elevation - k0.elevation) * ease
        let distFactor = k0.distanceFactor + (k1.distanceFactor - k0.distanceFactor) * ease
        distance = r * distFactor
        
        let tgtY = k0.targetOffsetY + (k1.targetOffsetY - k0.targetOffsetY) * ease
        target = SIMD3<Float>(0, center.y * tgtY, 0)
        
        let progress = tourTime / totalTime
        return (progress, k0.name)
    }
    
    public func updateTurntable() {
        if isTurntableEnabled {
            azimuth += turntableSpeed
            if azimuth > Float.pi * 2 { azimuth -= Float.pi * 2 }
        }
    }
    
    public func viewMatrix() -> simd_float4x4 {
        let eye = position
        let center = target
        let up = SIMD3<Float>(0, 1, 0)
        
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4<Float>(x.x, y.x, z.x, 0)
        m.columns.1 = SIMD4<Float>(x.y, y.y, z.y, 0)
        m.columns.2 = SIMD4<Float>(x.z, y.z, z.z, 0)
        m.columns.3 = SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        return m
    }
    
    public func projectionMatrix(aspect: Float) -> simd_float4x4 {
        let fovY = fovYDegrees * (Float.pi / 180.0)
        let near: Float = 0.1
        let far: Float = 1000.0
        let yScale = 1.0 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2.0 * far * near / zRange
        
        var m = simd_float4x4()
        m.columns.0 = SIMD4<Float>(xScale, 0, 0, 0)
        m.columns.1 = SIMD4<Float>(0, yScale, 0, 0)
        m.columns.2 = SIMD4<Float>(0, 0, zScale, -1)
        m.columns.3 = SIMD4<Float>(0, 0, wzScale, 0)
        return m
    }
}
