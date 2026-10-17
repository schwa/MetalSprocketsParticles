import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

@Suite(.serialized)
struct MovingColliderTests {
    // Particles sit still at the origin; a sphere sweeps through them along +x.
    func sweep(speed: Float) throws -> [Particle] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0
        emitter.friction = 0
        let deltaTime: Float = 1.0 / 60.0
        var center: SIMD3<Float> = [-1, 0, 0]
        let system = try ParticleSystem(device: runner.device, capacity: 64, emitter: emitter, seed: 1)
        system.colliders = [.sphere(center: center, radius: 0.5)]
        system.burst(64)
        for _ in 0..<30 {
            center.x += speed * deltaTime
            system.colliders = [.sphere(center: center, radius: 0.5)]
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    @Test func movingSphereTransfersVelocity() throws {
        let particles = try sweep(speed: 6)
        // With zero restitution, struck particles leave at the sphere's speed along the contact normal (+x here).
        let meanVelocityX = particles.map(\.velocity.x).reduce(0, +) / Float(particles.count)
        #expect(meanVelocityX > 5)
        #expect(meanVelocityX < 7)
    }

    @Test func stationaryCollidersHaveNoVelocity() throws {
        let particles = try sweep(speed: 0)
        #expect(particles.allSatisfy { $0.velocity.x == 0 && $0.velocity.y == 0 && $0.velocity.z == 0 })
    }
}
