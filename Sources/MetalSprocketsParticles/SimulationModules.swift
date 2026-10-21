import MetalSprocketsParticlesShaders
import simd

// Modules write their own part of the simulation uniforms (#226). A missing module leaves its NeutralModules value.

/// What a module needs from the frame to write its uniforms.
struct SimulationContext {
    var motion: ParticleSystemRuntime.SpawnMotion
    var mesh: EmitterMesh?
}

/// A module that sets simulation uniforms.
protocol SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext)
}

extension EmitterModules {
    /// Writes every enabled module's part of `uniforms`, over the values that apply when a module is missing.
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        NeutralModules.shape.contribute(to: &uniforms, context: context)
        NeutralModules.lifetime.contribute(to: &uniforms, context: context)
        uniforms.restitution = NeutralModules.collision.restitution
        uniforms.friction = NeutralModules.collision.friction
        uniforms.glintShininess = max(ParticleFoil().shininess, 1)
        for slot in spawn where slot.isEnabled {
            slot.module.contribute(to: &uniforms, context: context)
        }
        for slot in update where slot.isEnabled {
            slot.module.contribute(to: &uniforms, context: context)
        }
        for slot in render where slot.isEnabled {
            slot.module.contribute(to: &uniforms, context: context)
        }
    }
}

// Each stage switches over its cases rather than casting to SimulationContributor: frame planning runs this for every
// module of every emitter each frame, and dynamic protocol casts cost measurable CPU time there.

extension SpawnModule {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        switch self {
        case let .shape(module): module.contribute(to: &uniforms, context: context)
        case let .lifetime(module): module.contribute(to: &uniforms, context: context)
        case let .velocity(module): module.contribute(to: &uniforms, context: context)
        case let .rotation(module): module.contribute(to: &uniforms, context: context)
        case let .variation(module): module.contribute(to: &uniforms, context: context)
        case .rate, .colorImage, .function, .stitched: break
        }
    }
}

extension UpdateModule {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        switch self {
        case let .gravity(module): module.contribute(to: &uniforms, context: context)
        case let .drag(module): module.contribute(to: &uniforms, context: context)
        case let .flocking(module): module.contribute(to: &uniforms, context: context)
        case let .collision(module): module.contribute(to: &uniforms, context: context)
        case let .planeConstraint(module): module.contribute(to: &uniforms, context: context)
        case .events, .subEmitters, .triggers, .function, .collisionFunction, .deathFunction, .stitched: break
        }
    }
}

extension RenderModule {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        switch self {
        case let .trail(module): module.contribute(to: &uniforms, context: context)
        case let .ribbon(module): module.contribute(to: &uniforms, context: context)
        case let .colorByPosition(module): module.contribute(to: &uniforms, context: context)
        case let .imageSequence(module): module.contribute(to: &uniforms, context: context)
        case let .shading(module): module.contribute(to: &uniforms, context: context)
        case .sprite, .colorOverLife, .sizeOverLife, .colorBySpeed, .mesh, .light, .levelOfDetail: break
        }
    }
}

extension SimulationUniforms {
    /// Keeps particles on the plane through the emitter's origin, facing its local Z axis.
    mutating func constrainToPlane(_ motion: ParticleSystemRuntime.SpawnMotion) {
        constrainsToPlane = 1
        planePoint = motion.transform.columns.3.xyz
        let normal = motion.transform.columns.2.xyz
        planeNormal = simd_length(normal) > 0 ? simd_normalize(normal) : [0, 0, 1]
    }
}

// MARK: - Spawn

extension ShapeModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        uniforms.shape = ParticleShapeData(shape: shape, position: position, birthLocation: birthLocation, birthDirection: birthDirection, sweep: sweepAngle, mesh: context.mesh)
    }
}

extension LifetimeModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.lifetimeMinimum = range.lowerBound
        uniforms.lifetimeMaximum = range.upperBound
    }
}

extension VelocityModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.velocity = velocity
        uniforms.velocitySpread = spread
        uniforms.variation.speed = max(speedVariation, 0)
    }
}

extension RotationModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.angle = angle
        uniforms.angularSpeed = angularSpeed
        uniforms.variation.angle = angleVariation
        uniforms.variation.angularSpeed = angularSpeedVariation
    }
}

extension VariationModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.variation.size = max(size, 0)
        uniforms.variation.color = simd_max(color, .zero)
    }
}

// MARK: - Update

extension GravityModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.gravity = acceleration
    }
}

extension DragModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.drag = amount
    }
}

extension FlockingModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.flocks = 1
        uniforms.flockSpeedRange = [flocking.speedRange.lowerBound, flocking.speedRange.upperBound]
    }
}

extension CollisionModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.restitution = restitution
        uniforms.friction = friction
        uniforms.diesOnCollision = diesOnCollision ? 1 : 0
        uniforms.collisionRadius = max(radius, 0)
        uniforms.variation.restitution = max(restitutionVariation, 0)
        uniforms.variation.friction = max(frictionVariation, 0)
    }
}

extension PlaneConstraintModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context: SimulationContext) {
        uniforms.constrainToPlane(context.motion)
    }
}

// MARK: - Render

extension TrailModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.trailPointCount = UInt32(trail.clampedPointCount)
        uniforms.trailPointInterval = max(trail.pointInterval, 0)
    }
}

extension RibbonModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.ordersBirths = 1
    }
}

extension ColorByPositionModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        if atBirth, curve != nil {
            uniforms.colorsByBirthPosition = 1
            uniforms.birthColorStart = start
            uniforms.birthColorEnd = end
        }
    }
}

extension ImageSequenceModule: SimulationContributor {
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        uniforms.initialFrame = sequence.initialFrame
        uniforms.frameRate = sequence.frameRate
        uniforms.variation.initialFrame = sequence.initialFrameVariation
        uniforms.variation.frameRate = sequence.frameRateVariation
    }
}

extension ShadingModule: SimulationContributor {
    // Glint sub-emitters see what foil shading sees.
    func contribute(to uniforms: inout SimulationUniforms, context _: SimulationContext) {
        if case let .foil(settings) = model {
            uniforms.glintShininess = max(settings.shininess, 1)
        }
    }
}
