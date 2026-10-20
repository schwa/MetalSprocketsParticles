import Foundation
import Metal
@testable import MetalSprocketsParticles
import Testing

// Spike for #205: can a stitched stack of built-in modules run as fast as the same code inline in the kernel?
// Three kernels over 1M particles, same loads and stores: the modules inline, the stitched stack through a visible
// function table, and the stitched stack called directly as an extern function linked privately into the pipeline.
@Suite(.serialized, .requiresMetal4, .enabled(if: ProcessInfo.processInfo.environment["STITCHING_TIMINGS"] != nil))
struct StitchingInlineSpikeTests {
    static let moduleBodies: [(name: String, body: String)] = [
        ("gravityModule", "p.velocity += parameters[0].xyz * dt;"),
        ("dragModule", "p.velocity *= max(0.0, 1.0 - parameters[0].x * dt);"),
        ("integrateModule", "p.position += p.velocity * dt;"),
        ("colorOverLifeModule", "p.color = mix(parameters[0], parameters[1], saturate(p.age / p.lifetime));"),
        ("sizeOverLifeModule", "p.size = mix(parameters[0].x, parameters[0].y, saturate(p.age / p.lifetime));"),
        ("swirlModule", "p.velocity += cross(float3(0, 1, 0), p.position) * parameters[0].x * dt;"),
        ("floorModule", "if (p.position.y < parameters[0].x) { p.position.y = parameters[0].x; p.velocity.y *= -0.5; }"),
        ("ageModule", "p.age += dt;"),
    ]
    static let parameterCounts = [1, 1, 0, 2, 1, 1, 1, 0]

    static var modulesSource: String {
        zip(moduleBodies, parameterCounts).map { module, count in
            "[[stitchable]] constant float4 *\(module.name)(thread ParticleState &p, float dt, float time, constant float4 *parameters) { \(module.body) return parameters + \(count); }"
        }.joined(separator: "\n") + "\n[[stitchable]] void endModules(constant float4 *parameters) {}\n"
    }

    static var inlineBody: String {
        var offset = 0
        var lines: [String] = []
        for (module, count) in zip(moduleBodies, parameterCounts) {
            lines.append("{ constant float4 *parameters = allParameters + \(offset); \(module.body) }")
            offset += count
        }
        return lines.joined(separator: "\n")
    }

    static func kernelSource(mode: String) -> String {
        let call: String
        switch mode {
        case "inline": call = inlineBody
        case "table": call = "table[0](p, dt, time, allParameters);"
        default: call = "particleStack(p, dt, time, allParameters);"
        }
        return ParticleFunction.prelude + """
        struct Stored { float4 position; float4 velocity; float4 color; float4 misc; };
        using StackFunction = void(thread ParticleState &, float, float, constant float4 *);
        \(mode == "direct" ? "[[visible]] extern void particleStack(thread ParticleState &p, float dt, float time, constant float4 *parameters);" : "")
        kernel void step(device Stored *particles [[buffer(0)]], constant float4 *allParameters [[buffer(1)]],
            \(mode == "table" ? "visible_function_table<StackFunction> table [[buffer(2)]]," : "")
            uint id [[thread_position_in_grid]]) {
            float dt = 1.0 / 60.0;
            float time = 1;
            Stored s = particles[id];
            ParticleState p = { s.position.xyz, s.velocity.xyz, s.position.w, s.velocity.w, id, s.color, s.misc.x, 0, 0, 0, 0 };
            // Values live across the call, like the real kernel's colliders, uniforms, and start position.
            float4 live[12];
            for (int i = 0; i < 12; i++) { live[i] = sin(s.position * float(i + 1)) + allParameters[i % 8]; }
            \(call)
            float4 extra = 0;
            for (int i = 0; i < 12; i++) { extra += live[i] * cos(p.position.x * float(i)); }
            particles[id] = { float4(p.position, p.age), float4(p.velocity, p.lifetime), p.color + extra * 1e-6, float4(p.size, 0, 0, 0) };
        }
        """
    }

    func stitchedStack(device: MTLDevice) throws -> MTLFunction {
        let library = try device.makeLibrary(source: ParticleFunction.prelude + Self.modulesSource, options: nil)
        let inputs = (0..<4).map { MTLFunctionStitchingInputNode(argumentIndex: $0) }
        var previous: MTLFunctionStitchingNode = inputs[3]
        var nodes: [MTLFunctionStitchingFunctionNode] = []
        for module in Self.moduleBodies {
            let node = MTLFunctionStitchingFunctionNode(name: module.name, arguments: [inputs[0], inputs[1], inputs[2], previous], controlDependencies: [])
            nodes.append(node)
            previous = node
        }
        let end = MTLFunctionStitchingFunctionNode(name: "endModules", arguments: [previous], controlDependencies: [])
        let descriptor = MTLStitchedLibraryDescriptor()
        descriptor.functionGraphs = [MTLFunctionStitchingGraph(functionName: "particleStack", nodes: nodes, outputNode: end, attributes: [])]
        descriptor.functions = (Self.moduleBodies.map(\.name) + ["endModules"]).compactMap { library.makeFunction(name: $0) }
        let stitched = try device.makeLibrary(stitchedDescriptor: descriptor)
        return try #require(stitched.makeFunction(name: "particleStack"))
    }

    /// GPU ms (median of 40) and the particles after one dispatch from the same start.
    func measure(mode: String, device: MTLDevice, queue: MTLCommandQueue, count: Int) throws -> (Double, [SIMD4<Float>]) {
        let library = try device.makeLibrary(source: Self.kernelSource(mode: mode), options: nil)
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = try #require(library.makeFunction(name: "step"))
        let stack = mode == "inline" ? nil : try stitchedStack(device: device)
        if let stack {
            let linked = MTLLinkedFunctions()
            if mode == "table" {
                linked.functions = [stack]
            } else {
                linked.privateFunctions = [stack]
            }
            descriptor.linkedFunctions = linked
        }
        let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        var table: MTLVisibleFunctionTable?
        if mode == "table", let stack {
            let tableDescriptor = MTLVisibleFunctionTableDescriptor()
            tableDescriptor.functionCount = 1
            table = pipeline.makeVisibleFunctionTable(descriptor: tableDescriptor)
            table?.setFunction(pipeline.functionHandle(function: stack), index: 0)
        }
        let stride = MemoryLayout<SIMD4<Float>>.stride * 4
        let start = (0..<count * 4).map { index -> SIMD4<Float> in
            let i = Float(index / 4)
            return [sin(i), cos(i * 0.3) + 1, sin(i * 0.7), 1 + (i.truncatingRemainder(dividingBy: 3))]
        }
        let particles = try #require(device.makeBuffer(bytes: start, length: count * stride))
        let parameters: [SIMD4<Float>] = [[0, -9.8, 0, 0], [0.3, 0, 0, 0], [1, 0.5, 0, 1], [0, 0, 1, 0], [0.1, 0.02, 0, 0], [0.5, 0, 0, 0], [0, 0, 0, 0], .zero]
        var times: [Double] = []
        var firstResult: [SIMD4<Float>] = []
        for run in 0..<50 {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(particles, offset: 0, index: 0)
            encoder.setBytes(parameters, length: parameters.count * 16, index: 1)
            if let table {
                encoder.setVisibleFunctionTable(table, bufferIndex: 2)
            }
            encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            if run == 0 {
                let pointer = particles.contents().bindMemory(to: SIMD4<Float>.self, capacity: count * 4)
                firstResult = (0..<64).map { pointer[$0] }
            }
            if run >= 10 {
                times.append((commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000)
            }
        }
        return (times.sorted()[times.count / 2], firstResult)
    }

    @Test func stitchedStackCost() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let count = 1_000_000
        var results: [String: [SIMD4<Float>]] = [:]
        for _ in 0..<2 {
            for mode in ["inline", "table", "direct"] {
                let (time, first) = try measure(mode: mode, device: device, queue: queue, count: count)
                results[mode] = first
                print(String(format: "inline-spike %@: %.3f ms", mode, time))
            }
        }
        #expect(results["table"] == results["inline"])
        #expect(results["direct"] == results["inline"])
    }
}
