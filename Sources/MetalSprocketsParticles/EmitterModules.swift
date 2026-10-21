import simd

// An emitter as ordered module stacks per stage (#178). See Documentation/Modules.md. The module types are in
// SpawnModules.swift, UpdateModules.swift, and RenderModules.swift.
//
// Built-in modules write their part of the kernel uniforms, so they cost nothing per
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
        try container.update(&update, .update)
        try container.update(&render, .render)
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
