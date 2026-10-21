import Metal
import MetalSprockets

/// Every visible function the particle pipelines call (#222): user simulation functions, stitched module stacks, custom
/// shading functions, and the built-ins (slot no-ops, unlit, lit, foil). Each is compiled once per source and name,
/// linked the right way (built-ins static so calls inline, user code binary so a new function does not rebuild the
/// pipeline), and reported as `ParticleFunctionError` when it does not compile.
final class GPUFunctions {
    private let device: MTLDevice
    private let library: ShaderLibrary
    private var compiled: [Key: VisibleFunction] = [:]
    private var builtIns: BuiltInShading?

    /// What a compiled function depends on: never parameter values, which do not change what is linked.
    enum Key: Hashable {
        case simulation(SlotFunction.Key)
        case shading(source: String, name: String)
    }

    init(device: MTLDevice, library: ShaderLibrary) {
        self.device = device
        self.library = library
    }

    /// The function for `slot`: `function`, or the slot's built-in no-op when there is none.
    func simulation(_ function: SlotFunction?, slot: ParticleFunctionSlot) throws -> VisibleFunction {
        guard let function else {
            return try library.function(type: VisibleFunction.self, named: slot.noOpName)
        }
        return try cached(.simulation(function.key)) {
            try Self.compile(function, device: device)
        }
    }

    /// A custom shading function (`ShadingModel.custom`).
    func shading(_ function: ParticleFunction) throws -> VisibleFunction {
        try cached(.shading(source: function.source, name: function.name)) {
            try Self.compileShading(function, device: device)
        }
    }

    /// The built-in shading models, linked statically: they are always linked, so their pipeline is built once, and the
    /// compiler can inline them (per-pixel foil is ~45% faster than through a real call).
    func builtInShading() throws -> BuiltInShading {
        if let builtIns {
            return builtIns
        }
        let builtIns = BuiltInShading(
            unlit: try library.function(type: VisibleFunction.self, named: "particleShadeUnlit").linking(.static),
            lit: try library.function(type: VisibleFunction.self, named: "particleShadeLit").linking(.static),
            foil: try library.function(type: VisibleFunction.self, named: "particleShadeFoil").linking(.static)
        )
        self.builtIns = builtIns
        return builtIns
    }

    /// Puts `function` where `key` would be compiled, for tests that swap in hand-built functions.
    func store(_ function: VisibleFunction, for key: Key) {
        compiled[key] = function
    }

    private func cached(_ key: Key, _ compile: () throws -> VisibleFunction) throws -> VisibleFunction {
        if let function = compiled[key] {
            return function
        }
        let function = try compile()
        compiled[key] = function
        return function
    }

    // MARK: Compiling, without a cache (validation uses these directly)

    static func compile(_ function: SlotFunction, device: MTLDevice) throws -> VisibleFunction {
        switch function {
        case let .user(function): try compileSource(function, prelude: ParticleFunction.prelude, device: device)
        case let .stitched(modules, slot): try StitchedModule.stitch(modules, name: StitchedModule.functionName(for: modules, slot: slot), device: device)
        }
    }

    static func compileShading(_ function: ParticleFunction, device: MTLDevice) throws -> VisibleFunction {
        try compileSource(function, prelude: ShadingModule.prelude, device: device)
    }

    /// `function`'s source after `prelude`, as a binary-linked visible function.
    private static func compileSource(_ function: ParticleFunction, prelude: String, device: MTLDevice) throws -> VisibleFunction {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: prelude + function.source, options: nil)
        } catch {
            throw ParticleFunctionError(name: function.name, message: error.localizedDescription)
        }
        // Libraries list only functions with an entry point, so a function without [[visible]] is missing here too.
        guard library.functionNames.contains(function.name) else {
            throw ParticleFunctionError(name: function.name, message: "The source defines no [[visible]] function with that name.")
        }
        do {
            return try VisibleFunction(library: library, name: function.name)
        } catch {
            throw ParticleFunctionError(name: function.name, message: error.localizedDescription)
        }
    }
}
