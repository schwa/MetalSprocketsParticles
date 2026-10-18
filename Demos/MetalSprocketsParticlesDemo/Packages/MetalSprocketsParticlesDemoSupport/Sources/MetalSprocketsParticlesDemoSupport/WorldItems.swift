import Foundation
import MetalSprocketsParticles

// Colliders and force fields are plain enums in the library; the demo gives them ids for lists and selection.

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider
    /// Moves to the pointer each frame.
    var followsPointer = false
}

struct ForceFieldItem: Identifiable, Equatable {
    let id = UUID()
    var field: ForceField
    /// Centers on the pointer each frame (attractors and vortices).
    var followsPointer = false
}
