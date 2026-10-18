import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

extension Collider {
    /// Line-list vertices (pairs) outlining the collider.
    var wireframe: [SIMD4<Float>] {
        switch self {
        case let .plane(normal, distance):
            let n = simd_normalize(normal)
            let helper: SIMD3<Float> = abs(n.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(helper, n))
            let v = simd_cross(n, u)
            let origin = n * distance
            let extent: Float = 4
            let steps = 8
            var lines: [SIMD3<Float>] = []
            for index in 0...steps {
                let t = -extent + 2 * extent * Float(index) / Float(steps)
                lines += [origin + u * t - v * extent, origin + u * t + v * extent]
                lines += [origin + v * t - u * extent, origin + v * t + u * extent]
            }
            return lines.map { SIMD4($0, 1) }
        case let .sphere(center, radius):
            let segments = 48
            var lines: [SIMD3<Float>] = []
            for axis in 0..<3 {
                for index in 0..<segments {
                    for step in [index, index + 1] {
                        let angle = Float(step) / Float(segments) * 2 * .pi
                        let (c, s) = (cos(angle) * radius, sin(angle) * radius)
                        let point: SIMD3<Float> = axis == 0 ? [c, s, 0] : axis == 1 ? [c, 0, s] : [0, c, s]
                        lines.append(center + point)
                    }
                }
            }
            return lines.map { SIMD4($0, 1) }
        case let .capsule(start, end, radius):
            let axis = end - start
            let direction = simd_length(axis) > 0 ? simd_normalize(axis) : SIMD3<Float>(0, 1, 0)
            let helper: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(helper, direction))
            let v = simd_cross(direction, u)
            var lines: [SIMD3<Float>] = []
            // Arc from `fromAngle` to `toAngle` in the plane spanned by `x` and `y` around `center`.
            func arc(_ center: SIMD3<Float>, _ x: SIMD3<Float>, _ y: SIMD3<Float>, from fromAngle: Float, to toAngle: Float) {
                let segments = 24
                for index in 0..<segments {
                    for step in [index, index + 1] {
                        let angle = fromAngle + (toAngle - fromAngle) * Float(step) / Float(segments)
                        lines.append(center + (x * cos(angle) + y * sin(angle)) * radius)
                    }
                }
            }
            arc(start, u, v, from: 0, to: 2 * .pi)
            arc(end, u, v, from: 0, to: 2 * .pi)
            for side in [u, -u, v, -v] {
                lines += [start + side * radius, end + side * radius]
            }
            for side in [u, v] {
                arc(end, side, direction, from: 0, to: .pi)
                arc(start, side, -direction, from: 0, to: .pi)
            }
            return lines.map { SIMD4($0, 1) }
        case let .box(center, halfExtents, rotation):
            let corners = (0..<8).map { index in
                center + rotation.act(halfExtents * SIMD3<Float>(index & 1 == 0 ? -1 : 1, index & 2 == 0 ? -1 : 1, index & 4 == 0 ? -1 : 1))
            }
            // Corners differing in exactly one bit share an edge.
            var lines: [SIMD3<Float>] = []
            for a in 0..<8 {
                for bit in [1, 2, 4] where a & bit == 0 {
                    lines += [corners[a], corners[a | bit]]
                }
            }
            return lines.map { SIMD4($0, 1) }
        }
    }
}

public extension ParticleSystem {
    /// Draws the system's colliders as flat-colored wireframes. Place inside a `RenderPass`.
    func renderColliders(projection: simd_float4x4, view: simd_float4x4, color: SIMD4<Float> = [0.4, 0.6, 1, 1]) throws -> some Element {
        try wireframe(colliders.flatMap(\.wireframe), color: color, viewProjection: projection * view)
    }
}
