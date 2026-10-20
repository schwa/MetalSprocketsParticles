import Foundation
import Metal
import MetalSprockets

// A stack of stitched modules travels through the function-slot machinery as a ParticleFunction whose source is a
// marker plus the modules. The runtime caches it by that source like any user function, and compile() stitches it.

extension StitchedModule {
    static let marker = "// particle-stitched-modules\n"
    private static let separator = "\n// particle-stitched-module-separator\n"

    static func function(for modules: [StitchedModule], slot: ParticleFunctionSlot) -> ParticleFunction {
        let source = marker + modules.map { "\($0.name)\n\($0.source)" }.joined(separator: separator)
        let parameters = modules.flatMap { module in
            Array(module.parameters.prefix(module.parameterCount)) + Array(repeating: SIMD4<Float>.zero, count: max(module.parameterCount - module.parameters.count, 0))
        }
        return ParticleFunction(source: source, name: "particleStitched_\(slot)_\(stableHash(source))", parameters: parameters)
    }

    /// The modules (name and source only) a marker function stands for, or nil for an ordinary user function.
    static func modules(in function: ParticleFunction) -> [StitchedModule]? {
        guard function.source.hasPrefix(marker) else {
            return nil
        }
        return function.source.dropFirst(marker.count).components(separatedBy: separator).map { entry in
            let parts = entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            return StitchedModule(source: parts.count > 1 ? String(parts[1]) : "", name: String(parts[0]))
        }
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
