import simd

/// Spins one of a particle system's colliders at a steady rate about its own pivot (a sphere's or box's center, a capsule's
/// midpoint). The system derives the angular velocity from frame to frame, so spinning colliders fling particles.
public struct ColliderSpin: Sendable, Equatable, Codable {
    /// Index into `ParticleSystem.colliders`.
    public var collider: Int
    public var axis: SIMD3<Float>
    /// Radians per second.
    public var speed: Float

    public init(collider: Int, axis: SIMD3<Float>, speed: Float) {
        self.collider = collider
        self.axis = axis
        self.speed = speed
    }

    /// The rotation after `time` seconds.
    public func rotation(at time: Float) -> simd_quatf {
        guard simd_length(axis) > 0 else {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        return simd_quatf(angle: speed * time, axis: simd_normalize(axis))
    }
}

public extension Collider {
    /// The collider turned by `rotation` about its pivot. Planes and spheres look the same, so they are unchanged.
    func rotated(by rotation: simd_quatf) -> Self {
        switch shape {
        case .plane, .sphere:
            return self
        case let .box(center, halfExtents, boxRotation):
            return Self(.box(center: center, halfExtents: halfExtents, rotation: simd_normalize(rotation * boxRotation)), categoryBitMask: categoryBitMask)
        case let .capsule(start, end, radius):
            let pivot = (start + end) / 2
            return Self(.capsule(start: pivot + rotation.act(start - pivot), end: pivot + rotation.act(end - pivot), radius: radius), categoryBitMask: categoryBitMask)
        }
    }
}

public extension [Collider] {
    /// The colliders with `spins` applied at `time`. Spins with an out-of-range index are ignored.
    func spun(_ spins: [ColliderSpin], at time: Float) -> Self {
        var colliders = self
        for spin in spins where colliders.indices.contains(spin.collider) {
            colliders[spin.collider] = colliders[spin.collider].rotated(by: spin.rotation(at: time))
        }
        return colliders
    }
}
