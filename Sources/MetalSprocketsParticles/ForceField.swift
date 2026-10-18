import MetalSprocketsParticlesShaders
import simd

/// A force applied to every particle each step, in addition to gravity and drag.
public enum ForceField: Sendable, Equatable {
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

extension ForceFieldData {
    init(_ field: ForceField) {
        self.init()
        switch field {
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
