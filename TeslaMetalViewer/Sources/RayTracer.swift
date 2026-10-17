import Foundation
import Metal
import MetalKit
import simd

public struct GeometryInfoGPU {
    public var vertexOffset: UInt32 = 0 // offset 0..4
    public var indexOffset: UInt32 = 0  // offset 4..8
    public var isGround: UInt32 = 0     // offset 8..12
    public var isPaint: UInt32 = 0      // offset 12..16
    public var baseColor: SIMD4<Float> = .zero // offset 16..32 (xyz = rgb, w = metallic)
    public var params: SIMD4<Float> = .zero    // offset 32..48 (x = roughness, y = clearcoat, z = emissive, w = 0)
}

public struct UniformsGPU {
    public var invView: simd_float4x4 = matrix_identity_float4x4 // offset 0..64
    public var invProj: simd_float4x4 = matrix_identity_float4x4 // offset 64..128
    public var cameraPos: SIMD4<Float> = .zero                   // offset 128..144 (xyz = pos, w = 1.0)
    public var carPaintColor: SIMD4<Float> = .zero               // offset 144..160 (xyz = rgb, w = metallic)
    public var materialParams: SIMD4<Float> = .zero              // offset 160..176 (x = roughness, y = clearcoat, z = groundReflectivity, w = groundRoughness)
    public var viewport: SIMD4<UInt32> = .zero                   // offset 176..192 (x = width, y = height, z = sampleIndex, w = isAccumulating)
    public var tintParams: SIMD4<Float> = .zero                  // offset 192..208 (x = isPrivacyTint, y = transmission, z = darkness, w = 0)
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
    
    public func loadModel(filename: String) -> Bool {
        guard let url = TeslaCatalog.resolveModelPath(filename: filename) else {
            print("Could not find model file: \(filename)")
            return false
        }
        
        guard let scene = GLBLoader.loadModel(from: url, device: device) else {
            print("Failed to load and parse GLB: \(filename)")
            return false
        }
        
        self.currentScene = scene
        buildAccelerationStructure(from: scene)
        resetAccumulation()
        return true
    }
    
    private func buildAccelerationStructure(from scene: ModelSceneData) {
        var allVertices: [RaytraceVertex] = []
        var allIndices: [UInt32] = []
        var geomInfos: [GeometryInfoGPU] = []
        var geomDescriptors: [MTLAccelerationStructureTriangleGeometryDescriptor] = []
        
        for geom in scene.geometries {
            guard geom.vertices.count > 0, geom.indices.count > 0 else { continue }
            
            let vOffset = UInt32(allVertices.count)
            let iOffset = UInt32(allIndices.count)
            
            allVertices.append(contentsOf: geom.vertices)
            
            // Shift each index so allIndices contains global indices into allVertices
            allIndices.append(contentsOf: geom.indices.map { $0 + vOffset })
            
            var info = GeometryInfoGPU()
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
            desc.vertexStride = MemoryLayout<RaytraceVertex>.stride // 32 bytes
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
        print("Hardware Ray Tracing Acceleration Structure built with \(scene.totalTriangles) triangles!")
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
        
        let ub = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<UniformsGPU>.stride, options: .storageModeShared)!
        self.uniformsBuffer = ub
        
        // Dynamically keep geometryBuffer in sync with the current paint color and params
        if let gb = geometryBuffer, geometryCount > 0 {
            let ptr = gb.contents().bindMemory(to: GeometryInfoGPU.self, capacity: geometryCount)
            for i in 0..<geometryCount {
                if ptr[i].isPaint == 1 {
                    ptr[i].baseColor = SIMD4<Float>(paintColor.x, paintColor.y, paintColor.z, metallic)
                    ptr[i].params.x = roughness
                    ptr[i].params.y = clearcoat
                }
            }
        }
        
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
}
