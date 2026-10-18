import Metal
import MetalSprockets

/// A user-supplied Metal function that runs for each particle, for behavior the built-in settings cannot express.
///
/// `source` is Metal code that defines a `[[visible]]` function called `name` with this signature:
///
/// ```metal
/// [[visible]] void name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
/// ```
///
/// The system compiles `source` after `ParticleFunction.prelude`, which includes `<metal_stdlib>` and declares
/// `ParticleState`. Change `particle` to change the particle. `time` is the emitter's clock in seconds, and
/// `parameters` holds `parameters` from Swift (at least one entry).
public struct ParticleFunction: Sendable, Hashable, Codable {
    public var source: String
    public var name: String
    public var parameters: [SIMD4<Float>]

    public init(source: String, name: String, parameters: [SIMD4<Float>] = []) {
        self.source = source
        self.name = name
        self.parameters = parameters
    }

    /// Put before `source` when compiling. Mirrors `ParticleState` in the simulation kernel.
    public static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct ParticleState {
        float3 position; // World space.
        float3 velocity; // World units per second.
        float age;       // Seconds since birth.
        float lifetime;  // Seconds the particle lives.
        uint id;         // Index in the system's particle buffer.
    };

    """
}

/// A `ParticleFunction` that could not be compiled or found.
public struct ParticleFunctionError: Error, LocalizedError, Sendable {
    /// The function's `name`.
    public var name: String
    /// The compiler's message, or why the function was not found.
    public var message: String

    public var errorDescription: String? {
        "Particle function '\(name)' failed: \(message)"
    }
}

public extension ParticleFunction {
    /// Compiles the function on `device`. Throws `ParticleFunctionError` if it does not compile or is missing.
    func validate(device: MTLDevice) throws {
        _ = try compile(device: device)
    }

    internal func compile(device: MTLDevice) throws -> VisibleFunction {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.prelude + source, options: nil)
        } catch {
            throw ParticleFunctionError(name: name, message: error.localizedDescription)
        }
        // Libraries list only functions with an entry point, so a function without [[visible]] is missing here too.
        guard library.functionNames.contains(name) else {
            throw ParticleFunctionError(name: name, message: "The source defines no [[visible]] function with that name.")
        }
        do {
            return try VisibleFunction(library: library, name: name)
        } catch {
            throw ParticleFunctionError(name: name, message: error.localizedDescription)
        }
    }
}

extension ParticleEmitter {
    /// This emitter's and its sub-emitters' functions.
    var allFunctions: [ParticleFunction] {
        ([self] + subEmitters.map(\.settings)).flatMap { [$0.updateFunction, $0.spawnFunction] }.compactMap(\.self)
    }
}

public extension ParticlePreset {
    /// Compiles every layer's functions, so a bad effect file fails when opened rather than when it first runs.
    func validateFunctions(device: MTLDevice) throws {
        for function in layers.flatMap(\.settings.allFunctions) {
            try function.validate(device: device)
        }
    }
}

public extension ParticleSystem {
    /// Compiles every emitter's update and spawn functions, including sub-emitters', so errors show up now rather
    /// than on the next `simulate`. `load(_:)` calls this.
    func compileFunctions() throws {
        for function in emitters.flatMap(\.settings.allFunctions) {
            _ = try visibleFunction(for: function)
        }
    }
}

extension ParticleSystem {
    /// The linked function for `function`, compiled once per source and name. Throws `ParticleFunctionError`.
    func visibleFunction(for function: ParticleFunction) throws -> VisibleFunction {
        let key = FunctionKey(source: function.source, name: function.name)
        if let cached = compiledFunctions[key] {
            return cached
        }
        let compiled = try function.compile(device: device)
        compiledFunctions[key] = compiled
        return compiled
    }

    struct FunctionKey: Hashable {
        var source: String
        var name: String
    }
}
