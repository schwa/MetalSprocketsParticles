/// Where particles live after they are born.
public enum SimulationSpace: Sendable, Equatable {
    /// Particles are born through `ParticleSystem.transform` and then stay put in the world, so a moving emitter
    /// leaves a trail. Gravity, colliders, and force fields are in world space.
    case world
    /// Particles live in the emitter's space and move with `ParticleSystem.transform`. Gravity, colliders, and force
    /// fields are in emitter space too.
    case local
}
