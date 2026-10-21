import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

@Suite(.serialized, .requiresMetal4)
struct DieOnCollisionTests {
    /// Particles dropped from y = 1 onto a floor, alive count after `steps` steps.
    func aliveAfterFalling(diesOnCollision: Bool, steps: Int, colliders: [Collider] = [.plane(normal: [0, 1, 0], distance: 0)]) throws -> Int {
        let runner = try Runner()
        let emitter = EmitterModules.standard(position: [0, 1, 0], shape: .sphere(radius: 0.1), velocity: .zero, spread: 0, lifetime: 10...10, birthRate: 0) {
            $0.edit(CollisionModule.self) { $0.diesOnCollision = diesOnCollision }
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 64, modules: emitter, seed: 3)
        system.colliders = colliders
        system.burst(64)
        for _ in 0..<steps {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return UnsafeBufferPointer(start: pointer, count: system.capacity).filter { $0.velocity.w > 0 && $0.position.w < $0.velocity.w }.count
    }

    @Test func particlesDieWhenTheyHitACollider() throws {
        // A 1.1 m fall takes about 0.47 s; 60 steps is a full second.
        #expect(try aliveAfterFalling(diesOnCollision: true, steps: 60) == 0)
    }

    @Test func particlesSurviveBeforeContact() throws {
        #expect(try aliveAfterFalling(diesOnCollision: true, steps: 10) == 64)
    }

    @Test func particlesBounceByDefault() throws {
        #expect(try aliveAfterFalling(diesOnCollision: false, steps: 60) == 64)
    }

    @Test func noCollidersNoDeaths() throws {
        #expect(try aliveAfterFalling(diesOnCollision: true, steps: 60, colliders: []) == 64)
    }
}
