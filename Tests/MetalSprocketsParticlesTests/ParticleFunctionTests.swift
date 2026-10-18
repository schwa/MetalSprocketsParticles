import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// User Metal functions (`ParticleEmitter.updateFunction`) compiled at runtime and called from the simulation kernel.
@Suite(.serialized)
struct ParticleFunctionTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// Sets velocity to parameters[0].xyz every step.
    let setVelocity = ParticleFunction(source: """
    [[visible]] void setVelocity(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
        particle.velocity = parameters[0].xyz;
    }
    """, name: "setVelocity", parameters: [[0, 5, 0, 0]])

    func fallingEmitter(_ configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        configure(&emitter)
        return emitter
    }

    /// Velocities of every particle after bursting `count` per emitter and running `frames` steps.
    func velocities(_ system: ParticleSystem, count: Int, frames: Int = 30) throws -> [[SIMD3<Float>]] {
        for emitter in system.emitters {
            emitter.burst(count)
        }
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return system.emitters.map { emitter in
            emitter.range.prefix(count).map { SIMD3(pointer[$0].velocity.x, pointer[$0].velocity.y, pointer[$0].velocity.z) }
        }
    }

    @Test func updateFunctionAppliesOnlyToItsEmitter() throws {
        let lifted = fallingEmitter { $0.updateFunction = setVelocity }
        let system = try ParticleSystem(device: runner.device, emitters: [lifted, fallingEmitter()], capacity: 32)
        let result = try velocities(system, count: 16)
        // Gravity is applied before the function, so the function wins; the other emitter just falls.
        #expect(result[0].allSatisfy { simd_distance($0, [0, 5, 0]) < 1e-4 })
        #expect(result[1].allSatisfy { $0.y < -4 })
    }

    @Test func parametersReachTheFunction() throws {
        var function = setVelocity
        function.parameters = [[2, 0, -3, 0]]
        let system = try ParticleSystem(device: runner.device, capacity: 16, emitter: fallingEmitter { $0.updateFunction = function })
        let result = try velocities(system, count: 16)
        #expect(result[0].allSatisfy { simd_distance($0, [2, 0, -3]) < 1e-4 })
    }

    @Test func compileErrorsThrowFromSimulate() throws {
        let broken = ParticleFunction(source: "[[visible]] void broken(thread ParticleState &particle) { oops; }", name: "broken")
        let system = try ParticleSystem(device: runner.device, capacity: 16, emitter: fallingEmitter { $0.updateFunction = broken })
        #expect(throws: (any Error).self) {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
    }

    @Test func updateFunctionRoundTripsThroughJSON() throws {
        let emitter = fallingEmitter { $0.updateFunction = setVelocity }
        let decoded = try JSONDecoder().decode(ParticleEmitter.self, from: try JSONEncoder().encode(emitter))
        #expect(decoded.updateFunction == setVelocity)
        let plain = try JSONDecoder().decode(ParticleEmitter.self, from: try JSONEncoder().encode(fallingEmitter()))
        #expect(plain.updateFunction == nil)
    }
}
