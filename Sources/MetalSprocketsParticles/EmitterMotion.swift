import simd

/// Moves an emitter over time, for trails and moving sources. Produces the transform to pass to
/// `ParticleSystem.simulate(deltaTime:colliders:transforms:)`.
public struct EmitterMotion: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case still = "Still"
        case circle = "Circle"
        case bounce = "Bounce"
        /// A figure eight in the XZ plane.
        case figureEight = "Figure Eight"

        public var id: Self { self }
    }

    public var kind: Kind
    public var radius: Float
    public var speed: Float
    /// Added to the moving point, so a path can sit above the ground.
    public var offset: SIMD3<Float>
    /// Turns the emitter around +Y, in radians.
    public var yaw: Float

    public init(kind: Kind = .still, radius: Float = 1.5, speed: Float = 1, offset: SIMD3<Float> = .zero, yaw: Float = 0) {
        self.kind = kind
        self.radius = radius
        self.speed = speed
        self.offset = offset
        self.yaw = yaw
    }

    public func transform(time: Float) -> simd_float4x4 {
        let angle = time * speed
        let position: SIMD3<Float> = switch kind {
        case .still: .zero
        case .circle: [cos(angle) * radius, 0, sin(angle) * radius]
        case .bounce: [0, abs(sin(angle)) * radius, 0]
        case .figureEight: [sin(angle) * radius, 0, sin(angle * 2) * radius * 0.5]
        }
        var transform = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        transform.columns.3 = SIMD4(position + offset, 1)
        return transform
    }
}

public extension Collider {
    func translated(by offset: SIMD3<Float>) -> Collider {
        switch self {
        case let .plane(normal, distance):
            .plane(normal: normal, distance: distance + simd_dot(offset, simd_normalize(normal)))
        case let .sphere(center, radius):
            .sphere(center: center + offset, radius: radius)
        case let .box(center, halfExtents, rotation):
            .box(center: center + offset, halfExtents: halfExtents, rotation: rotation)
        case let .capsule(start, end, radius):
            .capsule(start: start + offset, end: end + offset, radius: radius)
        }
    }

    /// A simple showcase animation: spheres bob, boxes slide in x, capsules slide in z, planes stay put. `index`
    /// staggers the phase so colliders do not move in lockstep.
    func animated(time: Float, index: Int) -> Collider {
        let phase = time + Float(index) * 1.7
        return switch self {
        case .plane: self
        case .sphere: translated(by: [0, 0.6 * sin(phase * 1.3), 0])
        case .box: translated(by: [0.5 * sin(phase * 0.9), 0, 0])
        case .capsule: translated(by: [0, 0, 0.6 * sin(phase * 0.7)])
        }
    }
}
