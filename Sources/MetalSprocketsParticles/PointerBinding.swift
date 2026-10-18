import CoreGraphics
import simd

/// Something in a preset that follows the pointer (the mouse in an app, a scripted path elsewhere).
public enum PointerBinding: Sendable, Hashable, Codable {
    /// The collider at this index in `ParticlePreset.colliders` moves so its center is at the pointer.
    case collider(Int)
    /// The force field at this index in `ParticlePreset.forceFields` moves its center (attractors and vortices) to the
    /// pointer. Wind and turbulence have no position and are unchanged.
    case forceField(Int)
    /// The emitter for the layer at this index moves to the pointer, keeping its motion's rotation.
    case emitter(Int)
}

public extension ParticlePreset {
    /// Where the pointer is at `time` when there is no live input (renders, videos, tests): `pointerMotion`'s path.
    func pointerPosition(at time: Float) -> SIMD3<Float> {
        pointerMotion.transform(time: time).columns.3.xyz
    }

    /// `colliders(at:)` with pointer-bound colliders moved to `pointer` (by default `pointerPosition(at:)`).
    func colliders(at time: Float, pointer: SIMD3<Float>?) -> [Collider] {
        colliders(at: time).following(pointer ?? pointerPosition(at: time), bindings: pointerBindings)
    }

    /// The force fields with pointer-bound ones moved to `pointer` (by default `pointerPosition(at:)`).
    func forceFields(at time: Float, pointer: SIMD3<Float>? = nil) -> [ForceField] {
        forceFields.following(pointer ?? pointerPosition(at: time), bindings: pointerBindings)
    }

    /// `transforms(at:)` with pointer-bound emitters moved to `pointer` (by default `pointerPosition(at:)`).
    func transforms(at time: Float, pointer: SIMD3<Float>?) -> [simd_float4x4] {
        transforms(at: time).following(pointer ?? pointerPosition(at: time), bindings: pointerBindings)
    }
}

public extension [Collider] {
    func following(_ pointer: SIMD3<Float>, bindings: [PointerBinding]) -> Self {
        var colliders = self
        for case let .collider(index) in bindings where colliders.indices.contains(index) {
            colliders[index] = colliders[index].centered(at: pointer)
        }
        return colliders
    }
}

public extension [ForceField] {
    func following(_ pointer: SIMD3<Float>, bindings: [PointerBinding]) -> Self {
        var fields = self
        for case let .forceField(index) in bindings where fields.indices.contains(index) {
            switch fields[index].effect {
            case let .attractor(_, strength, radius):
                fields[index].effect = .attractor(center: pointer, strength: strength, radius: radius)
            case let .vortex(_, axis, strength, radius):
                fields[index].effect = .vortex(center: pointer, axis: axis, strength: strength, radius: radius)
            case .wind, .turbulence:
                break
            }
        }
        return fields
    }
}

public extension [simd_float4x4] {
    func following(_ pointer: SIMD3<Float>, bindings: [PointerBinding]) -> Self {
        var transforms = self
        for case let .emitter(index) in bindings where transforms.indices.contains(index) {
            transforms[index].columns.3 = SIMD4(pointer, 1)
        }
        return transforms
    }
}

extension Collider {
    /// The collider moved so its center (a box's or sphere's center, a capsule's midpoint) is at `point`. Planes pass
    /// through `point`.
    func centered(at point: SIMD3<Float>) -> Collider {
        switch shape {
        case let .plane(normal, _):
            return Collider(.plane(normal: normal, distance: simd_dot(simd_normalize(normal), point)), categoryBitMask: categoryBitMask)
        case let .sphere(center, _), let .box(center, _, _):
            return translated(by: point - center)
        case let .capsule(start, end, _):
            return translated(by: point - (start + end) / 2)
        }
    }
}

/// Turns a point in a view into a world position, for driving pointer bindings with a mouse.
public enum PointerProjection {
    /// Where the ray through `location` (in a view of `size`, origin top left) meets the plane through `planePoint`
    /// that faces the camera. `nil` if the ray misses it.
    public static func worldPosition(
        of location: CGPoint,
        in size: CGSize,
        projection: simd_float4x4,
        cameraToWorld: simd_float4x4,
        planePoint: SIMD3<Float>
    ) -> SIMD3<Float>? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let ndc = SIMD2<Float>(Float(location.x / size.width) * 2 - 1, 1 - Float(location.y / size.height) * 2)
        let inverseProjection = projection.inverse
        let near = inverseProjection * SIMD4<Float>(ndc.x, ndc.y, 0, 1)
        let far = inverseProjection * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        let origin = (cameraToWorld * SIMD4(near.xyz / near.w, 1)).xyz
        let target = (cameraToWorld * SIMD4(far.xyz / far.w, 1)).xyz
        let direction = simd_normalize(target - origin)
        // The plane faces the camera: its normal is the camera's view direction.
        let normal = -cameraToWorld.columns.2.xyz
        let denominator = simd_dot(direction, normal)
        guard abs(denominator) > 1e-6 else {
            return nil
        }
        let distance = simd_dot(planePoint - origin, normal) / denominator
        return distance > 0 ? origin + direction * distance : nil
    }
}
