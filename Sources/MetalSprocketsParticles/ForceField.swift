import MetalSprocketsParticlesShaders
import simd

/// A force applied to particles each step, in addition to gravity and drag. Only emitters whose
/// `ParticleEmitter.fieldMask` shares a bit with `categoryBitMask` feel it.
public struct ForceField: Sendable, Equatable {
    public enum Effect: Sendable, Equatable, Codable {
        /// Pulls particle velocity toward `velocity`. `strength` is per second: higher catches up faster.
        case wind(velocity: SIMD3<Float>, strength: Float)
        /// Constant acceleration toward `center`; negative `strength` repels. `radius` 0 means unlimited range.
        case attractor(center: SIMD3<Float>, strength: Float, radius: Float = 0)
        /// Swirls particles around the line through `center` along `axis`. Positive `strength` turns counterclockwise
        /// looking down `axis`. `radius` 0 means unlimited range.
        case vortex(center: SIMD3<Float>, axis: SIMD3<Float> = [0, 1, 0], strength: Float, radius: Float = 0)
        /// Curl-noise turbulence. `scale` is noise frequency per world unit; `speed` animates the pattern over time.
        case turbulence(strength: Float, scale: Float = 1, speed: Float = 0)
    }

    public var effect: Effect
    /// All bits by default, so every emitter feels it.
    public var categoryBitMask: UInt32

    public init(_ effect: Effect, categoryBitMask: UInt32 = .max) {
        self.effect = effect
        self.categoryBitMask = categoryBitMask
    }

    public static func wind(velocity: SIMD3<Float>, strength: Float, categoryBitMask: UInt32 = .max) -> ForceField {
        ForceField(.wind(velocity: velocity, strength: strength), categoryBitMask: categoryBitMask)
    }

    public static func attractor(center: SIMD3<Float>, strength: Float, radius: Float = 0, categoryBitMask: UInt32 = .max) -> ForceField {
        ForceField(.attractor(center: center, strength: strength, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func vortex(
        center: SIMD3<Float>,
        axis: SIMD3<Float> = [0, 1, 0],
        strength: Float,
        radius: Float = 0,
        categoryBitMask: UInt32 = .max
    ) -> ForceField {
        ForceField(.vortex(center: center, axis: axis, strength: strength, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func turbulence(strength: Float, scale: Float = 1, speed: Float = 0, categoryBitMask: UInt32 = .max) -> ForceField {
        ForceField(.turbulence(strength: strength, scale: scale, speed: speed), categoryBitMask: categoryBitMask)
    }
}

extension ForceField: Codable {
    private enum CodingKeys: String, CodingKey {
        case effect, categoryBitMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Files saved before categories stored the effect itself, without the wrapper.
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect) ?? Effect(from: decoder)
        categoryBitMask = try container.decodeIfPresent(UInt32.self, forKey: .categoryBitMask) ?? .max
    }
}

extension ForceFieldData {
    init(_ field: ForceField) {
        self.init()
        switch field.effect {
        case let .wind(velocity, strength):
            kind = .wind
            self.velocity = velocity
            self.strength = strength
        case let .attractor(center, strength, radius):
            kind = .attractor
            self.center = center
            self.strength = strength
            self.radius = radius
        case let .vortex(center, axis, strength, radius):
            kind = .vortex
            self.center = center
            self.axis = simd_length(axis) > 0 ? simd_normalize(axis) : [0, 1, 0]
            self.strength = strength
            self.radius = radius
        case let .turbulence(strength, scale, speed):
            kind = .turbulence
            self.strength = strength
            self.scale = scale
            self.speed = speed
        }
    }
}
