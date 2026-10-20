import Foundation
import Metal
import MetalSprockets

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
        var sources: [String] = []
        for module in modules where !sources.contains(module.source) {
            sources.append(module.source)
        }
        let source = ParticleFunction.prelude + sources.joined(separator: "\n") + "\n[[stitchable]] void particleEndModules(constant float4 *parameters) {}\n"
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ParticleFunctionError(name: name, message: error.localizedDescription)
        }
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
        var functions: [MTLFunction] = []
        for functionName in Set(modules.map(\.name) + ["particleEndModules"]) {
            guard let function = library.makeFunction(name: functionName) else {
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

    /// FNV-1a, so names stay the same across launches (Hasher is seeded per process).
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
