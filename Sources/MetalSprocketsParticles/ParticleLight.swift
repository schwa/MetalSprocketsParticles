import MetalSprocketsParticlesShaders
import simd

/// A world-space light for emitters with `ParticleEmitter.isLit`. Lit particles are shaded like small spheres:
/// color × (`ParticleSystem.ambientLight` + diffuse light from each light). At most `PARTICLE_MAX_LIGHTS` are used.
public enum ParticleLight: Sendable, Equatable, Codable {
    /// Light from far away traveling along `direction`, like the sun.
    case directional(direction: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1)
    /// Light from `position` in all directions, fading to zero at `range` (0 means no falloff).
    case point(position: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = 0)
}

extension ParticleLightData {
    init(_ light: ParticleLight) {
        self.init()
        switch light {
        case let .directional(direction, color, intensity):
            kind = .directional
            self.direction = simd_length(direction) > 0 ? simd_normalize(direction) : [0, -1, 0]
            self.color = color * intensity
        case let .point(position, color, intensity, range):
            kind = .point
            self.position = position
            self.color = color * intensity
            self.range = max(range, 0)
        }
    }
}
