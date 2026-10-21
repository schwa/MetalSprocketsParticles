import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

@Suite(.serialized, .requiresMetal4)
struct DeterminismTests {
    func simulate(seed: UInt32, steps: Int) throws -> [Particle] {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4_096, modules: .fountain, seed: seed)
        system.colliders = Collider.fountain(time: 0)
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

    func simulateSubStepped(seed: UInt32, frames: Int, stepsPerFrame: Int) throws -> [Particle] {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4_096, modules: .fountain, seed: seed)
        system.colliders = Collider.fountain(time: 0)
        let deltaTime: Float = 1.0 / 60.0
        for _ in 0..<frames {
            let steps = try (0..<stepsPerFrame).map { _ in try system.simulate(deltaTime: deltaTime) }
            try runner.run(ForEach(Array(steps.indices), id: \.self) { steps[$0] })
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    @Test(arguments: [2, 4, 8, 16])
    func subSteppingMatchesOneStepPerSubmission(stepsPerFrame: Int) throws {
        let reference = try simulate(seed: 42, steps: 8 * stepsPerFrame)
        for _ in 0..<3 {
            #expect(try simulateSubStepped(seed: 42, frames: 8, stepsPerFrame: stepsPerFrame) == reference)
        }
    }

    @Test func differentSeedsGiveDifferentParticles() throws {
        let first = try simulate(seed: 1, steps: 90)
        let second = try simulate(seed: 2, steps: 90)
        #expect(first != second)
    }
}

extension Particle: @retroactive Equatable {
    public static func == (lhs: Particle, rhs: Particle) -> Bool {
        lhs.position == rhs.position && lhs.velocity == rhs.velocity && lhs.color == rhs.color && lhs.rotation == rhs.rotation && lhs.properties == rhs.properties
    }
}
