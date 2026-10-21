import Metal

// The runtime's API in modules (#204). Each emitter keeps only its modules (#227).

public extension ParticleSystemRuntime.Emitter {
    /// The emitter's behavior as modules.
    var modules: EmitterModules {
        get { storedModules }
        set { configure(modules: newValue) }
    }
}

public extension ParticleSystemRuntime {
    /// Creates a system with a single emitter.
    convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), capacity: Int, modules: EmitterModules, seed: UInt32 = 0) throws {
        try self.init(device: device, modules: [modules], capacity: capacity, seed: seed)
    }

    /// Adds an emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    func addEmitter(_ modules: EmitterModules, capacity: Int) throws -> Emitter {
        try rebuild(adding: [(modules: modules, capacity: capacity)])
        return emitters[emitters.count - 1]
    }
}
