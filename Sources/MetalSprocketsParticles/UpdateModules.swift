import simd

public enum UpdateModule: StageModule {
    case gravity(GravityModule)
    case drag(DragModule)
    case flocking(FlockingModule)
    case collision(CollisionModule)
    case planeConstraint(PlaneConstraintModule)
    case events(EventsModule)
    case subEmitters(SubEmittersModule)
    case triggers(TriggersModule)
    case function(UpdateFunctionModule)
    case collisionFunction(CollisionFunctionModule)
    case deathFunction(DeathFunctionModule)
    case stitched(StitchedUpdateModule)

    public static let types: [any ParticleModule.Type] = [
        GravityModule.self, DragModule.self, FlockingModule.self, CollisionModule.self, PlaneConstraintModule.self, EventsModule.self, SubEmittersModule.self, TriggersModule.self, UpdateFunctionModule.self,
        CollisionFunctionModule.self, DeathFunctionModule.self, StitchedUpdateModule.self,
    ]

    public init?(wrapping module: any ParticleModule) {
        switch module {
        case let module as GravityModule: self = .gravity(module)
        case let module as DragModule: self = .drag(module)
        case let module as FlockingModule: self = .flocking(module)
        case let module as CollisionModule: self = .collision(module)
        case let module as PlaneConstraintModule: self = .planeConstraint(module)
        case let module as EventsModule: self = .events(module)
        case let module as SubEmittersModule: self = .subEmitters(module)
        case let module as TriggersModule: self = .triggers(module)
        case let module as UpdateFunctionModule: self = .function(module)
        case let module as CollisionFunctionModule: self = .collisionFunction(module)
        case let module as DeathFunctionModule: self = .deathFunction(module)
        case let module as StitchedUpdateModule: self = .stitched(module)
        default: return nil
        }
    }

    public var module: any ParticleModule {
        switch self {
        case let .gravity(module): module
        case let .drag(module): module
        case let .flocking(module): module
        case let .collision(module): module
        case let .planeConstraint(module): module
        case let .events(module): module
        case let .subEmitters(module): module
        case let .triggers(module): module
        case let .function(module): module
        case let .collisionFunction(module): module
        case let .deathFunction(module): module
        case let .stitched(module): module
        }
    }
}

public struct GravityModule: LoweredModule {
    public static let kind = "gravity"
    public static let added: Self? = Self(acceleration: [0, -9.8, 0])
    public var acceleration: SIMD3<Float>

    public init(acceleration: SIMD3<Float>) {
        self.acceleration = acceleration
    }

    init?(lifting emitter: ParticleEmitter) {
        guard emitter.gravity != .zero else {
            return nil
        }
        acceleration = emitter.gravity
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.gravity = acceleration
    }
}

public struct DragModule: LoweredModule {
    public static let kind = "drag"
    public static let added: Self? = Self(amount: 0.5)
    public var amount: Float

    public init(amount: Float) {
        self.amount = amount
    }

    init?(lifting emitter: ParticleEmitter) {
        guard emitter.drag != 0 else {
            return nil
        }
        amount = emitter.drag
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.drag = amount
    }
}

public struct FlockingModule: LoweredModule {
    public static let kind = "flocking"
    public static let added: Self? = Self(flocking: ParticleFlocking())
    public var flocking: ParticleFlocking

    public init(flocking: ParticleFlocking) {
        self.flocking = flocking
    }

    init?(lifting emitter: ParticleEmitter) {
        guard let flocking = emitter.flocking else {
            return nil
        }
        self.flocking = flocking
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.flocking = flocking
    }
}

/// How particles bounce off colliders.
public struct CollisionModule: LoweredModule {
    public static let kind = "collision"
    public static let isRequired = true
    public var restitution: Float
    public var restitutionVariation: Float
    public var friction: Float
    public var frictionVariation: Float
    public var diesOnCollision: Bool
    public var radius: Float
    public var collidesWithSceneDepth: Bool

    public init(restitution: Float = 0.4, restitutionVariation: Float = 0, friction: Float = 0.2, frictionVariation: Float = 0, diesOnCollision: Bool = false, radius: Float = 0, collidesWithSceneDepth: Bool = false) {
        self.restitution = restitution
        self.restitutionVariation = restitutionVariation
        self.friction = friction
        self.frictionVariation = frictionVariation
        self.diesOnCollision = diesOnCollision
        self.radius = radius
        self.collidesWithSceneDepth = collidesWithSceneDepth
    }

    init?(lifting emitter: ParticleEmitter) {
        self.init(restitution: emitter.restitution, restitutionVariation: emitter.restitutionVariation, friction: emitter.friction, frictionVariation: emitter.frictionVariation, diesOnCollision: emitter.diesOnCollision, radius: emitter.collisionRadius, collidesWithSceneDepth: emitter.collidesWithSceneDepth)
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.restitution = restitution
        emitter.restitutionVariation = restitutionVariation
        emitter.friction = friction
        emitter.frictionVariation = frictionVariation
        emitter.diesOnCollision = diesOnCollision
        emitter.collisionRadius = radius
        emitter.collidesWithSceneDepth = collidesWithSceneDepth
    }
}

/// Keeps particles on the emitter's XY plane.
public struct PlaneConstraintModule: LoweredModule {
    public static let kind = "planeConstraint"
    public static let added: Self? = Self()

    public init() {}

    init?(lifting emitter: ParticleEmitter) {
        guard emitter.constrainsToPlane else {
            return nil
        }
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.constrainsToPlane = true
    }
}

/// Reports collisions and deaths to the app.
public struct EventsModule: LoweredModule {
    public static let kind = "events"
    public static let added: Self? = Self(reportsCollisions: true, reportsDeaths: true)
    public var reportsCollisions: Bool
    public var reportsDeaths: Bool

    public init(reportsCollisions: Bool, reportsDeaths: Bool) {
        self.reportsCollisions = reportsCollisions
        self.reportsDeaths = reportsDeaths
    }

    init?(lifting emitter: ParticleEmitter) {
        guard emitter.reportsCollisions || emitter.reportsDeaths else {
            return nil
        }
        self.init(reportsCollisions: emitter.reportsCollisions, reportsDeaths: emitter.reportsDeaths)
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.reportsCollisions = reportsCollisions
        emitter.reportsDeaths = reportsDeaths
    }
}

public struct SubEmittersModule: LoweredModule {
    public static let kind = "subEmitters"
    public var emitters: [SubEmitter]

    public init(emitters: [SubEmitter]) {
        self.emitters = emitters
    }

    init?(lifting emitter: ParticleEmitter) {
        guard !emitter.subEmitters.isEmpty else {
            return nil
        }
        emitters = emitter.subEmitters
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.subEmitters += emitters
    }
}

public struct TriggersModule: LoweredModule {
    public static let kind = "triggers"
    public var triggers: [EmissionTrigger]

    public init(triggers: [EmissionTrigger]) {
        self.triggers = triggers
    }

    init?(lifting emitter: ParticleEmitter) {
        guard !emitter.triggers.isEmpty else {
            return nil
        }
        triggers = emitter.triggers
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.triggers += triggers
    }
}

/// A user `[[visible]]` function run for every live particle each step.
public struct UpdateFunctionModule: LoweredModule {
    public static let kind = "function"
    public var function: ParticleFunction

    public init(function: ParticleFunction) {
        self.function = function
    }

    init?(lifting emitter: ParticleEmitter) {
        guard let function = emitter.updateFunction else {
            return nil
        }
        self.function = function
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.updateFunction = function
    }
}

/// A user function run when a particle hits a collider.
public struct CollisionFunctionModule: LoweredModule {
    public static let kind = "collisionFunction"
    public var function: ParticleFunction

    public init(function: ParticleFunction) {
        self.function = function
    }

    init?(lifting emitter: ParticleEmitter) {
        guard let function = emitter.collisionFunction else {
            return nil
        }
        self.function = function
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.collisionFunction = function
    }
}

/// A user function run on the step a particle dies.
public struct DeathFunctionModule: LoweredModule {
    public static let kind = "deathFunction"
    public var function: ParticleFunction

    public init(function: ParticleFunction) {
        self.function = function
    }

    init?(lifting emitter: ParticleEmitter) {
        guard let function = emitter.deathFunction else {
            return nil
        }
        self.function = function
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.deathFunction = function
    }
}

/// A user `[[stitchable]]` module in the update stack. Lifting adds these separately, one per module.
public struct StitchedUpdateModule: LoweredModule {
    public static let kind = "stitched"
    public static let added: Self? = Self(module: .template)
    public var module: StitchedModule

    public init(module: StitchedModule) {
        self.module = module
    }

    init?(lifting _: ParticleEmitter) {
        nil
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.updateModules.append(module)
    }
}
