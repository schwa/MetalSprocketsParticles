import Foundation

public enum ParticleSystemRuntimeError: Error, LocalizedError, Sendable {
    /// The emitters and their sub-emitters (whose capacity multiplies with each nesting level) need more particles than
    /// one GPU buffer can hold.
    case tooManyParticles

    public var errorDescription: String? {
        switch self {
        case .tooManyParticles:
            "The particle system needs more particles than one GPU buffer can hold. Lower emitter capacities or sub-emitter counts per event."
        }
    }
}
