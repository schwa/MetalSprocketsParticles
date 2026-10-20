import Foundation
import Metal
import MetalSprockets

public extension StitchedModule {
    /// Compiles and stitches the module on its own. Throws `ParticleFunctionError` if it does not compile, is missing,
    /// or does not have the stitched module signature.
    func validate(device: MTLDevice) throws {
        _ = try Self.stitch([self], name: "particleValidate_\(name)", device: device)
    }

    /// A module that compiles as is, with an example that reads one parameter: a swirl around the Y axis.
    static var template: Self {
        Self(source: """
        [[stitchable]] constant float4 *swirl(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            // Turns particles around the Y axis; parameters[0].x sets how fast.
            particle.velocity += cross(float3(0, 1, 0), particle.position) * parameters[0].x * deltaTime;
            return parameters + 1;
        }
        """, name: "swirl", parameters: [[1, 0, 0, 0]])
    }
}

extension StitchedModule {
    /// What the stitched code depends on: everything but parameter values.
    struct Identity: Hashable {
        var source: String
        var name: String
    }

    var identity: Identity {
        Identity(source: source, name: name)
    }

    /// `parameters` cut or padded with zeros to `parameterCount`.
    var paddedParameters: [SIMD4<Float>] {
        Array(parameters.prefix(parameterCount)) + Array(repeating: .zero, count: max(parameterCount - parameters.count, 0))
    }

    /// The stitched function's name: one per distinct stack, since linking two functions with one name fails.
    static func functionName(for modules: [StitchedModule], slot: ParticleFunctionSlot) -> String {
        let identity = modules.map { "\($0.name)\u{0}\($0.source)" }.joined(separator: "\u{1}")
        return "particleStitched_\(slot)_\(stableHash(identity))"
    }

    /// One visible function named `name` that calls `modules` in order, each passing its returned parameter pointer on.
    static func stitch(_ modules: [StitchedModule], name: String, device: MTLDevice) throws -> VisibleFunction {
        // Graph nodes name functions, so one name must mean one function.
        var sourceByName: [String: String] = [:]
        for module in modules {
            if let other = sourceByName[module.name], other != module.source {
                throw ParticleFunctionError(name: module.name, message: "Two stitched modules in one stack are named '\(module.name)' but have different sources.")
            }
            sourceByName[module.name] = module.source
        }
        // Each distinct source compiles on its own, so helpers with the same name in different sources do not clash.
        var libraries: [String: MTLLibrary] = [:]
        for source in Set(sourceByName.values) {
            libraries[source] = try compile(ParticleFunction.prelude + source, name: name, device: device)
        }
        let endLibrary = try compile("[[stitchable]] void particleEndModules(constant float4 *parameters) {}\n", name: name, device: device)
        let inputs = (0..<4).map { MTLFunctionStitchingInputNode(argumentIndex: $0) }
        var previous: MTLFunctionStitchingNode = inputs[3]
        var nodes: [MTLFunctionStitchingFunctionNode] = []
        for module in modules {
            let node = MTLFunctionStitchingFunctionNode(name: module.name, arguments: [inputs[0], inputs[1], inputs[2], previous], controlDependencies: [])
            nodes.append(node)
            previous = node
        }
        let end = MTLFunctionStitchingFunctionNode(name: "particleEndModules", arguments: [previous], controlDependencies: [])
        let descriptor = MTLStitchedLibraryDescriptor()
        descriptor.functionGraphs = [MTLFunctionStitchingGraph(functionName: name, nodes: nodes, outputNode: end, attributes: [])]
        var functions: [MTLFunction] = endLibrary.makeFunction(name: "particleEndModules").map { [$0] } ?? []
        for (functionName, source) in sourceByName {
            guard let function = libraries[source]?.makeFunction(name: functionName) else {
                throw ParticleFunctionError(name: functionName, message: "The source defines no [[stitchable]] function with that name.")
            }
            functions.append(function)
        }
        descriptor.functions = functions
        do {
            let stitched = try device.makeLibrary(stitchedDescriptor: descriptor)
            return try VisibleFunction(library: stitched, name: name)
        } catch {
            throw ParticleFunctionError(name: name, message: error.localizedDescription)
        }
    }

    private static func compile(_ source: String, name: String, device: MTLDevice) throws -> MTLLibrary {
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ParticleFunctionError(name: name, message: error.localizedDescription)
        }
    }

    /// FNV-1a, so names stay the same across launches (Hasher is seeded per process).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
