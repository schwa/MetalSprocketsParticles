import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `ParticleState.color`, `size`, and `custom` in user functions.
@Suite(.serialized, .requiresMetal4)
struct ParticleStateAttributeTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func function(_ name: String, _ body: String) -> ParticleFunction {
        ParticleFunction(source: """
        [[visible]] void \(name)(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            \(body)
        }
        """, name: name)
    }

    func emitter(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.sizeVariation = 0
        configure(&emitter)
        return emitter
    }

    func run(_ system: ParticleSystemRuntime, burst: Int = 8, frames: Int) throws -> [Particle] {
        system.burst(burst)
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<burst).map { pointer[$0] }
    }

    @Test func customPersistsBetweenSteps() throws {
        // Counts steps in custom.x and moves the particle up by the count, so the result shows custom survived.
        let counter = function("countSteps", "particle.custom.x += 1; particle.position = float3(0, particle.custom.x, 0);")
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter { $0.updateFunction = counter })
        let particles = try run(system, frames: 5)
        // The burst's first step also runs the update, so 5 frames are 5 updates.
        #expect(particles.allSatisfy { $0.position.y == 5 })
        let attributes = try #require(system.attributes).contents().bindMemory(to: SIMD4<Float>.self, capacity: 8)
        #expect(attributes[0].x == 5)
    }

    @Test func customStartsAtZeroForReusedSlots() throws {
        let counter = function("countSteps", "particle.custom.x += 1; if (particle.custom.x >= 3) { particle.age = particle.lifetime; }")
        let record = function("recordCustom", "particle.position = float3(particle.custom.x, 0, 0);")
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter {
            $0.updateFunction = counter
            $0.spawnFunction = record
        })
        // First generation counts to 3 and dies; the second is born into the same slots and must see 0 at spawn.
        _ = try run(system, burst: 4, frames: 4)
        let particles = try run(system, burst: 4, frames: 0)
        #expect(particles.allSatisfy { $0.position.x == 0 })
    }

    @Test func colorAndSizeWriteThrough() throws {
        let paint = function("paint", "particle.color = float4(1, 0, 0, 1); particle.size = 2.5;")
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter { $0.updateFunction = paint })
        let particles = try run(system, frames: 1)
        #expect(particles.allSatisfy { $0.properties.w.bitPattern == 0xFF00_00FF })
        #expect(particles.allSatisfy { $0.properties.x == 2.5 })
    }

    @Test func colorStartsAsWhiteAndLeavingItAloneKeepsNoTint() throws {
        // Reads the starting color into velocity, so the test can see it.
        let read = function("readColor", "particle.velocity = particle.color.xyz * particle.color.w;")
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter { $0.updateFunction = read })
        let particles = try run(system, frames: 1)
        #expect(particles.allSatisfy { $0.velocity.x == 1 && $0.velocity.y == 1 && $0.velocity.z == 1 })
        #expect(particles.allSatisfy { $0.properties.w.bitPattern == 0 })
    }

    @Test func extraAttributesPersistWhenTheEmitterAsksForThem() throws {
        // Counts steps in custom1.x and twice the steps in custom2.y, and shows them in the position.
        let counter = function("countMore", "particle.custom1.x += 1; particle.custom2.y += 2; particle.position = float3(particle.custom1.x, particle.custom2.y, 0);")
        let kept = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter {
            $0.updateFunction = counter
            $0.customAttributeCount = 3
        })
        let particles = try run(kept, frames: 5)
        #expect(particles.allSatisfy { $0.position.x == 5 && $0.position.y == 10 })
        #expect(kept.attributeStride == 3)
        #expect(try #require(kept.attributes).length == kept.capacity * 3 * 16)

        // With the default of one, custom1 and custom2 start from zero every step.
        let notKept = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter { $0.updateFunction = counter })
        #expect(try run(notKept, frames: 5).allSatisfy { $0.position.x == 1 && $0.position.y == 2 })
        #expect(notKept.attributeStride == 1)
    }

    @Test func systemsWithoutFunctionsDoNotAllocateAttributes() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: emitter { _ in })
        _ = try run(system, frames: 2)
        #expect(system.attributes == nil)
    }
}
