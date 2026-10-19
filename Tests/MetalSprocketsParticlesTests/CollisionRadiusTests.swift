import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `ParticleEmitter.collisionRadius`: particles collide as spheres, so big ones rest on colliders (#126).
@Suite(.serialized)
struct CollisionRadiusTests {
    /// Final positions of particles dropped straight down from `start` onto `collider`.
    func rest(radius: Float, on collider: Collider, from start: SIMD3<Float> = [0, 1, 0]) throws -> [SIMD3<Float>] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = start
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0
        emitter.friction = 1
        emitter.collisionRadius = radius
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter)
        system.colliders = [collider]
        system.burst(4)
        for _ in 0..<120 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
        return (0..<4).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    @Test func pointsRestOnTheSurface() throws {
        let landed = try rest(radius: 0, on: .plane(normal: [0, 1, 0], distance: 0))
        #expect(landed.allSatisfy { abs($0.y) < 0.02 })
    }

    @Test func spheresRestOneRadiusAboveAFloor() throws {
        let landed = try rest(radius: 0.1, on: .plane(normal: [0, 1, 0], distance: 0))
        #expect(landed.allSatisfy { abs($0.y - 0.1) < 0.02 })
    }

    @Test func spheresRestOnSpheres() throws {
        let landed = try rest(radius: 0.1, on: .sphere(center: [0, 0, 0], radius: 0.5), from: [0, 2, 0])
        #expect(landed.allSatisfy { abs(simd_length($0) - 0.6) < 0.02 })
    }

    @Test func spheresRestOnBoxes() throws {
        let landed = try rest(radius: 0.1, on: .box(center: .zero, halfExtents: [1, 0.25, 1]), from: [0, 2, 0])
        #expect(landed.allSatisfy { abs($0.y - 0.35) < 0.02 })
    }

    @Test func collisionRadiusRoundTripsThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.collisionRadius = 0.07
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).collisionRadius == 0.07)
    }
}
