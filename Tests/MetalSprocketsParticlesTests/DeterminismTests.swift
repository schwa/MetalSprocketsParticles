import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

@Suite(.serialized)
struct DeterminismTests {
    func simulate(seed: UInt32, steps: Int) throws -> [Particle] {
        let runner = try Runner()
        let system = try ParticleSystem(device: runner.device, capacity: 4_096, emitter: .fountain, seed: seed)
        let deltaTime: Float = 1.0 / 60.0
        for _ in 0..<steps {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    @Test func sameSeedGivesIdenticalParticles() throws {
        let first = try simulate(seed: 42, steps: 90)
        let second = try simulate(seed: 42, steps: 90)
        #expect(first == second)
    }

    @Test func differentSeedsGiveDifferentParticles() throws {
        let first = try simulate(seed: 1, steps: 90)
        let second = try simulate(seed: 2, steps: 90)
        #expect(first != second)
    }
}

extension Particle: @retroactive Equatable {
    public static func == (lhs: Particle, rhs: Particle) -> Bool {
        lhs.position == rhs.position && lhs.velocity == rhs.velocity && lhs.color == rhs.color && lhs.rotation == rhs.rotation
    }
}
