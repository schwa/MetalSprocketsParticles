import MetalSprocketsParticlesShaders
import simd
import SwiftMesh

/// A world-space shape that particles bounce off. Only emitters whose `EmitterModules.categoryMask` shares a bit with
/// `categoryBitMask` collide with it.
public struct Collider: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case plane(normal: SIMD3<Float>, distance: Float)
        case sphere(center: SIMD3<Float>, radius: Float)
        case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        /// A line segment from `start` to `end` with rounded ends.
        case capsule(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float)
        /// A baked signed distance field (negative inside) in the collider's local space, placed by `center` and
        /// `rotation`. Bake one from a mesh with SwiftMesh's `Mesh.signedDistanceField(resolution:padding:bvh:)`.
        case signedDistanceField(SignedDistanceField, center: SIMD3<Float> = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    }

    public var shape: Shape
    /// All bits by default, so every emitter collides.
    public var categoryBitMask: UInt32

    public init(_ shape: Shape, categoryBitMask: UInt32 = .max) {
        self.shape = shape
        self.categoryBitMask = categoryBitMask
    }

    public static func plane(normal: SIMD3<Float>, distance: Float, categoryBitMask: UInt32 = .max) -> Self {
        Self(.plane(normal: normal, distance: distance), categoryBitMask: categoryBitMask)
    }

    public static func sphere(center: SIMD3<Float>, radius: Float, categoryBitMask: UInt32 = .max) -> Self {
        Self(.sphere(center: center, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func box(
        center: SIMD3<Float>,
        halfExtents: SIMD3<Float>,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        categoryBitMask: UInt32 = .max
    ) -> Self {
        Self(.box(center: center, halfExtents: halfExtents, rotation: rotation), categoryBitMask: categoryBitMask)
    }

    public static func capsule(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float, categoryBitMask: UInt32 = .max) -> Self {
        Self(.capsule(start: start, end: end, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func signedDistanceField(
        _ field: SignedDistanceField,
        center: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        categoryBitMask: UInt32 = .max
    ) -> Self {
        Self(.signedDistanceField(field, center: center, rotation: rotation), categoryBitMask: categoryBitMask)
    }
}

extension Collider.Shape {
    /// A signed distance field's grid as a box in world space; nil for other shapes.
    var signedDistanceFieldBounds: Collider.Shape? {
        guard case let .signedDistanceField(field, center, rotation) = self else {
            return nil
        }
        let bounds = field.localBounds
        return .box(center: center + rotation.act(bounds.center), halfExtents: bounds.halfExtents, rotation: rotation)
    }
}

extension SignedDistanceField {
    /// The grid's box in its local space: from the first sample to the last.
    var localBounds: (center: SIMD3<Float>, halfExtents: SIMD3<Float>) {
        let size = spacing * SIMD3<Float>(resolution &- 1)
        return (origin + size / 2, abs(size) / 2)
    }
}

extension Collider {
    /// Linear velocity implied by moving from `previous` to `self` over `deltaTime`. Zero if the shape changed kind
    /// or orientation, or if no time passed. Rotation is not turned into velocity: spinning boxes do not fling particles.
    func velocity(from previous: Collider, deltaTime: Float) -> SIMD3<Float> {
        guard deltaTime > 0 else {
            return .zero
        }
        switch (previous.shape, shape) {
        case let (.plane(oldNormal, oldDistance), .plane(normal, distance)) where simd_normalize(oldNormal) == simd_normalize(normal):
            return simd_normalize(normal) * (distance - oldDistance) / deltaTime
        case let (.sphere(oldCenter, _), .sphere(center, _)):
            return (center - oldCenter) / deltaTime
        case let (.box(oldCenter, _, _), .box(center, _, _)), let (.signedDistanceField(_, oldCenter, _), .signedDistanceField(_, center, _)):
            return (center - oldCenter) / deltaTime
        case let (.capsule(oldStart, oldEnd, _), .capsule(start, end, _)):
            return ((start + end) - (oldStart + oldEnd)) / 2 / deltaTime
        default:
            return .zero
        }
    }

    /// Linear velocity and angular velocity (axis times radians per second) implied by moving from `previous`. Boxes
    /// and distance fields turn with their rotation and capsules with their direction, the shorter way round; other
    /// shapes do not turn.
    func motion(from previous: Collider, deltaTime: Float) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        guard deltaTime > 0 else {
            return (.zero, .zero)
        }
        var angular: SIMD3<Float> = .zero
        switch (previous.shape, shape) {
        case let (.box(_, _, oldRotation), .box(_, _, rotation)), let (.signedDistanceField(_, _, oldRotation), .signedDistanceField(_, _, rotation)):
            var delta = simd_normalize(rotation * simd_normalize(oldRotation).inverse)
            if delta.real < 0 {
                delta = simd_quatf(vector: -delta.vector)
            }
            if delta.angle > 1e-6 {
                angular = simd_normalize(delta.axis) * delta.angle / deltaTime
            }
        case let (.capsule(oldStart, oldEnd, _), .capsule(start, end, _)):
            let old = oldEnd - oldStart
            let new = end - start
            if simd_length(old) > 0, simd_length(new) > 0 {
                let from = simd_normalize(old)
                let to = simd_normalize(new)
                let axis = simd_cross(from, to)
                if simd_length(axis) > 1e-6 {
                    angular = simd_normalize(axis) * acos(min(max(simd_dot(from, to), -1), 1)) / deltaTime
                }
            }
        default:
            break
        }
        return (velocity(from: previous, deltaTime: deltaTime), angular)
    }
}

extension ColliderData {
    init(_ collider: Collider, velocity: SIMD3<Float> = .zero) {
        self.init()
        self.velocity = velocity
        rotation = [0, 0, 0, 1]
        switch collider.shape {
        case let .sphere(center, _), let .box(center, _, _), let .signedDistanceField(_, center, _):
            pivot = center
        case let .capsule(start, end, _):
            pivot = (start + end) / 2
        case .plane:
            break
        }
        switch collider.shape {
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
        case let .signedDistanceField(field, center, rotation):
            // The grid itself is a 3D texture the runtime binds separately, at fieldIndex.
            kind = .signedDistanceField
            self.center = center
            self.rotation = simd_normalize(rotation).vector
            fieldMin = field.origin
            fieldMax = field.origin + field.spacing * SIMD3<Float>(field.resolution &- 1)
            fieldSpacing = field.spacing
            fieldIndex = .max
        }
    }
}
