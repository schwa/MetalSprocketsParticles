import Metal

// The runtime's API in modules (#204). The runtime itself keeps each emitter's lowered settings, which is what the
// simulation reads.

public extension ParticleSystemRuntime.Emitter {
    /// The emitter's behavior as modules. Reading lifts the current settings; setting lowers the modules.
    var modules: EmitterModules {
        get { EmitterModules(settings) }
        set { settings = newValue.lowered() }
    }
}

public extension ParticleSystemRuntime {
    /// Creates a system with one emitter per entry in `modules`, each with room for `capacity` particles. With none,
    /// an empty system to fill with `apply(_:)` or `load(_:)`.
    convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), modules: [EmitterModules] = [], capacity: Int = 1, seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: modules.map { $0.lowered() }, capacity: capacity, seed: seed)
    }

    /// Creates a system with a single emitter.
    convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), capacity: Int, modules: EmitterModules, seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: [modules.lowered()], capacity: capacity, seed: seed)
    }

    /// Replaces every emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    func setEmitters(_ emitters: [(modules: EmitterModules, capacity: Int)]) throws -> [Emitter] {
        try setEmitters(emitters.map { (settings: $0.modules.lowered(), capacity: $0.capacity) })
    }

    /// Adds an emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    func addEmitter(_ modules: EmitterModules, capacity: Int) throws -> Emitter {
        try addEmitter(modules.lowered(), capacity: capacity)
    }
}
