import simd

// An emitter as ordered module stacks per stage (#178). See Documentation/Modules.md. The module types are in
// SpawnModules.swift, UpdateModules.swift, and RenderModules.swift.
//
// Built-in modules lower to ParticleEmitter, which the simulation kernel reads as uniforms, so they cost nothing per
// module. Stitched modules (user [[stitchable]] functions) run in stack order inside the stage's function slot.

/// A module in a stack, with a switch to turn it off without removing it.
public struct ModuleSlot<Module: StageModule>: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var module: Module

    public init(_ module: Module, isEnabled: Bool = true) {
        self.module = module
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, module
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        module = try container.decode(Module.self, forKey: .module)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(module, forKey: .module)
        if !isEnabled {
            try container.encode(false, forKey: .isEnabled)
        }
    }
}

/// A user module: a `[[stitchable]]` Metal function stitched with the stage's other user modules into one function.
///
/// ```metal
/// [[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
/// ```
///
/// Read your entries from `parameters` and return `parameters + parameterCount`, so the next module reads its own.
/// `source` compiles after `ParticleFunction.prelude`.
public struct StitchedModule: Sendable, Hashable, Codable {
    public var source: String
    public var name: String
    public var parameters: [SIMD4<Float>]
    /// Entries this module reads and skips; `parameters` is padded with zeros to this count.
    public var parameterCount: Int

    public init(source: String, name: String, parameters: [SIMD4<Float>] = [], parameterCount: Int? = nil) {
        self.source = source
        self.name = name
        self.parameters = parameters
        self.parameterCount = parameterCount ?? parameters.count
    }
}

/// One emitter's behavior: a module stack per stage, applied in order, plus settings that belong to no stage.
public struct EmitterModules: Sendable, Equatable, Codable {
    public var spawn: [ModuleSlot<SpawnModule>] = []
    public var update: [ModuleSlot<UpdateModule>] = []
    public var render: [ModuleSlot<RenderModule>] = []
    /// Which colliders and force fields affect the particles.
    public var categoryMask: UInt32 = .max
    /// `ParticleState.custom` through `custom3` kept between steps, 1 to 4.
    public var customAttributeCount = 1

    public init(spawn: [SpawnModule] = [], update: [UpdateModule] = [], render: [RenderModule] = []) {
        self.spawn = spawn.map { ModuleSlot($0) }
        self.update = update.map { ModuleSlot($0) }
        self.render = render.map { ModuleSlot($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case spawn, update, render, categoryMask, customAttributeCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.update(&spawn, .spawn)
        try container.update(&render, .render)
        // Format 2 had the appearance modules (color and size over life...) in update; they move to render.
        if container.contains(.update) {
            var entries = try container.nestedUnkeyedContainer(forKey: .update)
            while !entries.isAtEnd {
                let entry = try entries.superDecoder()
                do {
                    update.append(try ModuleSlot<UpdateModule>(from: entry))
                } catch {
                    guard let moved = try? ModuleSlot<RenderModule>(from: entry) else {
                        throw error
                    }
                    render.append(moved)
                }
            }
        }
        try container.update(&categoryMask, .categoryMask)
        try container.update(&customAttributeCount, .customAttributeCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spawn, forKey: .spawn)
        try container.encode(update, forKey: .update)
        try container.encode(render, forKey: .render)
        if categoryMask != .max {
            try container.encode(categoryMask, forKey: .categoryMask)
        }
        if customAttributeCount != 1 {
            try container.encode(customAttributeCount, forKey: .customAttributeCount)
        }
    }
}

// MARK: - Typed access

public extension EmitterModules {
    /// The first module of type `Module` in any stage, enabled or not. Setting replaces it, adds it to its stage when
    /// there is none, or removes it for nil:
    ///
    ///     modules[RateModule.self]?.birthRate = 500
    ///     modules[GravityModule.self] = GravityModule(acceleration: [0, -1, 0])
    subscript<Module: ParticleModule>(_: Module.Type) -> Module? {
        get {
            spawn.lazy.compactMap { $0.module.module as? Module }.first
                ?? update.lazy.compactMap { $0.module.module as? Module }.first
                ?? render.lazy.compactMap { $0.module.module as? Module }.first
        }
        set {
            if spawn.replaceFirst(Module.self, with: newValue) || update.replaceFirst(Module.self, with: newValue) || render.replaceFirst(Module.self, with: newValue) {
                return
            }
            guard let newValue else {
                return
            }
            if let module = SpawnModule(wrapping: newValue) {
                spawn.append(ModuleSlot(module))
            } else if let module = UpdateModule(wrapping: newValue) {
                update.append(ModuleSlot(module))
            } else if let module = RenderModule(wrapping: newValue) {
                render.append(ModuleSlot(module))
            }
        }
    }
}

extension Array {
    /// Replaces (or for nil removes) the first slot holding a `Module`. Returns whether there was one.
    mutating func replaceFirst<Stage: StageModule, Module: ParticleModule>(_: Module.Type, with module: Module?) -> Bool where Element == ModuleSlot<Stage> {
        guard let index = firstIndex(where: { $0.module.module is Module }) else {
            return false
        }
        if let module, let wrapped = Stage(wrapping: module) {
            self[index].module = wrapped
        } else {
            remove(at: index)
        }
        return true
    }
}

// MARK: - Merging

extension Array {
    /// `lifted` in this stack's order: each enabled slot takes the next lifted module of its kind; disabled slots stay
    /// where they are; lifted modules of new kinds go at the end.
    func merging<Module: StageModule>(_ lifted: [ModuleSlot<Module>]) -> [ModuleSlot<Module>] where Element == ModuleSlot<Module> {
        var pool = lifted
        var result: [ModuleSlot<Module>] = []
        for slot in self {
            if !slot.isEnabled {
                result.append(slot)
            } else if let index = pool.firstIndex(where: { $0.module.kind == slot.module.kind }) {
                result.append(pool.remove(at: index))
            }
        }
        return result + pool
    }
}

public extension EmitterModules {
    /// `lifted`'s modules in this one's order, keeping this one's disabled modules.
    func merging(_ lifted: EmitterModules) -> EmitterModules {
        var merged = lifted
        merged.spawn = spawn.merging(lifted.spawn)
        merged.update = update.merging(lifted.update)
        merged.render = render.merging(lifted.render)
        return merged
    }
}

// MARK: - Lowering and lifting

public extension ParticleEmitter {
    /// What an emitter does with no modules: nothing moves, colors, or grows; it just spawns with the shape's defaults.
    /// Modules are applied on top of this.
    static var neutral: Self {
        var emitter = Self()
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.sizeOverLife = .constant(0.04)
        return emitter
    }
}

public extension EmitterModules {
    /// The flat settings the simulation runs. Disabled modules are skipped.
    func lowered() -> ParticleEmitter {
        var emitter = ParticleEmitter.neutral
        emitter.categoryMask = categoryMask
        emitter.customAttributeCount = customAttributeCount
        for slot in spawn where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        for slot in update where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        for slot in render where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        return emitter
    }

    /// Modules that lower to `emitter`: each module type that `emitter` uses, in the stage's type order, then its
    /// stitched modules.
    init(_ emitter: ParticleEmitter) {
        self.init(
            spawn: SpawnModule.lifted(from: emitter) + emitter.spawnModules.map { .stitched(StitchedSpawnModule(module: $0)) },
            update: UpdateModule.lifted(from: emitter) + emitter.updateModules.map { .stitched(StitchedUpdateModule(module: $0)) },
            render: RenderModule.lifted(from: emitter)
        )
        categoryMask = emitter.categoryMask
        customAttributeCount = emitter.customAttributeCount
    }
}
