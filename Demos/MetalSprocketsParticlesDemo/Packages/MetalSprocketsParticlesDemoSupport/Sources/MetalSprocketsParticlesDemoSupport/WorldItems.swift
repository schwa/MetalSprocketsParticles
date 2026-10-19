import Foundation
import MetalSprocketsParticles

// Colliders and force fields are plain enums in the library; the demo gives them ids for lists and selection.

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider
    /// Moves to the pointer each frame.
    var followsPointer = false
}

/// A scene light with an identity, so the list can add and remove lights without index-based identity.
struct LightItem: Identifiable, Equatable {
    let id = UUID()
    var light: ParticleLight
}

struct ForceFieldItem: Identifiable, Equatable {
    let id = UUID()
    var field: ForceField
    /// Centers on the pointer each frame (attractors and vortices).
    var followsPointer = false
}
