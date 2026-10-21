import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `ParticleEmitter.constrainsToPlane` keeps particles on the emitter's XY plane.
@Suite(.serialized, .requiresMetal4)
struct PlaneConstraintTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// Particles from a sphere with wide spread, gravity with a z part, and turbulence: everything that adds depth.
    func particles(constrained: Bool, transform: simd_float4x4 = matrix_identity_float4x4, colliders: [Collider] = []) throws -> [Particle] {
        var emitter = ParticleEmitter()
        emitter.shape = .sphere(radius: 0.5)
        emitter.velocity = [0, 1, 1]
        emitter.velocitySpread = 2
        emitter.gravity = [0, -2, 3]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.constrainsToPlane = constrained
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: emitter)
        runtime.emitters[0].transform = transform
        runtime.forceFields = [.turbulence(strength: 4, scale: 1, speed: 1)]
        runtime.colliders = colliders
        runtime.burst(64)
        for _ in 0..<30 {
            try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 64)
        return (0..<64).map { pointer[$0] }
    }

    @Test func particlesStayOnTheZeroPlane() throws {
        let free = try particles(constrained: false)
        let flat = try particles(constrained: true)
        #expect(free.contains { abs($0.position.z) > 0.1 })
        #expect(flat.allSatisfy { abs($0.position.z) < 1e-4 && abs($0.velocity.z) < 1e-4 })
        // Motion within the plane is untouched.
        #expect(flat.contains { abs($0.position.x) > 0.1 } && flat.contains { abs($0.position.y) > 0.1 })
    }

    @Test func thePlaneFollowsTheEmitter() throws {
        // Turned a quarter turn about x and moved up: the plane is y = 2, facing up.
        var transform = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        transform.columns.3 = [0, 2, 0, 1]
        let flat = try particles(constrained: true, transform: transform)
        #expect(flat.allSatisfy { abs($0.position.y - 2) < 1e-4 && abs($0.velocity.y) < 1e-4 })
    }

    @Test func collisionsDoNotPushParticlesOffThePlane() throws {
        // A sphere off to the side of the plane deflects particles partly along z.
        let flat = try particles(constrained: true, colliders: [.sphere(center: [0, 0.6, 0.3], radius: 0.5)])
        #expect(flat.allSatisfy { abs($0.position.z) < 1e-4 })
    }

    @Test func settingRoundTripsAndDefaultsOff() throws {
        var emitter = ParticleEmitter()
        #expect(!emitter.constrainsToPlane)
        emitter.constrainsToPlane = true
        let decoded = try roundTrip(emitter)
        #expect(decoded.constrainsToPlane)
    }
}
