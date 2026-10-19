import MetalSprocketsParticlesShaders
import simd

/// A world-space light for emitters with `ParticleEmitter.isLit`. Lit particles are shaded like small spheres:
/// color × (`ParticleSystemRuntime.ambientLight` + diffuse light from each light). At most `PARTICLE_MAX_LIGHTS` are used.
public enum ParticleLight: Sendable, Equatable, Codable {
    /// Light from far away traveling along `direction`, like the sun.
    case directional(direction: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1)
    /// Light from `position` in all directions, fading to zero at `range` (0 means no falloff).
    case point(position: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = 0)
}

/// Turns some of an emitter's live particles into point lights each frame (`ParticleEmitter.light`): sparks lighting
/// smoke, fireflies glowing on leaves. They light lit particles of every emitter, and the host can use them too
/// (`ParticleSystemRuntime.particleLightBuffer`, `emittedLights()`). At most `PARTICLE_MAX_PARTICLE_LIGHTS` across the
/// system.
public struct ParticleLightEmission: Sendable, Equatable, Codable {
    /// How many particles become lights, picked evenly across the emitter's particles.
    public var count: Int
    public var color: SIMD3<Float>
    /// Multiplies `color`; each light dims as its particle ages.
    public var intensity: Float
    /// Light fades to zero at this distance from the particle.
    public var range: Float

    public init(count: Int = 4, color: SIMD3<Float> = [1, 0.6, 0.3], intensity: Float = 1, range: Float = 2) {
        self.count = count
        self.color = color
        self.intensity = intensity
        self.range = range
    }
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
