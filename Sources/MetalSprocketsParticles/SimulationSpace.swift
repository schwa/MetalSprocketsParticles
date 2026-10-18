/// Where an emitter's particles live after they are born. Gravity, colliders, and force fields are always in world
/// space; local particles are converted to world space for that part of each step.
public enum SimulationSpace: Sendable, Hashable, CaseIterable, Codable {
    /// Particles are born through the emitter's transform and then stay put in the world, so a moving emitter leaves a
    /// trail.
    case world
    /// Particles live in the emitter's space and move with its transform.
    case local
}
