import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

/// `ParticleSystemRuntime.aliveParticleCount` is counted on the GPU and read a few frames late.
@Suite(.serialized, .requiresMetal4)
struct AliveCountTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func readback(_ system: ParticleSystemRuntime) -> Int {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity).filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
    }

    @Test func matchesAReadbackFromFiveFramesEarlier() throws {
        var emitter = EmitterModules.standard
        emitter.edit(RateModule.self) { $0.birthRate = 300 }
        emitter.edit(LifetimeModule.self) { $0.range = 0.2...0.6 }
        // Warmup adds extra steps on the first frame; each emitter must still be counted once per frame.
        emitter.edit(RateModule.self) { $0.warmupDuration = 0.5 }
        emitter[SubEmittersModule.self] = SubEmittersModule(emitters: [SubEmitter(occasion: .onDeath, countPerEvent: 2, modules: .standard)])
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 500, modules: emitter)
        var counts: [Int] = []
        for _ in 0..<40 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
            counts.append(readback(system))
        }
        // The 41st plan reads the slot written by frame 36 (index 35).
        _ = try system.planFrame(deltaTime: 1.0 / 60.0)
        let slots = Int(PARTICLE_ALIVE_COUNTER_SLOTS)
        #expect(system.aliveParticleCount == counts[counts.count - slots])
        #expect(system.aliveParticleCount > 50)
    }

    @Test func zeroUntilEnoughFramesHaveRun() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 100, modules: .standard)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        #expect(system.aliveParticleCount == 0)
    }
}
