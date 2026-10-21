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
        let emitter = EmitterModules.standard(position: [0, 0.2, 0], shape: .point, velocity: [0.5, 0, 0], spread: 0, gravity: [0, -9.8, 0], lifetime: 10...10, birthRate: 0) {
            $0[RotationModule.self] = RotationModule(angularSpeed: 8)
            $0.edit(CollisionModule.self) {
                $0.restitution = 0
                $0.friction = friction
            }
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, modules: emitter)
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
