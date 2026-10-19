import MetalSprocketsParticlesShaders

/// Debug views that draw particles in false colors or as wireframes instead of their own colors
/// (`ParticleSystemRuntime.debugView`).
public enum ParticleDebugView: String, Sendable, CaseIterable {
    case none
    /// Each sprite quad, mesh, or ribbon as lines: size, orientation, stretch, and overlap.
    case wireframe
    /// A distinct color per emitter, sub-emitters included.
    case emitter
    /// Age as a fraction of lifetime, blue (born) to red (dying).
    case age
    /// Speed through `ParticleSystemRuntime.debugRange`, blue (slow) to red (fast).
    case speed
    /// Seconds of life left up to `debugRange.upperBound`, blue (plenty) to red (about to die).
    case lifeRemaining
    /// Position in the emitter's ring of particle slots: shows spawn order and the live window.
    case slot
    /// Dim additive color: bright areas are where many particles overlap (fill cost).
    case overdraw

    public var name: String {
        switch self {
        case .none: "None"
        case .wireframe: "Wireframe"
        case .emitter: "Emitter"
        case .age: "Age"
        case .speed: "Speed"
        case .lifeRemaining: "Life Remaining"
        case .slot: "Slot"
        case .overdraw: "Overdraw"
        }
    }

    var gpuMode: ParticleDebugMode {
        switch self {
        case .none: .none
        case .wireframe: .wireframe
        case .emitter: .emitter
        case .age: .age
        case .speed: .speed
        case .lifeRemaining: .lifeRemaining
        case .slot: .slot
        case .overdraw: .overdraw
        }
    }

    /// The blend mode draws use in this view; nil keeps the emitter's.
    var blendMode: ParticleBlendMode? {
        switch self {
        case .none: nil
        case .wireframe: .opaque
        case .overdraw: .additive
        default: .alpha
        }
    }
}
