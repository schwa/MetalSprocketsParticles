import MetalSprocketsParticlesShaders
import simd

/// A world-space shape that particles bounce off.
public enum Collider: Sendable, Equatable {
    case plane(normal: SIMD3<Float>, distance: Float)
    case sphere(center: SIMD3<Float>, radius: Float)
    case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    /// A line segment from `start` to `end` with rounded ends.
    case capsule(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float)
}

extension Collider {
    /// Linear velocity implied by moving from `previous` to `self` over `deltaTime`. Zero if the shape changed kind
    /// or orientation, or if no time passed. Rotation is not turned into velocity: spinning boxes do not fling particles.
    func velocity(from previous: Collider, deltaTime: Float) -> SIMD3<Float> {
        guard deltaTime > 0 else {
            return .zero
        }
        switch (previous, self) {
        case let (.plane(oldNormal, oldDistance), .plane(normal, distance)) where simd_normalize(oldNormal) == simd_normalize(normal):
            return simd_normalize(normal) * (distance - oldDistance) / deltaTime
        case let (.sphere(oldCenter, _), .sphere(center, _)):
            return (center - oldCenter) / deltaTime
        case let (.box(oldCenter, _, _), .box(center, _, _)):
            return (center - oldCenter) / deltaTime
        case let (.capsule(oldStart, oldEnd, _), .capsule(start, end, _)):
            return ((start + end) - (oldStart + oldEnd)) / 2 / deltaTime
        default:
            return .zero
        }
    }
}

extension ColliderData {
    init(_ collider: Collider, velocity: SIMD3<Float> = .zero) {
        self.init()
        self.velocity = velocity
        rotation = [0, 0, 0, 1]
        switch collider {
        case let .plane(normal, distance):
            kind = .plane
            self.normal = simd_normalize(normal)
            self.distance = distance
        case let .sphere(center, radius):
            kind = .sphere
            self.center = center
            self.radius = radius
        case let .box(center, halfExtents, rotation):
            kind = .box
            self.center = center
            self.halfExtents = halfExtents
            self.rotation = simd_normalize(rotation).vector
        case let .capsule(start, end, radius):
            kind = .capsule
            center = start
            self.end = end
            self.radius = radius
        }
    }
}
