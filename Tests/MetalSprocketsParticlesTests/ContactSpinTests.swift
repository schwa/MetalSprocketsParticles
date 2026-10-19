import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

/// Contact friction slows spin as well as sliding (#132).
@Suite(.serialized, .requiresMetal4)
struct ContactSpinTests {
    func spin(afterFalling frames: Int, friction: Float, floor: Bool) throws -> [Float] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [0, 0.2, 0]
        emitter.velocity = [0.5, 0, 0]
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.angularSpeed = 8
        emitter.angularSpeedVariation = 0
        emitter.restitution = 0
        emitter.friction = friction
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter)
        system.colliders = floor ? [.plane(normal: [0, 1, 0], distance: 0)] : []
        system.burst(8)
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 8)
        return (0..<8).map { pointer[$0].rotation.y }
    }

    @Test func restingParticlesStopSpinning() throws {
        let spins = try spin(afterFalling: 120, friction: 0.3, floor: true)
        #expect(spins.allSatisfy { abs($0) < 0.1 })
    }

    @Test func frictionlessContactKeepsSpin() throws {
        let spins = try spin(afterFalling: 120, friction: 0, floor: true)
        #expect(spins.allSatisfy { abs($0 - 8) < 1e-4 })
    }

    @Test func particlesInTheAirKeepSpinning() throws {
        let spins = try spin(afterFalling: 30, friction: 0.3, floor: false)
        #expect(spins.allSatisfy { abs($0 - 8) < 1e-4 })
    }
}
