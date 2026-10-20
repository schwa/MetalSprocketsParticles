import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

// Spike for #182: can update behaviors be [[stitchable]] modules, stitched into one function for the update slot?
@Suite(.serialized, .requiresMetal4)
struct StitchingSpikeTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    // Each module takes the user-function arguments and returns `parameters` advanced past its own entries, so the
    // next module reads its own. The data dependency on that pointer also fixes the order.
    static let moduleSource = ParticleFunction.prelude + """
    [[stitchable]] constant float4 *gravityModule(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
        p.velocity += parameters[0].xyz * dt;
        return parameters + 1;
    }
    [[stitchable]] constant float4 *dragModule(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
        p.velocity *= max(0.0, 1.0 - parameters[0].x * dt);
        return parameters + 1;
    }
    [[stitchable]] constant float4 *colorOverLifeModule(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
        p.color = mix(parameters[0], parameters[1], saturate(p.age / p.lifetime));
        return parameters + 2;
    }
    [[stitchable]] void endModules(constant float4 *parameters) {}
    """

    // The same three behaviors written by hand, as one user function.
    static let handWritten = ParticleFunction(source: """
    [[visible]] void handWritten(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
        p.velocity += parameters[0].xyz * dt;
        p.velocity *= max(0.0, 1.0 - parameters[1].x * dt);
        p.color = mix(parameters[2], parameters[3], saturate(p.age / p.lifetime));
    }
    """, name: "handWritten", parameters: parameters)

    static let parameters: [SIMD4<Float>] = [[0, -9.8, 0, 0], [0.7, 0, 0, 0], [1, 0.5, 0, 1], [0, 0, 1, 0.2]]

    /// Stitches `modules`, in order, into a visible function named `name`.
    static func stitch(_ modules: [String], name: String, library: MTLLibrary, device: MTLDevice) throws -> MTLLibrary {
        let inputs = (0..<4).map { MTLFunctionStitchingInputNode(argumentIndex: $0) }
        var previous: MTLFunctionStitchingNode = inputs[3]
        var nodes: [MTLFunctionStitchingFunctionNode] = []
        for module in modules {
            let node = MTLFunctionStitchingFunctionNode(name: module, arguments: [inputs[0], inputs[1], inputs[2], previous], controlDependencies: [])
            nodes.append(node)
            previous = node
        }
        let end = MTLFunctionStitchingFunctionNode(name: "endModules", arguments: [previous], controlDependencies: [])
        let graph = MTLFunctionStitchingGraph(functionName: name, nodes: nodes, outputNode: end, attributes: [])
        let descriptor = MTLStitchedLibraryDescriptor()
        descriptor.functionGraphs = [graph]
        descriptor.functions = try (modules + ["endModules"]).map { try library.makeFunction(name: $0).orThrow(.resourceCreationFailure($0)) }
        return try device.makeLibrary(stitchedDescriptor: descriptor)
    }

    func run(_ emitter: ParticleEmitter, inject: ((ParticleSystemRuntime) throws -> Void)? = nil, frames: Int = 30) throws -> [Particle] {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: emitter)
        try inject?(system)
        system.burst(64)
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 64)
        return (0..<64).map { pointer[$0] }
    }

    func emitter(_ function: ParticleFunction) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .sphere(radius: 1)
        emitter.velocitySpread = 1
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 2...2
        emitter.birthRate = 0
        emitter.updateFunction = function
        return emitter
    }

    @Test func stitchedModulesMatchHandWrittenFunction() throws {
        let device = runner.device
        let modules = try device.makeLibrary(source: Self.moduleSource, options: nil)
        let stitchedLibrary = try Self.stitch(["gravityModule", "dragModule", "colorOverLifeModule"], name: "stitchedUpdate", library: modules, device: device)
        let stitched = try VisibleFunction(library: stitchedLibrary, name: "stitchedUpdate")

        let expected = try run(emitter(Self.handWritten))
        // The runtime caches compiled functions by source and name; put the stitched function where it will look.
        let placeholder = ParticleFunction(source: "// stitched", name: "stitchedUpdate", parameters: Self.parameters)
        let actual = try run(emitter(placeholder)) { system in
            system.compiledFunctions[ParticleSystemRuntime.FunctionKey(source: placeholder.source, name: placeholder.name)] = stitched
        }
        for (a, b) in zip(actual, expected) {
            #expect(a.position == b.position)
            #expect(a.velocity == b.velocity)
            #expect(a.properties == b.properties)
        }
        #expect(expected.contains { $0.velocity.y < -1 })
    }

    /// Median simulate GPU ms for 1M particles: no user function, the hand-written function, and the stitched one.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STITCHING_TIMINGS"] != nil)) func timings() throws {
        let device = runner.device
        let modules = try device.makeLibrary(source: Self.moduleSource, options: nil)
        let buildStart = ContinuousClock.now
        let builds = 20
        var stitchedLibrary: MTLLibrary?
        for index in 0..<builds {
            stitchedLibrary = try Self.stitch(["gravityModule", "dragModule", "colorOverLifeModule"], name: "stitched\(index)", library: modules, device: device)
        }
        print("stitch: \((ContinuousClock.now - buildStart) / builds) per graph")
        let stitched = try VisibleFunction(library: try stitchedLibrary.orThrow(.resourceCreationFailure("")), name: "stitched\(builds - 1)")
        let placeholder = ParticleFunction(source: "// stitched", name: "stitched\(builds - 1)", parameters: Self.parameters)

        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        let cases: [(String, ParticleFunction?, VisibleFunction?)] = [
            ("built-in only", nil, nil),
            ("hand-written", Self.handWritten, nil),
            ("stitched", placeholder, stitched),
        ]
        for (label, function, inject) in cases {
            var settings = emitter(function ?? Self.handWritten)
            settings.updateFunction = function
            settings.lifetime = 2...2
            settings.birthRate = 500_000
            let start = ContinuousClock.now
            let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1_000_000, emitter: settings)
            if let inject, let function {
                system.compiledFunctions[ParticleSystemRuntime.FunctionKey(source: function.source, name: function.name)] = inject
            }
            var times: [Double] = []
            var first: Duration?
            for frame in 0..<240 {
                let result = try renderer.render(try system.simulate(deltaTime: 1.0 / 60.0))
                if first == nil {
                    first = ContinuousClock.now - start
                }
                if frame >= 180 {
                    times.append((result.gpuTime ?? .nan) * 1_000)
                }
            }
            let median = times.sorted()[times.count / 2]
            print(String(format: "timing %@: %.3f ms GPU (first frame incl. pipeline: %@)", label, median, "\(first!)"))
        }
    }

    /// Records which kinds of arguments a [[stitchable]] function accepts.
    @Test func stitchableSignatures() throws {
        let cases: [(String, String)] = [
            ("thread reference to struct", "[[stitchable]] void f(thread ParticleState &p) {}"),
            ("struct by value, returned", "[[stitchable]] ParticleState f(ParticleState p) { return p; }"),
            ("vectors", "[[stitchable]] float3 f(float3 v, float dt) { return v * dt; }"),
            ("constant pointer", "[[stitchable]] constant float4 *f(constant float4 *p) { return p + 1; }"),
            ("device pointer", "[[stitchable]] void f(device float4 *p) { p[0] = 1; }"),
        ]
        for (label, source) in cases {
            let result: String
            do {
                _ = try runner.device.makeLibrary(source: ParticleFunction.prelude + source, options: nil)
                result = "compiles"
            } catch {
                result = "fails: \(error.localizedDescription.prefix(200))"
            }
            print("stitchable \(label): \(result)")
        }
    }
}
