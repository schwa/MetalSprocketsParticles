import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

@Suite(.serialized)
struct RotationTests {
    func simulate(steps: Int, configure: (inout ParticleEmitter) -> Void) throws -> [Particle] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        configure(&emitter)
        let system = try ParticleSystem(device: runner.device, capacity: 256, emitter: emitter, seed: 11)
        system.burst(256)
        for _ in 0..<steps {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    @Test func defaultsDoNotRotate() throws {
        let particles = try simulate(steps: 30) { _ in }
        #expect(particles.allSatisfy { $0.rotation.x == 0 && $0.rotation.y == 0 })
    }

    @Test func initialAngleWithinVariation() throws {
        let particles = try simulate(steps: 1) {
            $0.angle = 1
            $0.angleVariation = 0.25
        }
        #expect(particles.allSatisfy { $0.rotation.x >= 0.75 && $0.rotation.x <= 1.25 })
        // Variation actually varies.
        #expect(Set(particles.map(\.rotation.x)).count > 100)
    }

    @Test func spinAccumulatesWithAge() throws {
        let particles = try simulate(steps: 60) {
            $0.angularSpeed = 2
        }
        for particle in particles {
            let age = particle.position.w
            #expect(abs(particle.rotation.x - 2 * age) < 1e-3)
            #expect(particle.rotation.y == 2)
        }
    }

    @Test func angularSpeedWithinVariation() throws {
        let particles = try simulate(steps: 1) {
            $0.angularSpeed = -3
            $0.angularSpeedVariation = 1
        }
        #expect(particles.allSatisfy { $0.rotation.y >= -4 && $0.rotation.y <= -2 })
    }
}
