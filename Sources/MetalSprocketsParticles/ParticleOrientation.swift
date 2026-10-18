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

    /// The plane normal for `fixed`, unit length; +Y otherwise.
    var fixedNormal: SIMD3<Float> {
        if case let .fixed(normal) = self, simd_length(normal) > 0 {
            return simd_normalize(normal)
        }
        return [0, 1, 0]
    }

    var velocityStretch: Float {
        if case let .velocityAligned(stretch) = self {
            return max(stretch, 0)
        }
        return 0
    }
}
