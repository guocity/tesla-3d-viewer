import Foundation
import Metal
import MetalKit
import simd

public struct GeometryInfoGPU {
    public var emission = SIMD4<Float>(1,1,1,-1)
    public var textures = SIMD4<Int32>(-1,-1,-1,0)
    public var vertexOffset: UInt32 = 0
    public var indexOffset: UInt32 = 0
    public var isGround: UInt32 = 0
    public var isPaint: UInt32 = 0
    public var baseColor: SIMD4<Float> = .zero
    public var params: SIMD4<Float> = .zero
}

public struct UniformsGPU {
    public var effectParams: SIMD4<Float> = .zero
    public var effectTextures = SIMD4<Int32>(-1,0,0,0)
    public var climateLeft = matrix_identity_float4x4
    public var climateRight = matrix_identity_float4x4
    public var invView: simd_float4x4 = matrix_identity_float4x4
    public var invProj: simd_float4x4 = matrix_identity_float4x4
    public var cameraPos: SIMD4<Float> = .zero
    public var carPaintColor: SIMD4<Float> = .zero
    public var materialParams: SIMD4<Float> = .zero
    public var viewport: SIMD4<UInt32> = .zero
    public var tintParams: SIMD4<Float> = .zero
    public var reservedInterior: SIMD4<Float> = .zero
    public var rearStrip = SIMD4<Float>(repeating: 0)
    public var rearStripSize = SIMD4<Float>(repeating: 0)
    public var headlampLeft = SIMD4<Float>(repeating: 0)
    public var headlampRight = SIMD4<Float>(repeating: 0)
    public var weather = SIMD4<Float>(0.65,0.85,0,0)
    public var renderOptions = SIMD4<Float>(0,1,0,0.15)
}

public class RayTracer {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public private(set) var pipelineState: MTLComputePipelineState!

    // Scene geometry & hardware acceleration structure
    public private(set) var currentScene: ModelSceneData?
    public private(set) var accelerationStructure: MTLAccelerationStructure?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var geometryBuffer: MTLBuffer?
    private var uniformsBuffer: MTLBuffer?

    // Accumulation & intermediate render textures
    private var accumTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    public var sampleIndex: UInt32 = 0
    public let maxSamples: UInt32 = 256
    public var isDirty: Bool = true
    private var geometryCount: Int = 0
    public private(set) var headlampPositions = [SIMD4<Float>(repeating: 0),SIMD4<Float>(repeating: 0)]
    private var rearStrip = SIMD4<Float>(repeating: 0)
    private var rearStripSize = SIMD4<Float>(repeating: 0)
    private var lastTintParams: SIMD4<Float> = .zero

    public init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        buildPipeline()
    }

    private func buildPipeline() {
        do {
            let library = try device.makeLibrary(source: ShaderSource.metalRaytracingSource, options: nil)
            guard let function = library.makeFunction(name: "raytraceKernel") else {
                fatalError("Could not find raytraceKernel function in Metal library")
            }
            let desc = MTLComputePipelineDescriptor()
            desc.computeFunction = function
            desc.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            self.pipelineState = try device.makeComputePipelineState(descriptor: desc, options: [], reflection: nil)
        } catch {
            fatalError("Failed to compile Metal Ray Tracing pipeline: \(error)")
        }
    }

    public var signalState: Float {
        Float((VehicleLighting.blinkOn(time: effectTime-signalStartTime) ? 1 : 0) | (turnSignalLeftOn ? 2 : 0) | (turnSignalRightOn ? 4 : 0))
    }
    public var signalStartTime: Float = 0
    public var weatherTime: Float = 2
    public var effectTime: Float = 0
    public var drivingSpeed: Float = 0
    public var wheelDegrees: Float = 0
    public var climateMode: Float = 0
    public var lighting: LightingPreset = .studio { didSet { if oldValue != lighting {
        if let scene = currentScene { buildAccelerationStructure(from: scene) }; resetAccumulation()
    } } }
    public var exposure: Float = 1 { didSet { if oldValue != exposure { resetAccumulation() } } }
    public var windowTrim: WindowTrim = .source { didSet { if oldValue != windowTrim { resetAccumulation() } } }
    public var headlightReflection: Float = 0.15 { didSet { if oldValue != headlightReflection { resetAccumulation() } } }

    public var rainIntensity: Float = 0.65 { didSet { if oldValue != rainIntensity { resetAccumulation() } } }
    public var wetness: Float = 0.85 { didSet { if oldValue != wetness { resetAccumulation() } } }
    public var charging = false
    public var headlightsOn: Bool = true
    public var drlOn: Bool = true
    public var brakeLightsOn: Bool = false
    public var turnSignalLeftOn: Bool = false
    public var turnSignalRightOn: Bool = false
    public var showRoofLightbar: Bool = false
    public var showLightBeams: Bool = true
    private var modelURL: URL?

    public func loadModel(filename: String, headlightsOn: Bool = true, drlOn: Bool = true, brakeLightsOn: Bool = false,
                          turnSignalLeftOn: Bool = false, turnSignalRightOn: Bool = false, showRoofLightbar: Bool = false) -> Bool {
        guard let url = TeslaCatalog.resolveModelPath(filename: filename) else {
            print("Could not find model file: \(filename)")
            return false
        }

        self.signalStartTime = effectTime
        self.headlightsOn = headlightsOn
        self.drlOn = drlOn
        self.brakeLightsOn = brakeLightsOn
        self.turnSignalLeftOn = turnSignalLeftOn
        self.turnSignalRightOn = turnSignalRightOn
        self.showRoofLightbar = showRoofLightbar

        guard let scene = GLBLoader.loadModel(from: url, device: device, charging: charging, wheelDegrees: wheelDegrees,
                                             headlightsOn: headlightsOn, drlOn: drlOn, brakeLightsOn: brakeLightsOn,
                                             turnSignalLeftOn: turnSignalLeftOn, turnSignalRightOn: turnSignalRightOn,
                                             showRoofLightbar: showRoofLightbar) else {
            print("Failed to load and parse GLB: \(filename)")
            return false
        }

        self.modelURL = url
        self.currentScene = scene
        buildAccelerationStructure(from: scene)
        resetAccumulation()
        return true
    }

    public func applyAnimation(name: String?, time: Float) {
        applyAnimations(names: name.map { Set([$0]) } ?? [], time: time)
    }

    public func applyAnimations(names: Set<String>, time: Float) {
        guard let url = modelURL,
              let scene = GLBLoader.loadModel(from: url, device: device, selectedAnimations: names, time: time, charging: charging, wheelDegrees: wheelDegrees,
                                             headlightsOn: headlightsOn, drlOn: drlOn, brakeLightsOn: brakeLightsOn,
                                             turnSignalLeftOn: turnSignalLeftOn, turnSignalRightOn: turnSignalRightOn,
                                             showRoofLightbar: showRoofLightbar) else { return }
        currentScene = scene
        buildAccelerationStructure(from: scene)
        resetAccumulation()
    }

    private func buildAccelerationStructure(from scene: ModelSceneData) {
        // Derive the beam emitters from the actual front lamp triangles, never
        // from selected paint metallicity or sedan-sized hardcoded coordinates.
        for side in 0..<2 {
            var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
            for g in scene.geometries where g.lightRole == "headlights" {
                for index in g.indices {
                    let v = g.vertices[Int(index)].position, p = SIMD3(v.x,v.y,v.z)
                    if p.x > 0 && (side == 0 ? p.z < -0.02 : p.z > 0.02) { lo = simd_min(lo,p); hi = simd_max(hi,p) }
                }
            }
            headlampPositions[side] = lo.x.isFinite ? SIMD4((lo+hi)/2,1) : .zero
        }
        rearStrip = .zero; rearStripSize = .zero
        // Juniper's authored parking emitter illuminates the recessed TESLA panel
        // from above. Keep its actual location; do not turn it toward the camera.
        if let lamp = scene.geometries.first(where: { $0.lightRole == "parking" && $0.emissive > 0 }) {
            let points = lamp.indices.map { lamp.vertices[Int($0)].position }
            var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
            for v in points { let p = SIMD3(v.x,v.y,v.z); lo = simd_min(lo,p); hi = simd_max(hi,p) }
            // Sample the upper recess lip: the source card extends into the
            // housing, while its effective aperture must sit above the receiver.
            var lip = lo.x
            let span = (hi.z-lo.z)*0.4
            for g in scene.geometries where g.componentName.contains("Trunk_Cover") {
                for index in g.indices {
                    let p = g.vertices[Int(index)].position
                    if p.y < lo.y && p.y > lo.y-0.06 && abs(p.z) < span { lip = min(lip,p.x) }
                }
            }
            rearStrip = SIMD4(min(lo.x,lip)-0.003,lo.y,(lo.z+hi.z)/2,lamp.emissive)
            rearStripSize = SIMD4((hi.z-lo.z)/2,0,0,0)
        }
        var allVertices: [RaytraceVertex] = []
        var allIndices: [UInt32] = []
        var geomInfos: [GeometryInfoGPU] = []
        var geomDescriptors: [MTLAccelerationStructureTriangleGeometryDescriptor] = []

        for geom in scene.geometries + SceneGeometry.make(for: lighting) {
            // Source additive lamp meshes are invisible when off; an opaque
            // black substitute would hide running lights layered behind them.
            if geom.isLampOverlay && geom.emissive <= 0 { continue }
            guard geom.vertices.count > 0, geom.indices.count > 0 else { continue }

            let vOffset = UInt32(allVertices.count)
            let iOffset = UInt32(allIndices.count)

            allVertices.append(contentsOf: geom.vertices)

            // Shift each index so allIndices contains global indices into allVertices
            allIndices.append(contentsOf: geom.indices.map { $0 + vOffset })

            var info = GeometryInfoGPU()
            info.emission = SIMD4(geom.emissionColor,Float(geom.emissionTexture))
            info.textures = geom.textures
            info.vertexOffset = vOffset
            info.indexOffset = iOffset
            info.isGround = geom.isGround
            info.isPaint = geom.isPaint
            info.baseColor = SIMD4<Float>(geom.baseColor.x, geom.baseColor.y, geom.baseColor.z, geom.metallic)
            info.params = SIMD4<Float>(geom.roughness, geom.clearcoat, geom.emissive, geom.transmission)
            geomInfos.append(info)

            let desc = MTLAccelerationStructureTriangleGeometryDescriptor()
            desc.vertexBuffer = nil // Set below
            desc.vertexBufferOffset = 0
            desc.vertexStride = MemoryLayout<RaytraceVertex>.stride // 48 bytes
            desc.indexBuffer = nil // Set below
            desc.indexType = .uint32
            desc.indexBufferOffset = Int(iOffset) * MemoryLayout<UInt32>.stride
            desc.triangleCount = geom.indices.count / 3
            geomDescriptors.append(desc)
        }

        // Create unified Metal vertex and index buffers
        let vb = device.makeBuffer(
            bytes: allVertices,
            length: allVertices.count * MemoryLayout<RaytraceVertex>.stride,
            options: .storageModeShared
        )!
        let ib = device.makeBuffer(
            bytes: allIndices,
            length: allIndices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!
        let gb = device.makeBuffer(
            bytes: geomInfos,
            length: geomInfos.count * MemoryLayout<GeometryInfoGPU>.stride,
            options: .storageModeShared
        )!

        self.vertexBuffer = vb
        self.indexBuffer = ib
        self.geometryBuffer = gb
        self.geometryCount = geomInfos.count

        // Assign buffers to geometry descriptors
        for desc in geomDescriptors {
            desc.vertexBuffer = vb
            desc.indexBuffer = ib
        }

        // Build Hardware Acceleration Structure
        let asDesc = MTLPrimitiveAccelerationStructureDescriptor()
        asDesc.geometryDescriptors = geomDescriptors

        let sizes = device.accelerationStructureSizes(descriptor: asDesc)
        let accel = device.makeAccelerationStructure(size: sizes.accelerationStructureSize)!
        let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize, options: .storageModePrivate)!

        let cmd = commandQueue.makeCommandBuffer()!
        let enc = cmd.makeAccelerationStructureCommandEncoder()!
        enc.build(accelerationStructure: accel, descriptor: asDesc, scratchBuffer: scratch, scratchBufferOffset: 0)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        self.accelerationStructure = accel

    }

    /// Exercise the actual visibility shader against opaque/glass/beyond-plane fixtures.
    public func validateClimateOcclusion() -> [Float]? {
        let saved = currentScene
        defer { if let saved { buildAccelerationStructure(from: saved) } }
        var scene = ModelSceneData()
        func pane(x: Float, z: Float, transmission: Float) -> GeometryData {
            var g=GeometryData(); g.transmission=transmission
            g.vertices=[SIMD3(x-0.8,-0.8,z),SIMD3(x+0.8,-0.8,z),SIMD3(x,0.8,z)]
                .map { RaytraceVertex(position: $0,normal: SIMD3(0,0,-1)) }
            g.indices=[0,1,2]; return g
        }
        scene.geometries=[pane(x:0,z:0,transmission:0),pane(x:2,z:0,transmission:0.96),
                          pane(x:4,z:0,transmission:0.96),pane(x:4,z:1,transmission:0),
                          pane(x:8,z:3,transmission:0)]
        buildAccelerationStructure(from: scene)
        do {
            let library=try device.makeLibrary(source: ShaderSource.metalRaytracingSource,options:nil)
            guard let function=library.makeFunction(name:"climateOcclusionProbe"),
                  let output=device.makeBuffer(length:5*MemoryLayout<Float>.stride,options:.storageModeShared),
                  let command=commandQueue.makeCommandBuffer(),let encoder=command.makeComputeCommandEncoder() else { return nil }
            let pipeline=try device.makeComputePipelineState(function:function)
            encoder.setComputePipelineState(pipeline)
            encoder.setAccelerationStructure(accelerationStructure,bufferIndex:0)
            encoder.setBuffer(geometryBuffer,offset:0,index:1); encoder.setBuffer(output,offset:0,index:2)
            encoder.dispatchThreads(MTLSize(width:5,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:5,height:1,depth:1))
            encoder.endEncoding();command.commit();command.waitUntilCompleted()
            guard command.status == .completed else { return nil }
            return Array(UnsafeBufferPointer(start:output.contents().assumingMemoryBound(to:Float.self),count:5))
        } catch { print("Climate visibility probe failed: \(error)");return nil }
    }

    public func resetAccumulation() {
        sampleIndex = 0
        isDirty = true
    }

    private func updateTextures(width: Int, height: Int, pixelFormat: MTLPixelFormat) {
        if width == currentWidth && height == currentHeight && accumTexture != nil { return }

        currentWidth = width
        currentHeight = height

        let accumDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        accumDesc.usage = [.shaderRead, .shaderWrite]
        accumDesc.storageMode = .private
        accumTexture = device.makeTexture(descriptor: accumDesc)

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        outDesc.usage = [.shaderWrite, .shaderRead]
        outDesc.storageMode = .private
        outputTexture = device.makeTexture(descriptor: outDesc)

        resetAccumulation()
    }

    public func render(
        in view: MTKView,
        camera: Camera,
        paintColor: SIMD3<Float>,
        metallic: Float,
        roughness: Float,
        clearcoat: Float,
        groundReflectivity: Float,
        groundRoughness: Float,
        isPrivacyTint: Bool,
        privacyTintDarkness: Float,
        isInteracting: Bool
    ) {
        guard let drawable = view.currentDrawable,
              let accel = accelerationStructure,
              let vb = vertexBuffer,
              let ib = indexBuffer,
              let gb = geometryBuffer else { return }

        let w = Int(view.drawableSize.width)
        let h = Int(view.drawableSize.height)
        guard w > 0 && h > 0 else { return }

        let targetPixelFormat = view.colorPixelFormat
        updateTextures(width: w, height: h, pixelFormat: targetPixelFormat)

        if isInteracting {
            sampleIndex = 0
        } else if sampleIndex >= maxSamples {
            return // Converged
        }

        let aspect = Float(w) / Float(h)
        let viewMat = camera.viewMatrix()
        let projMat = camera.projectionMatrix(aspect: aspect)

        let tintTrans = 0.82 * (1.0 - privacyTintDarkness) + 0.08 * privacyTintDarkness

        var uniforms = UniformsGPU()
        let beamsActive: Float = (headlightsOn && showLightBeams) ? 1.0 : 0.0
        uniforms.rearStrip = rearStrip; uniforms.rearStripSize = rearStripSize
        uniforms.headlampLeft = headlampPositions[0]; uniforms.headlampRight = headlampPositions[1]
        uniforms.weather = SIMD4(rainIntensity,wetness,weatherTime,beamsActive)
        uniforms.renderOptions = SIMD4(lighting.shaderIndex,exposure,windowTrim.shaderIndex,headlightReflection)
        uniforms.effectParams = SIMD4(effectTime,drivingSpeed,climateMode,signalState)
        uniforms.effectTextures = SIMD4(currentScene?.roadTexture ?? -1,Int32(currentScene?.climatePlanes.count ?? 0),currentScene?.noiseTexture ?? -1,0)
        uniforms.climateLeft = currentScene?.climatePlanes.first ?? matrix_identity_float4x4
        uniforms.climateRight = currentScene?.climatePlanes.dropFirst().first ?? matrix_identity_float4x4
        uniforms.invView = viewMat.inverse
        uniforms.invProj = projMat.inverse
        uniforms.cameraPos = SIMD4<Float>(camera.position.x, camera.position.y, camera.position.z, 1.0)
        uniforms.carPaintColor = SIMD4<Float>(paintColor.x, paintColor.y, paintColor.z, metallic)
        uniforms.materialParams = SIMD4<Float>(roughness, clearcoat, groundReflectivity, groundRoughness)
        uniforms.viewport = SIMD4<UInt32>(UInt32(w), UInt32(h), sampleIndex, isInteracting ? 0 : 1)
        uniforms.tintParams = SIMD4<Float>(
            isPrivacyTint ? 1.0 : 0.0,
            tintTrans,
            privacyTintDarkness,
            0.0
        )
        if uniforms.tintParams != lastTintParams {
            lastTintParams = uniforms.tintParams
            sampleIndex = 0
            uniforms.viewport.z = 0
        }

        let ub = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<UniformsGPU>.stride, options: .storageModeShared)!
        self.uniformsBuffer = ub

        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return }

        enc.setComputePipelineState(pipelineState)
        enc.setAccelerationStructure(accel, bufferIndex: 0)
        enc.setBuffer(vb, offset: 0, index: 1)
        enc.setBuffer(ib, offset: 0, index: 2)
        enc.setBuffer(gb, offset: 0, index: 3)
        enc.setBuffer(ub, offset: 0, index: 4)
        enc.setTexture(accumTexture, index: 0)
        enc.setTexture(outputTexture, index: 1)
        for (i, texture) in (currentScene?.textures ?? []).enumerated() { enc.setTexture(texture, index: i+2) }

        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (w + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (h + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        enc.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        enc.endEncoding()

        // Blit output texture to MTKView drawable
        if let blitEnc = cmd.makeBlitCommandEncoder() {
            blitEnc.copy(
                from: outputTexture!,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: drawable.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEnc.endEncoding()
        }

        cmd.present(drawable)
        cmd.commit()

        if !isInteracting && sampleIndex < maxSamples {
            sampleIndex += 1
        }
    }

    public func renderToImage(
        width: Int,
        height: Int,
        samples: Int,
        camera: Camera,
        paintColor: SIMD3<Float>,
        metallic: Float,
        roughness: Float,
        clearcoat: Float,
        groundReflectivity: Float,
        groundRoughness: Float,
        isPrivacyTint: Bool,
        privacyTintDarkness: Float
    ) -> CGImage? {
        guard let accel = accelerationStructure,
              let vb = vertexBuffer,
              let ib = indexBuffer,
              let gb = geometryBuffer else { return nil }

        let w = width
        let h = height
        updateTextures(width: w, height: h, pixelFormat: .rgba8Unorm)

        let aspect = Float(w) / Float(h)
        let viewMat = camera.viewMatrix()
        let projMat = camera.projectionMatrix(aspect: aspect)
        let tintTrans = 0.82 * (1.0 - privacyTintDarkness) + 0.08 * privacyTintDarkness

        var uniforms = UniformsGPU()
        uniforms.rearStrip = rearStrip; uniforms.rearStripSize = rearStripSize
        uniforms.headlampLeft = headlampPositions[0]; uniforms.headlampRight = headlampPositions[1]
        uniforms.weather = SIMD4(rainIntensity,wetness,weatherTime,(headlightsOn && showLightBeams) ? 1 : 0)
        uniforms.renderOptions = SIMD4(lighting.shaderIndex,exposure,windowTrim.shaderIndex,headlightReflection)
        uniforms.effectParams = SIMD4(effectTime,drivingSpeed,climateMode,signalState)
        uniforms.effectTextures = SIMD4(currentScene?.roadTexture ?? -1,Int32(currentScene?.climatePlanes.count ?? 0),currentScene?.noiseTexture ?? -1,0)
        uniforms.climateLeft = currentScene?.climatePlanes.first ?? matrix_identity_float4x4
        uniforms.climateRight = currentScene?.climatePlanes.dropFirst().first ?? matrix_identity_float4x4
        uniforms.invView = viewMat.inverse
        uniforms.invProj = projMat.inverse
        uniforms.cameraPos = SIMD4<Float>(camera.position.x, camera.position.y, camera.position.z, 1.0)
        uniforms.carPaintColor = SIMD4<Float>(paintColor.x, paintColor.y, paintColor.z, metallic)
        uniforms.materialParams = SIMD4<Float>(roughness, clearcoat, groundReflectivity, groundRoughness)
        uniforms.tintParams = SIMD4<Float>(isPrivacyTint ? 1.0 : 0.0, tintTrans, privacyTintDarkness, 0.0)

        for s in 0..<samples {
            uniforms.viewport = SIMD4<UInt32>(UInt32(w), UInt32(h), UInt32(s), s > 0 ? 1 : 0)
            guard let ub = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<UniformsGPU>.stride, options: .storageModeShared),
                  let cmd = commandQueue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else { continue }

            enc.setComputePipelineState(pipelineState)
            enc.setAccelerationStructure(accel, bufferIndex: 0)
            enc.setBuffer(vb, offset: 0, index: 1)
            enc.setBuffer(ib, offset: 0, index: 2)
            enc.setBuffer(gb, offset: 0, index: 3)
            enc.setBuffer(ub, offset: 0, index: 4)
            enc.setTexture(accumTexture, index: 0)
            enc.setTexture(outputTexture, index: 1)
        for (i, texture) in (currentScene?.textures ?? []).enumerated() { enc.setTexture(texture, index: i+2) }

            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadGroups = MTLSize(
                width: (w + threadsPerGroup.width - 1) / threadsPerGroup.width,
                height: (h + threadsPerGroup.height - 1) / threadsPerGroup.height,
                depth: 1
            )
            enc.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
        }

        let bytesPerRow = w * 4
        let totalBytes = bytesPerRow * h
        var rawBytes = [UInt8](repeating: 0, count: totalBytes)

        let readDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        readDesc.storageMode = .shared
        guard let readTex = device.makeTexture(descriptor: readDesc),
              let cmd = commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }

        blit.copy(from: outputTexture!, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1), to: readTex, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        readTex.getBytes(&rawBytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rawBytes) as CFData),
              let cgImage = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { return nil }

        return cgImage
    }
}
