import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct FlockingTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// `count` particles in a box of `size` with random directions at speed about 1, run for `frames` steps.
    func run(count: Int, size: Float, frames: Int, flocking: ParticleFlocking?) throws -> [Particle] {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .box(size: [size, size, size]) }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 1 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(DragModule.self) { $0.amount = 0 }
        emitter.edit(LifetimeModule.self) { $0.range = 100...100 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter[FlockingModule.self] = flocking.map(FlockingModule.init)
        let system = try ParticleSystemRuntime(device: runner.device, capacity: count, modules: emitter, seed: 3)
        system.burst(count)
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: count)
        return (0..<count).map { pointer[$0] }
    }

    /// 1 when every particle moves the same way, near 0 for random directions.
    func order(_ particles: [Particle]) -> Float {
        // Skip particles that happen to be still; their direction is undefined.
        let directions = particles.map { SIMD3($0.velocity.x, $0.velocity.y, $0.velocity.z) }
            .filter { simd_length($0) > 1e-4 }
            .map(simd_normalize)
        return simd_length(directions.reduce(.zero, +) / Float(directions.count))
    }

    func spread(_ particles: [Particle]) -> Float {
        let positions = particles.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
        let center = positions.reduce(.zero, +) / Float(positions.count)
        return positions.map { simd_distance($0, center) }.reduce(0, +) / Float(positions.count)
    }

    /// Flocking in a dense pile must stay cheap (#158). Each grid cell was sorted by one thread with an insertion sort,
    /// so a crowded cell cost its count squared on a single thread: Inside the Teapot's beads, piled in a few cells,
    /// took 2 to 5 ms of GPU a frame for 3 000 particles. Measured against the same preset without flocking, not a
    /// fixed budget, so it does not depend on the machine.
    @Test(.disabled(if: MetalDebugLayers.validationActive || MetalDebugLayers.captureActive, "Timing; the debug layers are slower (#230).")) func flockingInADensePileStaysCheap() throws {
        let preset = try #require(ParticleSystem.named("Inside the Teapot"))
        func averageGPUMilliseconds(_ system: ParticleSystem) throws -> Double {
            let size = CGSize(width: 320, height: 180)
            let renderer = try OffscreenRenderer(size: size)
            let player = try ParticlePlayer(system: system, device: renderer.device)
            var total: Double = 0
            for frame in 0..<240 {
                let rendering = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
                // After the beads have fallen into a pile.
                if frame >= 60 {
                    total += (rendering.gpuTime ?? 0) * 1_000
                }
            }
            return total / 180
        }
        var withoutFlocking = preset
        withoutFlocking.layers[1].modules[FlockingModule.self] = nil
        let flocking = try averageGPUMilliseconds(preset)
        let baseline = try averageGPUMilliseconds(withoutFlocking)
        #expect(flocking < baseline * 5 + 0.3, "with flocking \(flocking) ms, without \(baseline) ms")
    }

    @Test func alignmentMakesTheFlockMoveTogether() throws {
        let alignOnly = ParticleFlocking(radius: 2, separation: 0, alignment: 3, cohesion: 0, speedRange: 0...10)
        let before = order(try run(count: 200, size: 1, frames: 1, flocking: alignOnly))
        let after = order(try run(count: 200, size: 1, frames: 120, flocking: alignOnly))
        let free = order(try run(count: 200, size: 1, frames: 120, flocking: nil))
        #expect(before < 0.3)
        #expect(free < 0.3)
        #expect(after > 0.9)
    }

    @Test func cohesionPullsTheFlockTogether() throws {
        let cohereOnly = ParticleFlocking(radius: 3, separation: 0, alignment: 0, cohesion: 4, speedRange: 0...10)
        let free = spread(try run(count: 200, size: 2, frames: 60, flocking: nil))
        let together = spread(try run(count: 200, size: 2, frames: 60, flocking: cohereOnly))
        #expect(together < free * 0.6)
    }

    @Test func separationPushesCrowdsApart() throws {
        let separateOnly = ParticleFlocking(radius: 0.3, separationRadius: 0.3, separation: 0.05, alignment: 0, cohesion: 0, speedRange: 0...10)
        let free = spread(try run(count: 200, size: 0.2, frames: 30, flocking: nil))
        let apart = spread(try run(count: 200, size: 0.2, frames: 30, flocking: separateOnly))
        #expect(apart > free * 1.5)
    }

    @Test func speedStaysInRange() throws {
        let flock = ParticleFlocking(speedRange: 0.8...1.2)
        let particles = try run(count: 100, size: 1, frames: 30, flocking: flock)
        #expect(particles.allSatisfy { (0.79...1.21).contains(simd_length(SIMD3($0.velocity.x, $0.velocity.y, $0.velocity.z))) })
    }

    /// The grid scatter runs in atomic order; cells are sorted so neighbor order, and so results, never vary.
    @Test func flockingIsDeterministic() throws {
        let dense = ParticleFlocking(radius: 0.4, maxNeighbors: 8)
        let first = try run(count: 2_000, size: 1, frames: 60, flocking: dense)
        let second = try run(count: 2_000, size: 1, frames: 60, flocking: dense)
        // swiftlint:disable:next prefer_key_path
        #expect(first.map { $0.position } == second.map { $0.position })
    }

    @Test func largeFlocksRun() throws {
        // The grid keeps this linear; all-pairs would be 10^10 checks per step.
        let particles = try run(count: 100_000, size: 20, frames: 3, flocking: ParticleFlocking())
        #expect(particles.allSatisfy { $0.velocity.x.isFinite && $0.position.x.isFinite })
    }

    /// Each flocking emitter gets its own grid pass, one after another: both flocks align, each on its own.
    @Test func twoFlockingEmittersEachFlock() throws {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .box(size: [1, 1, 1]) }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 1 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(DragModule.self) { $0.amount = 0 }
        emitter.edit(LifetimeModule.self) { $0.range = 100...100 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter[FlockingModule.self] = FlockingModule(flocking: ParticleFlocking(radius: 2, separation: 0, alignment: 3, cohesion: 0, speedRange: 0...10))
        var far = emitter
        far.edit(ShapeModule.self) { $0.position = [20, 0, 0] }
        let layers = [EmitterDescription("A", modules: emitter, capacity: 200), EmitterDescription("B", modules: far, capacity: 200)]
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, modules: .standard, seed: 3)
        try system.apply(layers)
        for emitter in system.emitters {
            emitter.burst(200)
        }
        for _ in 0..<120 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 400)
        let first = system.emitters[0].range.map { pointer[$0] }
        let second = system.emitters[1].range.map { pointer[$0] }
        #expect(order(first) > 0.9)
        #expect(order(second) > 0.9)
    }

    @Test func flockingRoundTripsThroughEffectFiles() throws {
        var emitter = EmitterModules.standard
        emitter[FlockingModule.self] = FlockingModule(flocking: ParticleFlocking(radius: 0.7, separation: 0.1, speedRange: 1...3, maxNeighbors: 12))
        #expect(try roundTrip(emitter)[FlockingModule.self] == emitter[FlockingModule.self])
    }
}
