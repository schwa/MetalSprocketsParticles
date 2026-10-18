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

extension ParticleSystem {
    /// The linked function for `function`, compiled once per source and name.
    func visibleFunction(for function: ParticleFunction) throws -> VisibleFunction {
        let key = FunctionKey(source: function.source, name: function.name)
        if let cached = compiledFunctions[key] {
            return cached
        }
        let library = try device.makeLibrary(source: ParticleFunction.prelude + function.source, options: nil)
        let compiled = try VisibleFunction(library: library, name: function.name)
        compiledFunctions[key] = compiled
        return compiled
    }

    struct FunctionKey: Hashable {
        var source: String
        var name: String
    }
}
