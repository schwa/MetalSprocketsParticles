import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `CollisionModule.radius`: particles collide as spheres, so big ones rest on colliders (#126).
@Suite(.serialized, .requiresMetal4)
struct CollisionRadiusTests {
    /// Final positions of particles dropped straight down from `start` onto `collider`.
    func rest(radius: Float, on collider: Collider, from start: SIMD3<Float> = [0, 1, 0]) throws -> [SIMD3<Float>] {
        let runner = try Runner()
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(ShapeModule.self) { $0.position = start }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = [0, -9.8, 0] }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter.edit(CollisionModule.self) { $0.restitution = 0 }
        emitter.edit(CollisionModule.self) { $0.friction = 1 }
        emitter.edit(CollisionModule.self) { $0.radius = radius }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, modules: emitter)
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
        var emitter = EmitterModules.standard
        emitter.edit(CollisionModule.self) { $0.radius = 0.07 }
        #expect(try roundTrip(emitter)[CollisionModule.self]?.radius == 0.07)
    }
}
