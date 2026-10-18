import simd

/// Legacy Model S merges upholstery and cabin trim into one source material.
/// Select whole disconnected cushion/backrest islands in its authored coordinates;
/// retain every original triangle and leave the dashboard and door trim separate.
enum SeatSurfaces {
    static func legacyModelSVertices(positions: [[Float]], indices: [UInt32]) -> Set<UInt32> {
        var parents = Array(positions.indices)
        func root(_ start: Int) -> Int {
            var i = start
            while parents[i] != i { parents[i] = parents[parents[i]]; i = parents[i] }
            return i
        }
        for t in stride(from: 0,to: indices.count,by: 3) {
            let a = root(Int(indices[t]))
            parents[root(Int(indices[t+1]))] = a
            parents[root(Int(indices[t+2]))] = a
        }
        var islands: [Int: [Int]] = [:]
        for i in positions.indices { islands[root(i),default: []].append(i) }
        var selected = Set<UInt32>()
        for island in islands.values where island.count >= 12 {
            var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
            for i in island {
                let p = positions[i], v = SIMD3(p[0],p[1],p[2])
                lo = simd_min(lo,v); hi = simd_max(hi,v)
            }
            let front = lo.x > -0.45 && hi.x < 0.41 && lo.y > 0.30 && hi.y < 1.27 && (lo.z > 0.08 || hi.z < -0.08)
            let rear = lo.x > -1.30 && hi.x < -0.48 && lo.y > 0.32 && hi.y < 1.30
            if (front || rear) && max(abs(lo.z),abs(hi.z)) < 0.71 && hi.y-lo.y > 0.15 {
                selected.formUnion(island.map(UInt32.init))
            }
        }
        return selected
    }
}
