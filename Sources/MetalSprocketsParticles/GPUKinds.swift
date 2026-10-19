import MetalSprocketsParticlesShaders

// The C kind each Swift enum case maps to, for the GPU. Editors have their own writable kinds in the demo.

extension EmitterShape {
    var gpuKind: ParticleEmitterShapeKind {
        switch self {
        case .point: .point
        case .sphere: .sphere
        case .box: .box
        case .plane: .plane
        case .disc: .disc
        case .cylinder: .cylinder
        case .cone: .cone
        case .torus: .torus
        case .mesh: .mesh
        case .points: .points
        }
    }
}

extension SubEmitter.Occasion {
    var gpuKind: ParticleSpawnOccasion {
        switch self {
        case .onBirth: .birth
        case .onDeath: .death
        case .onCollision: .collision
        case .whileAlive: .whileAlive
        case .atAge: .age
        case .onEntering: .enterVolume
        }
    }
}
