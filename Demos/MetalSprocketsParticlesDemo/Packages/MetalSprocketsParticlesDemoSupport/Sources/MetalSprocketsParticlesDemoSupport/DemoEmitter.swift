import Foundation
import MetalSprocketsParticles
import simd
import SwiftMesh

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
    /// Triangles for the mesh shape. Not editable in the demo; comes from presets.
    var mesh: Mesh?
}

extension DemoEmitter {
    init(_ layer: ParticlePreset.Layer) {
        self.init(name: layer.name, settings: layer.settings, sprite: layer.sprite, motion: layer.motion, simulationSpace: layer.simulationSpace, mesh: layer.mesh)
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
