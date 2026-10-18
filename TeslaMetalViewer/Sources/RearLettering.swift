import simd

/// Isolate the eight disconnected pieces of Juniper's five rear letters from
/// the shared trim mesh. Selection uses source-local coordinates so it follows
/// the trunk through source animations without selecting the surrounding trim.
enum RearLettering {
    static func vertices(positions: [[Float]], indices: [UInt32]) -> Set<UInt32> {
        var parents = Array(positions.indices)
        func root(_ start: Int) -> Int {
            var i = start
            while parents[i] != i { parents[i] = parents[parents[i]]; i = parents[i] }
            return i
        }
        var welded: [SIMD3<Int32>: Int] = [:]
        for (i,p) in positions.enumerated() {
            let key = SIMD3<Int32>(Int32((p[0]*100000).rounded()),Int32((p[1]*100000).rounded()),Int32((p[2]*100000).rounded()))
            if let other = welded[key] { parents[root(i)] = root(other) } else { welded[key] = i }
        }
        for t in stride(from: 0,to: indices.count,by: 3) {
            let a = root(Int(indices[t]))
            parents[root(Int(indices[t+1]))] = a
            parents[root(Int(indices[t+2]))] = a
        }
        var islands: [Int: [UInt32]] = [:]
        for i in Set(indices) { islands[root(Int(i)),default: []].append(i) }
        var selected = Set<UInt32>()
        for island in islands.values {
            var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
            for i in island {
                let p = positions[Int(i)], v = SIMD3(p[0],p[1],p[2])
                lo = simd_min(lo,v); hi = simd_max(hi,v)
            }
            let size = hi-lo
            if lo.x > -0.26 && hi.x < 0.26 && lo.y > 1.02 && hi.y < 1.06 && lo.z > 1.9 && hi.z < 2.5
                && size.x < 0.04 && size.y < 0.025 && size.z < 0.025 && island.count >= 12 {
                selected.formUnion(island)
            }
        }
        return selected
    }
}
