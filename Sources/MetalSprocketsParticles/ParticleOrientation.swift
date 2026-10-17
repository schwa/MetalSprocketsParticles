import MetalSprocketsParticlesShaders
import simd

/// How each particle's quad is oriented in the world.
public enum ParticleOrientation: Sendable, Equatable {
    /// Always faces the camera.
    case billboard
    /// Stands upright and turns around world Y to face the camera. Good for trees, flames, and smoke columns.
    case yAligned
    /// Long axis along the particle's velocity, turned toward the camera. The long axis is stretched by
    /// `1 + stretch × speed`, so fast particles become streaks. Good for sparks and rain.
    case velocityAligned(stretch: Float = 0)
    /// Lies flat in the plane with this normal. Good for ripples, decals, and leaves on water.
    case fixed(normal: SIMD3<Float>)

    var mode: ParticleOrientationMode {
        switch self {
        case .billboard: .billboard
        case .yAligned: .yAligned
        case .velocityAligned: .velocityAligned
        case .fixed: .fixed
        }
    }

    /// xyz = fixed plane normal, w = stretch factor.
    var parameters: SIMD4<Float> {
        switch self {
        case let .velocityAligned(stretch): [0, 0, 0, max(stretch, 0)]
        case let .fixed(normal): SIMD4(simd_length(normal) > 0 ? simd_normalize(normal) : [0, 1, 0], 0)
        default: [0, 1, 0, 0]
        }
    }
}
