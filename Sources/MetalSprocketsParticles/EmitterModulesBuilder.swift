// Writing an emitter as a list of modules (#202):
//
//     EmitterDescription("Flame", sprite: .smoke) {
//         ShapeModule(shape: .disc(radius: 0.3))
//         RateModule(birthRate: 400)
//         VelocityModule(velocity: [0, 1.5, 0], spread: 0.3)
//         GravityModule(acceleration: [0, 1, 0])
//     }
//
// Each module goes to its stage in the order written. Required modules that are missing get their defaults.

@resultBuilder
public enum EmitterModulesBuilder {
    public static func buildExpression(_ module: any ParticleModule) -> [any ParticleModule] {
        [module]
    }

    public static func buildBlock(_ components: [any ParticleModule]...) -> [any ParticleModule] {
        components.flatMap(\.self)
    }

    // The result builder protocol fixes this signature.
    // swiftlint:disable:next discouraged_optional_collection
    public static func buildOptional(_ components: [any ParticleModule]?) -> [any ParticleModule] {
        components ?? []
    }

    public static func buildEither(first components: [any ParticleModule]) -> [any ParticleModule] {
        components
    }

    public static func buildEither(second components: [any ParticleModule]) -> [any ParticleModule] {
        components
    }

    public static func buildArray(_ components: [[any ParticleModule]]) -> [any ParticleModule] {
        components.flatMap(\.self)
    }
}

public extension EmitterModules {
    /// Modules from a list, each in its stage. Required modules that are missing get those of `standard`.
    init(@EmitterModulesBuilder _ content: () -> [any ParticleModule]) {
        let modules = content()
        self.init(
            spawn: Self.stage(SpawnModule.self, modules),
            update: Self.stage(UpdateModule.self, modules),
            render: Self.stage(RenderModule.self, modules)
        )
    }

    /// The modules that belong to `Stage`, with its missing required modules added in type order.
    private static func stage<Stage: StageModule>(_: Stage.Type, _ modules: [any ParticleModule]) -> [Stage] {
        var stage = modules.compactMap { Stage(wrapping: $0) }
        let present = Set(stage.map(\.kind))
        let defaults = standard.spawn.map(\.module.module) + standard.update.map(\.module.module) + standard.render.map(\.module.module)
        for type in Stage.types where type.isRequired && !present.contains(type.kind) {
            if let module = defaults.first(where: { Swift.type(of: $0) == type }), let wrapped = Stage(wrapping: module) {
                stage.append(wrapped)
            }
        }
        return stage
    }
}

public extension EmitterModules {
    /// A starting point for 3D effects: a small sphere spraying orange-to-red sparks upward that fall back down.
    static var standard: Self {
        Self(
            spawn: [
                .shape(ShapeModule()),
                .rate(RateModule()),
                .lifetime(LifetimeModule()),
                .velocity(VelocityModule(velocity: [0, 4, 0], spread: 1.5)),
            ],
            update: [
                .gravity(GravityModule(acceleration: [0, -9.8, 0])),
                .drag(DragModule(amount: 0.1)),
                .collision(CollisionModule()),
            ],
            render: [
                .sprite(SpriteModule()),
                .colorOverLife(ColorOverLifeModule(color: .linear(from: [1, 0.7, 0.2, 1], to: [0.8, 0.1, 0.05, 0]))),
                .sizeOverLife(SizeOverLifeModule(curve: .linear(from: 0.04, to: 0.01))),
                .shading(ShadingModule()),
            ]
        )
    }

    /// A starting point for 2D effects (`ParticleSystem.is2D`), in points: a fountain shooting up the screen at a few
    /// hundred points a second, falling back down (+y), 8 points across, kept on its plane.
    static var default2D: Self {
        var modules = standard
        modules[ShapeModule.self]?.shape = .point
        modules[RateModule.self]?.birthRate = 200
        modules[VelocityModule.self] = VelocityModule(velocity: [0, -400, 0], spread: 150, speedVariation: 100)
        modules[GravityModule.self] = GravityModule(acceleration: [0, 500, 0])
        modules[DragModule.self] = DragModule(amount: 0.3)
        modules[LifetimeModule.self] = LifetimeModule(range: 1...2)
        modules[SizeOverLifeModule.self] = SizeOverLifeModule(curve: .constant(4))
        modules[PlaneConstraintModule.self] = PlaneConstraintModule()
        return modules
    }
}

public extension EmitterDescription {
    /// An emitter written as a list of modules; see `EmitterModulesBuilder`.
    init(
        _ name: String,
        sprite: ParticleSprite = .softDot,
        motion: EmitterMotion = EmitterMotion(),
        simulationSpace: SimulationSpace = .world,
        capacity: Int = 50_000,
        isEmitting: Bool = true,
        @EmitterModulesBuilder modules: () -> [any ParticleModule]
    ) {
        self.init(name, modules: EmitterModules(modules), sprite: sprite, motion: motion, simulationSpace: simulationSpace, capacity: capacity, isEmitting: isEmitting)
    }
}
