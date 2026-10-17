import MetalSprocketsParticles
import Observation

/// Demo state edited by the inspector. Each change is pushed to the particle system.
@Observable
@MainActor
final class ParticlesDemoModel {
    @ObservationIgnored let system: ParticleSystem?

    var emitter: ParticleEmitter = .fountain {
        didSet { system?.emitter = emitter }
    }

    var forceFields: [ForceField] = [] {
        didSet { system?.forceFields = forceFields }
    }

    var playback: SimulationState = .playing {
        didSet { system?.state = playback }
    }

    var speedFactor: Float = 1 {
        didSet { system?.speedFactor = speedFactor }
    }

    var isEmitting = true {
        didSet { system?.isEmitting = isEmitting }
    }

    /// Moves the fountain's colliders over time. When off, colliders stay at their rest positions.
    var animateColliders = true {
        didSet {
            if !animateColliders {
                system?.colliders = ParticleEmitter.fountainColliders(time: 0)
            }
        }
    }

    var showColliders = true

    init(capacity: Int = 200_000) {
        system = try? ParticleSystem(capacity: capacity, emitter: .fountain)
        system?.colliders = ParticleEmitter.fountainColliders(time: 0)
    }

    func restart() {
        system?.restart()
        playback = .playing
    }

    func burst(_ count: Int = 2_000) {
        system?.burst(count)
    }

    func resetEmitter() {
        emitter = .fountain
        forceFields = []
    }
}
