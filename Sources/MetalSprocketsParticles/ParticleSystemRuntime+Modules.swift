import Metal

// The runtime's API in modules (#204). Each emitter keeps its modules and their lowered settings (#226).

public extension ParticleSystemRuntime.Emitter {
    /// The emitter's behavior as modules.
    var modules: EmitterModules {
        get { storedModules }
        set { configure(modules: newValue, settings: newValue.lowered()) }
    }
}

public extension ParticleSystemRuntime {
    /// Creates a system with one emitter per entry in `modules`, each with room for `capacity` particles. With none,
    /// an empty system to fill with `apply(_:)` or `load(_:)`.
    convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), modules: [EmitterModules] = [], capacity: Int = 1, seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: modules.map { $0.lowered() }, capacity: capacity, seed: seed)
        keep(modules, in: emitters)
    }

    /// Creates a system with a single emitter.
    convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), capacity: Int, modules: EmitterModules, seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: [modules.lowered()], capacity: capacity, seed: seed)
        keep([modules], in: emitters)
    }

    /// Replaces every emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    func setEmitters(_ emitters: [(modules: EmitterModules, capacity: Int)]) throws -> [Emitter] {
        let created = try setEmitters(emitters.map { (settings: $0.modules.lowered(), capacity: $0.capacity) })
        keep(emitters.map(\.modules), in: created)
        return created
    }

    /// Gives each emitter the modules it was made from, disabled ones included, instead of ones lifted from settings.
    private func keep(_ modules: [EmitterModules], in emitters: [Emitter]) {
        for (emitter, modules) in zip(emitters, modules) {
            emitter.configure(modules: modules, settings: emitter.settings)
        }
    }

    /// Adds an emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    func addEmitter(_ modules: EmitterModules, capacity: Int) throws -> Emitter {
        try addEmitter(modules.lowered(), capacity: capacity)
    }
}
