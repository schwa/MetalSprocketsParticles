import Foundation

public enum ParticleSystemRuntimeError: Error, LocalizedError, Sendable {
    /// The emitters and their sub-emitters (whose capacity multiplies with each nesting level) need more particles than
    /// one GPU buffer can hold.
    case tooManyParticles
    /// The GPU could not make a 3D texture this large for a signed distance field collider.
    case signedDistanceFieldTooLarge(resolution: SIMD3<Int>)

    public var errorDescription: String? {
        switch self {
        case .tooManyParticles:
            "The particle system needs more particles than one GPU buffer can hold. Lower emitter capacities or sub-emitter counts per event."
        case let .signedDistanceFieldTooLarge(resolution):
            "The GPU cannot make a \(resolution.x)×\(resolution.y)×\(resolution.z) texture for a distance field collider. Bake it at a lower resolution."
        }
    }
}
