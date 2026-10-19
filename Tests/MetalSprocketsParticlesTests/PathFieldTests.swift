import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct PathFieldTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    @Test func polylinePassesThroughTheControlPoints() {
        let points: [SIMD3<Float>] = [[0, 0, 0], [1, 1, 0], [2, 0, 0], [3, 1, 0]]
        let polyline = ForceField.path(points: points, speed: 1).pathPolyline
        #expect(polyline.count == 3 * ForceField.pathSamplesPerSpan + 1)
        for point in points {
            #expect(polyline.contains { simd_distance($0, point) < 1e-5 })
        }
        #expect(ForceField.turbulence(strength: 1).pathPolyline.isEmpty)
    }

    @Test func closedPathsLoopAndLongOnesAreCapped() {
        let square: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]
        #expect(ForceField.path(points: square, speed: 1, closed: true).pathPolyline.count == 4 * ForceField.pathSamplesPerSpan)
        let long = (0..<2_000).map { SIMD3(Float($0), 0, 0) }
        #expect(ForceField.path(points: long, speed: 1).pathPolyline.count <= ForceField.maximumPathPoints)
    }

    /// Particles start beside a straight path along +X; the field pulls them onto it and carries them along.
    @Test func particlesAreCarriedAlongThePath() throws {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [0, 0.5, 0]
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, emitter: emitter)
        system.forceFields = [.path(points: [[-5, 0, 0], [0, 0, 0], [5, 0, 0], [10, 0, 0]], speed: 2, strength: 4)]
        system.burst(16)
        for _ in 0..<120 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        for index in 0..<16 {
            let particle = pointer[index]
            #expect(abs(particle.position.y) < 0.05) // Pulled onto the line.
            #expect(abs(particle.velocity.x - 2) < 0.1) // Moving along it at the field's speed.
            #expect(particle.position.x > 2)
        }
    }

    @Test func outsideTheRadiusNothingHappens() throws {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [0, 3, 0]
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter)
        system.forceFields = [.path(points: [[-5, 0, 0], [5, 0, 0]], speed: 2, strength: 4, radius: 1)]
        system.burst(4)
        for _ in 0..<30 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        #expect((0..<4).allSatisfy { pointer[$0].velocity.x == 0 && pointer[$0].position.y == 3 })
    }

    @Test func pathFieldsRoundTripThroughEffectFiles() throws {
        let field = ForceField.path(points: [[0, 0, 0], [1, 2, 3]], speed: 1.5, strength: 3, radius: 2, closed: true, categoryBitMask: 2)
        #expect(try JSONDecoder().decode(ForceField.self, from: JSONEncoder().encode(field)) == field)
    }
}
