import Foundation
import MetalSprocketsParticles
import simd

/// One emitter as the demo edits it: library settings plus the runtime choices that live on
/// `ParticleSystem.Emitter` (texture, motion, simulation space, emitting).
struct DemoEmitter: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var settings: ParticleEmitter
    var texture: DemoTexture = .softDot
    var motion = EmitterMotion()
    var simulationSpace: SimulationSpace = .world
    var isEmitting = true
}

/// Moves an emitter over time so trails, local space, and inherited velocity can be seen.
struct EmitterMotion: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case still = "Still"
        case circle = "Circle"
        case bounce = "Bounce"

        var id: Self { self }
    }

    var kind = Kind.still
    var radius: Float = 1.5
    var speed: Float = 1

    func transform(time: Float) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        let angle = time * speed
        switch kind {
        case .still:
            break
        case .circle:
            transform.columns.3 = [cos(angle) * radius, 0, sin(angle) * radius, 1]
        case .bounce:
            transform.columns.3 = [0, abs(sin(angle)) * radius, 0, 1]
        }
        return transform
    }
}

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider

    /// The collider moved over time: spheres bob, boxes slide in x, capsules slide in z, planes stay put. `index`
    /// staggers the phase so colliders do not move in lockstep.
    func animated(time: Float, index: Int) -> Collider {
        let phase = time + Float(index) * 1.7
        switch collider {
        case .plane:
            return collider
        case .sphere:
            return collider.translated(by: [0, 0.6 * sin(phase * 1.3), 0])
        case .box:
            return collider.translated(by: [0.5 * sin(phase * 0.9), 0, 0])
        case .capsule:
            return collider.translated(by: [0, 0, 0.6 * sin(phase * 0.7)])
        }
    }
}

struct ForceFieldItem: Identifiable, Equatable {
    let id = UUID()
    var field: ForceField
}

extension Collider {
    func translated(by offset: SIMD3<Float>) -> Collider {
        var collider = self
        collider.center += offset
        return collider
    }
}
