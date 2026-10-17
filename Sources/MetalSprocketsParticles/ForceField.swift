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
        switch field {
        case let .wind(velocity, strength):
            self.init(kind: [1, 0, 0, 0], a: SIMD4(velocity, strength), b: .zero)
        case let .attractor(center, strength, radius):
            self.init(kind: [2, 0, 0, 0], a: SIMD4(center, strength), b: [radius, 0, 0, 0])
        case let .vortex(center, axis, strength, radius):
            let axis = simd_length(axis) > 0 ? simd_normalize(axis) : SIMD3<Float>(0, 1, 0)
            self.init(kind: [3, 0, 0, 0], a: SIMD4(center, strength), b: SIMD4(axis, radius))
        case let .turbulence(strength, scale, speed):
            self.init(kind: [4, 0, 0, 0], a: [strength, scale, speed, 0], b: .zero)
        }
    }
}
