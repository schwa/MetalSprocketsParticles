import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ParticleEventTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func dropper(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [0, 1, 0]
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0.5
        configure(&emitter)
        return emitter
    }

    /// Runs `frames` steps, collecting every event; each `runner.run` waits for the GPU, so one more step reads the last.
    func events(_ system: ParticleSystemRuntime, frames: Int) throws -> [ParticleEvent] {
        var events: [ParticleEvent] = []
        for _ in 0...frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
            events += system.recentEvents
        }
        return events
    }

    @Test func collisionsReportWhereWhichColliderAndHowFast() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, emitter: dropper { $0.reportsCollisions = true })
        system.colliders = [.sphere(center: [0, 50, 0], radius: 0.1), .plane(normal: [0, 1, 0], distance: 0)]
        system.burst(16)
        let events = try events(system, frames: 40)
        let first = try #require(events.first)
        #expect(first.kind == .collision(colliderIndex: 1))
        #expect(abs(first.position.y) < 0.05)
        #expect(first.velocity.y > 0) // After the bounce.
        #expect(first.emitterIndex == 0)
        // Every particle lands (and bounces again, so there are more events than particles).
        #expect(events.count >= 16)
        #expect(events.allSatisfy { $0.kind == .collision(colliderIndex: 1) })
    }

    @Test func deathsAreReportedOncePerParticle() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 32, emitter: dropper {
            $0.reportsDeaths = true
            $0.lifetime = 0.1...0.1
        })
        system.burst(32)
        let events = try events(system, frames: 20)
        #expect(events.count == 32)
        #expect(events.allSatisfy { $0.kind == .death })
    }

    @Test func emittersThatDoNotReportStayQuiet() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, emitter: dropper { $0.lifetime = 0.1...0.1 })
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        system.burst(16)
        #expect(try events(system, frames: 40).isEmpty)
    }

    @Test func overflowDropsTheOldestAndCountsThem() throws {
        let count = ParticleEvent.capacity + 100
        let system = try ParticleSystemRuntime(device: runner.device, capacity: count, emitter: dropper {
            $0.reportsDeaths = true
            $0.lifetime = 0.01...0.01
        })
        system.burst(count)
        let events = try events(system, frames: 3)
        // Births spread over the step, so deaths land over two frames; whatever did not fit is counted, not lost silently.
        #expect(events.count <= 2 * ParticleEvent.capacity)
        #expect(events.count + system.droppedEventCount == count)
    }
}
