import simd

// What the runtime reads from an emitter's modules on the CPU (#227): emission, LOD, sub-emitters, triggers, functions.
// Each value is what `lowered()` would give: a missing module leaves the neutral value, modules that add up (sub-
// emitters, triggers, stitched modules) are joined in stack order, and the last of a replacing module wins.

/// The runtime's per-frame view of an emitter's modules, found in one pass. Runtime emitters cache it until their
/// modules change, because frame planning reads these values many times per emitter per frame.
struct ResolvedModules {
    var rate: RateModule
    var lifetime: ClosedRange<Float>
    var inheritVelocity: Float
    var levelOfDetail = LevelOfDetailModule()
    var shape: EmitterShape
    var position: SIMD3<Float>
    var subEmitters: [SubEmitter] = []
    var triggers: [EmissionTrigger] = []
    var flocking: ParticleFlocking?
    var trail: ParticleTrail?
    var sortMode: ParticleSortMode
    var events: EventsModule?
    var collidesWithSceneDepth = false
    var light: ParticleLightEmission?
    var colorOverLife: ColorOverLifeModule?
    /// The by-position gradient when it colors particles where they are born.
    var birthPositionColor: ParticleCurve<SIMD4<Float>>?
    /// One per `ParticleFunctionSlot`, in order.
    var functions: [SlotFunction?]
    var usesCustomAttributes: Bool

    init(_ modules: EmitterModules) {
        rate = NeutralModules.rate
        lifetime = NeutralModules.lifetime.range
        inheritVelocity = 0
        shape = NeutralModules.shape.shape
        position = NeutralModules.shape.position
        sortMode = NeutralModules.sprite.sortMode
        var userFunctions: [ParticleFunctionSlot: ParticleFunction] = [:]
        var stitchedUpdate: [StitchedModule] = []
        var stitchedSpawn: [StitchedModule] = []
        for slot in modules.spawn where slot.isEnabled {
            switch slot.module {
            case let .shape(module):
                shape = module.shape
                position = module.position
            case let .rate(module): rate = module
            case let .lifetime(module): lifetime = module.range
            case let .velocity(module): inheritVelocity = module.inherit
            case let .function(module): userFunctions[.spawn] = module.function
            case let .stitched(module): stitchedSpawn.append(module.module)
            case .rotation, .variation, .colorImage: break
            }
        }
        for slot in modules.update where slot.isEnabled {
            switch slot.module {
            case let .flocking(module): flocking = module.flocking
            case let .collision(module): collidesWithSceneDepth = module.collidesWithSceneDepth
            case let .events(module): events = module
            case let .subEmitters(module): subEmitters += module.emitters
            case let .triggers(module): triggers += module.triggers
            case let .function(module): userFunctions[.update] = module.function
            case let .collisionFunction(module): userFunctions[.collision] = module.function
            case let .deathFunction(module): userFunctions[.death] = module.function
            case let .stitched(module): stitchedUpdate.append(module.module)
            case .gravity, .drag, .planeConstraint: break
            }
        }
        for slot in modules.render where slot.isEnabled {
            switch slot.module {
            case let .sprite(module): sortMode = module.sortMode
            case let .colorOverLife(module): colorOverLife = module
            case let .colorByPosition(module): birthPositionColor = module.atBirth ? module.curve : nil
            case let .trail(module): trail = module.trail
            case let .light(module): light = module.light
            case let .levelOfDetail(module): levelOfDetail = module
            case .sizeOverLife, .colorBySpeed, .imageSequence, .shading, .mesh, .ribbon: break
            }
        }
        // A function wins over stitched modules; `validateFunctions` reports having both.
        functions = ParticleFunctionSlot.allCases.map { slot in
            if let function = userFunctions[slot] {
                return .user(function)
            }
            let stitched = slot == .update ? stitchedUpdate : slot == .spawn ? stitchedSpawn : []
            return stitched.isEmpty ? nil : .stitched(stitched, slot: slot)
        }
        usesCustomAttributes = functions.contains { $0?.usesCustomAttributes ?? false }
    }

    func function(for slot: ParticleFunctionSlot) -> SlotFunction? {
        functions[ParticleFunctionSlot.allCases.firstIndex(of: slot) ?? 0]
    }
}

/// What applies when an emitter has no module of a kind: nothing moves, colors, or grows; particles spawn from a
/// small sphere at the default rate and lifetime and bounce with the default collision response.
enum NeutralModules {
    static let shape = ShapeModule()
    static let rate = RateModule()
    static let lifetime = LifetimeModule()
    static let collision = CollisionModule()
    static let sprite = SpriteModule()
    static let colorOverLife = ColorOverLifeModule(color: .constant([1, 1, 1, 1]))
    static let sizeOverLife = SizeOverLifeModule(curve: .constant(0.04))
    static let colorBySpeed = ColorBySpeedModule(curve: nil)
    static let colorByPosition = ColorByPositionModule(curve: nil)
}

extension EmitterModules {

    /// Every enabled module of type `Module`, in stage order. For occasional checks; per-frame code uses
    /// `ResolvedModules`.
    func allEnabled<Module: ParticleModule>(_: Module.Type) -> [Module] {
        var found: [Module] = []
        for slot in spawn where slot.isEnabled {
            if let module = slot.module.module as? Module {
                found.append(module)
            }
        }
        for slot in update where slot.isEnabled {
            if let module = slot.module.module as? Module {
                found.append(module)
            }
        }
        for slot in render where slot.isEnabled {
            if let module = slot.module.module as? Module {
                found.append(module)
            }
        }
        return found
    }

    var resolved: ResolvedModules { ResolvedModules(self) }

    func function(for slot: ParticleFunctionSlot) -> SlotFunction? {
        resolved.function(for: slot)
    }

    /// Whether any of this emitter's own functions may use custom attributes, so the kernel must keep them.
    var usesCustomAttributes: Bool {
        resolved.usesCustomAttributes
    }

    /// This emitter's and its sub-emitters' functions.
    var allFunctions: [SlotFunction] {
        let resolved = resolved
        return resolved.functions.compactMap(\.self) + resolved.subEmitters.flatMap { $0.modules.resolved.functions.compactMap(\.self) }
    }
}

extension RateModule {
    /// This rate with the birth rate and its variation scaled; unchanged at 1, so default emitters keep their exact
    /// arithmetic.
    func scaled(by scale: Float) -> Self {
        guard scale != 1 else {
            return self
        }
        var copy = self
        copy.birthRate *= scale
        copy.variation *= scale
        return copy
    }
}
