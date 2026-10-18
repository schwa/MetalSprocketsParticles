import Foundation
import MetalSprocketsParticles

// Colliders and force fields are plain enums in the library; the demo gives them ids for lists and selection.

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider
}

struct ForceFieldItem: Identifiable, Equatable {
    let id = UUID()
    var field: ForceField
}
