import Foundation
import MetalSprocketsParticles

// Colliders and force fields are plain enums in the library; the demo gives them ids for lists and selection.

struct ColliderItem: Identifiable, Equatable {
    let id = UUID()
    var collider: Collider
    /// Moves to the pointer each frame.
    var followsPointer = false
    /// Turns at a steady rate (saved as a ColliderSpin by this collider's index).
    var spin: SteadySpin?
}

/// A collider's steady turn, without the index ColliderSpin stores it by.
struct SteadySpin: Equatable {
    var axis: SIMD3<Float> = [0, 1, 0]
    /// Radians per second.
    var speed: Float = 1
}

/// "When this emitter's particles hit or die, burst that many from that emitter", by emitter id, so removing or
/// reordering emitters cannot point a burst at the wrong one (EventBurst saves layer indices).
struct EventBurstItem: Identifiable, Equatable {
    let id = UUID()
    var sourceID: UUID
    var occasion: EventBurst.Occasion
    var targetID: UUID
    var count: Int
}

/// A stand-in for an app object that objectEnters triggers watch, moving along a path.
struct TrackedObjectItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var motion: EmitterMotion
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
