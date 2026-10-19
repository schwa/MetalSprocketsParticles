import ArgumentParser
import CoreGraphics
import Foundation
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd

/// Measures GPU time for the simulate and render passes separately, plus CPU time to build and encode each frame.
@main
struct BenchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "particles-bench",
        abstract: "Benchmark particle simulation and rendering at several particle counts."
    )

    @Option(help: "Frames simulated before measuring, so the ring fills.")
    var warmupFrames = 150

    @Option(help: "Frames measured per scenario. Results are medians.")
    var frames = 60

    @Option(help: "Image width in pixels.")
    var width = 1_920

    @Option(help: "Image height in pixels.")
    var height = 1_080

    @Option(help: "User update function on the emitter: none, noop (empty), or work (some math).")
    var updateFunction = "none"

    @Flag(help: "Only the 1M scenarios.")
    var only1M = false

    @Flag(help: "Benchmark every sample preset (whole frames, as the demo plays them) instead of the scenarios.")
    var presets = false

    @Option(help: "With --presets: only presets whose name contains this.")
    var preset: String?

    @Option(help: "With --presets: frame budget in milliseconds (8.33 is 120 fps).")
    var budget = 8.33

    @Flag(help: "With --presets: exit with an error when any preset's median frame is over budget.")
    var check = false

    struct Scenario {
        var name: String
        var capacity: Int
        var alive: Int
        var turbulence = true
        /// Half-width in world units. 0.01 is a few pixels at 1080p from this camera.
        var size: Float = 0.01
        var sortMode: ParticleSortMode = .none
    }

    func run() throws {
        if presets {
            try runPresets()
            return
        }
        let scenarios = [
            Scenario(name: "10K", capacity: 10_000, alive: 10_000),
            Scenario(name: "100K", capacity: 100_000, alive: 100_000),
            Scenario(name: "1M", capacity: 1_000_000, alive: 1_000_000),
            Scenario(name: "1M cap, 100K alive", capacity: 1_000_000, alive: 100_000),
            Scenario(name: "1M, no turbulence", capacity: 1_000_000, alive: 1_000_000, turbulence: false),
            Scenario(name: "1M, sub-pixel", capacity: 1_000_000, alive: 1_000_000, size: 0.0005),
            Scenario(name: "1M, 4x size", capacity: 1_000_000, alive: 1_000_000, size: 0.04),
            Scenario(name: "10K, sorted", capacity: 10_000, alive: 10_000, sortMode: .backToFront),
            Scenario(name: "100K, sorted", capacity: 100_000, alive: 100_000, sortMode: .backToFront),
            Scenario(name: "1M, sorted", capacity: 1_000_000, alive: 1_000_000, sortMode: .backToFront),
        ]
        let selected = only1M ? scenarios.filter { $0.name.hasPrefix("1M") && $0.sortMode == .none } : scenarios
        print("Scenario              | simulate GPU | render GPU | CPU/frame")
        print("----------------------|--------------|------------|----------")
        for scenario in selected {
            let result = try measure(scenario)
            let name = scenario.name.padding(toLength: 21, withPad: " ", startingAt: 0)
            print("\(name) | \(milliseconds(result.simulate)) | \(milliseconds(result.render)) | \(milliseconds(result.cpu))")
        }
    }

    private func milliseconds(_ seconds: Double) -> String {
        String(format: "%9.3f ms", seconds * 1_000)
    }

    /// A typical effect: particles spread through the view at a moderate on-screen size, two colliders, one field.
    private func emitter(_ scenario: Scenario) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.position = [0, 1.5, 0]
        emitter.shape = .sphere(radius: 1)
        emitter.velocity = .zero
        emitter.velocitySpread = 1
        emitter.gravity = [0, -1, 0]
        emitter.drag = 0.5
        let lifetime: Float = 2
        emitter.lifetime = lifetime...lifetime
        emitter.birthRate = Float(scenario.alive) / lifetime
        emitter.sizeOverLife = .constant(scenario.size)
        emitter.sortMode = scenario.sortMode
        return emitter
    }

    private func measure(_ scenario: Scenario) throws -> (simulate: Double, render: Double, cpu: Double) {
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height))
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: scenario.capacity, emitter: emitter(scenario), seed: 0)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0), .sphere(center: [0, 0.5, 0], radius: 0.6)]
        system.forceFields = scenario.turbulence ? [.turbulence(strength: 1, scale: 1, speed: 0.3)] : []
        if updateFunction == "noop" || updateFunction == "work" {
            let source = """
            [[visible]] void noop(thread ParticleState &p, float dt, float time, constant float4 *parameters) {}
            [[visible]] void work(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
                float3 swirl = float3(-p.position.z, sin(time + p.position.x), p.position.x) * parameters[0].x;
                p.velocity += swirl * dt;
                p.position += normalize(p.velocity + 1e-4) * 0.001 * cos(p.age * 6.0);
            }
            """
            system.emitters[0].settings.updateFunction = ParticleFunction(source: source, name: updateFunction, parameters: [[0.5, 0, 0, 0]])
        }
        let view = simd_float4x4(lookingFrom: [0, 2, 5], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(width) / Float(height), near: 0.1, far: 100)

        var simulateTimes: [Double] = []
        var renderTimes: [Double] = []
        var cpuTimes: [Double] = []
        for frame in 0..<(warmupFrames + frames) {
            // Separate submissions so each pass gets its own GPU duration.
            let cpuStart = ContinuousClock.now
            let simulated = try renderer.render(try system.simulate(deltaTime: 1.0 / 60.0, view: view))
            let rendered = try renderer.render(try RenderPass { try system.render(projection: projection, view: view) })
            let cpu = ContinuousClock.now - cpuStart
            guard frame >= warmupFrames else {
                continue
            }
            simulateTimes.append(simulated.gpuTime ?? .nan)
            renderTimes.append(rendered.gpuTime ?? .nan)
            // Wall time minus GPU time: building, encoding, and submitting, without waiting on the GPU.
            let wall = Double(cpu.components.seconds) + Double(cpu.components.attoseconds) / 1e18
            cpuTimes.append(wall - (simulated.gpuTime ?? 0) - (rendered.gpuTime ?? 0))
        }
        return (median(simulateTimes), median(renderTimes), median(cpuTimes))
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }
}
