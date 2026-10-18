import simd

/// Godot Transform-valued property keys store a row-major basis and an origin.
/// Interpolate rotation with slerp, rather than lerping the twelve matrix values,
/// which would shrink the struts between authored rotations.
enum SourceTransform {
    static func matrix(_ value: [Float]) -> simd_float4x4 {
        simd_float4x4(SIMD4(value[0],value[3],value[6],0),
                      SIMD4(value[1],value[4],value[7],0),
                      SIMD4(value[2],value[5],value[8],0),
                      SIMD4(value[9],value[10],value[11],1))
    }

    static func interpolate(_ a: [Float], _ b: [Float], fraction: Float) -> simd_float4x4 {
        let first = matrix(a), last = matrix(b)
        if fraction <= 0 { return first }
        if fraction >= 1 { return last }
        func parts(_ m: simd_float4x4) -> (simd_quatf,SIMD3<Float>) {
            var basis = simd_float3x3(SIMD3(m[0].x,m[0].y,m[0].z),
                                      SIMD3(m[1].x,m[1].y,m[1].z),
                                      SIMD3(m[2].x,m[2].y,m[2].z))
            var scale = SIMD3(simd_length(basis[0]),simd_length(basis[1]),simd_length(basis[2]))
            if simd_determinant(basis) < 0 { scale.x = -scale.x }
            for column in 0..<3 where abs(scale[column]) > 0.000001 { basis[column] /= scale[column] }
            return (simd_normalize(simd_quatf(basis)),scale)
        }
        let (rotationA,scaleA) = parts(first), (rotationB,scaleB) = parts(last)
        var result = simd_matrix4x4(simd_slerp(rotationA,rotationB,fraction))
        let scale = simd_mix(scaleA,scaleB,SIMD3(repeating: fraction))
        for column in 0..<3 { result[column] *= scale[column] }
        result.columns.3 = first.columns.3+(last.columns.3-first.columns.3)*fraction
        return result
    }
}
