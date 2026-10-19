import CoreGraphics
import simd

/// How a `ParticlePlayer` (and `ParticleView`) looks at a particle system. Hosts with their own camera, such as a scene
/// graph, pass their own matrices to `ParticlePlayer.frame(deltaTime:projection:view:sceneDepth:wireframes:)` instead.
public enum ParticleCamera: Sendable, Equatable {
    /// The system's `cameraEye` and `cameraTarget`, with a perspective projection; a flat front view for 2D systems.
    case system
    /// A perspective camera at `eye`, looking at `target`; a flat front view for 2D systems.
    case lookAt(eye: SIMD3<Float>, target: SIMD3<Float>)
    /// 2D, for effects over an app's UI: one world unit is one point, the origin is the view's top left, and y points
    /// down, as in SwiftUI. Particles live near the z = 0 plane; gravity down the screen is +y.
    case overlay

    /// How far the overlay camera sits from the z = 0 plane, and how deep its view is.
    static let overlayDepth: Float = 1_000

    /// Projection, camera-to-world transform, and the point the camera looks at (a good plane for the pointer), for a
    /// view of `size`. Perspective cameras only use its aspect; the overlay maps one unit to one point of it.
    public func matrices(for system: ParticleSystem, size: CGSize) -> (projection: simd_float4x4, cameraToWorld: simd_float4x4, focus: SIMD3<Float>) {
        switch self {
        case .system:
            return Self.lookAt(eye: system.cameraEye, target: system.cameraTarget).matrices(for: system, size: size)
        case let .lookAt(eye, target):
            if system.is2D {
                return Self.flat(eye: eye, target: target, size: size)
            }
            return Self.perspective(eye: eye, target: target, size: size)
        case .overlay:
            let width = Float(max(size.width, 1))
            let height = Float(max(size.height, 1))
            let depth = Self.overlayDepth
            // Behind the plane at z = -depth, looking along +z with up along -y: a rotation, not a mirror, so
            // camera-facing sprites stay upright while world y grows down the screen.
            let cameraToWorld = simd_float4x4(lookingFrom: [0, 0, -depth], at: .zero, up: [0, -1, 0])
            // In camera space x runs 0...width and y runs -height...0; map both to clip space, and depths from 1 to
            // 2 × depth onto 0...1.
            let near: Float = 1
            let far = depth * 2
            let projection = simd_float4x4(columns: (
                [2 / width, 0, 0, 0],
                [0, 2 / height, 0, 0],
                [0, 0, -1 / (far - near), 0],
                [-1, 1, -near / (far - near), 1]
            ))
            return (projection, cameraToWorld, .zero)
        }
    }

    /// 2D for a scene in its own units: orthographic, looking along -z at `target` with y up, showing at the target
    /// what the perspective camera from `eye` shows there.
    private static func flat(eye: SIMD3<Float>, target: SIMD3<Float>, size: CGSize) -> (projection: simd_float4x4, cameraToWorld: simd_float4x4, focus: SIMD3<Float>) {
        let aspect = Float(size.width / max(size.height, 1))
        let distance = max(simd_distance(eye, target), 0.001)
        let halfHeight = distance * tan(fieldOfView / 2)
        let halfWidth = halfHeight * aspect
        let near: Float = 0.01
        let far = max(distance * 2, distance + 100)
        let cameraToWorld = simd_float4x4(lookingFrom: target + [0, 0, distance], at: target, up: [0, 1, 0])
        let projection = simd_float4x4(columns: (
            [1 / halfWidth, 0, 0, 0],
            [0, 1 / halfHeight, 0, 0],
            [0, 0, -1 / (far - near), 0],
            [0, 0, -near / (far - near), 1]
        ))
        return (projection, cameraToWorld, target)
    }

    static let fieldOfView: Float = .pi / 4

    private static func perspective(eye: SIMD3<Float>, target: SIMD3<Float>, size: CGSize) -> (projection: simd_float4x4, cameraToWorld: simd_float4x4, focus: SIMD3<Float>) {
        let aspect = Float(size.width / max(size.height, 1))
        let projection = simd_float4x4.perspective(fovY: fieldOfView, aspect: aspect, near: 0.1, far: 100)
        return (projection, simd_float4x4(lookingFrom: eye, at: target), target)
    }
}
