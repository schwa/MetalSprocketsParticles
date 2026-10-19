import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct FlockingTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// `count` particles in a box of `size` with random directions at speed about 1, run for `frames` steps.
    func run(count: Int, size: Float, frames: Int, flocking: ParticleFlocking?) throws -> [Particle] {
        var emitter = ParticleEmitter()
        emitter.shape = .box(size: [size, size, size])
        emitter.velocity = .zero
        emitter.velocitySpread = 1
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 100...100
        emitter.birthRate = 0
        emitter.flocking = flocking
        let system = try ParticleSystemRuntime(device: runner.device, capacity: count, emitter: emitter, seed: 3)
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

    @Test func flockingRoundTripsThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.flocking = ParticleFlocking(radius: 0.7, separation: 0.1, speedRange: 1...3, maxNeighbors: 12)
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).flocking == emitter.flocking)
    }
}
