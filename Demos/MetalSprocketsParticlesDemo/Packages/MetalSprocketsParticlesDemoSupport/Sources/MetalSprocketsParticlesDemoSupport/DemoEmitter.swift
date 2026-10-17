import Foundation
import MetalSprocketsParticles
import simd

/// One emitter as the demo edits it: library settings plus the runtime choices that live on
/// `ParticleSystem.Emitter` (sprite, motion, simulation space, emitting).
struct DemoEmitter: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var settings: ParticleEmitter
    var sprite: ParticleSprite = .softDot
    var motion = EmitterMotion()
    var simulationSpace: SimulationSpace = .world
    var isEmitting = true
}

extension DemoEmitter {
    init(_ layer: ParticlePreset.Layer) {
        self.init(name: layer.name, settings: layer.settings, sprite: layer.sprite, motion: layer.motion, simulationSpace: layer.simulationSpace)
    }
}

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider
}

struct ForceFieldItem: Identifiable, Equatable {
    let id = UUID()
    var field: ForceField
}
