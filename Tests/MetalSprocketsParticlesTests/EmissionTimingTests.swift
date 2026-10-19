import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

private let deltaTime: Float = 1.0 / 60.0

@Suite(.requiresMetal4)
struct SpawnerTests {
    func totalSpawned(seconds: Float, emitter: ParticleEmitter, capacity: Int = 1_000_000) -> Int {
        var spawner = Spawner()
        var total = 0
        for _ in 0..<Int((seconds / deltaTime).rounded()) {
            total += Int(spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: capacity, isEmitting: true).count)
        }
        return total
    }

    @Test func birthRateIsIndependentOfCapacity() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 600
        #expect(abs(totalSpawned(seconds: 1, emitter: emitter) - 600) <= 1)
        #expect(abs(totalSpawned(seconds: 1, emitter: emitter, capacity: 10_000) - 600) <= 1)
    }

    @Test func fractionalRatesAccumulate() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 3
        #expect(abs(totalSpawned(seconds: 2, emitter: emitter) - 6) <= 1)
    }

    @Test func emissionDurationWithoutLoopStops() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 600
        emitter.emissionDuration = 0.5
        emitter.loops = false
        #expect(abs(totalSpawned(seconds: 2, emitter: emitter) - 300) <= 1)
    }

    @Test func emissionAndIdleCycle() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 600
        emitter.emissionDuration = 0.5
        emitter.idleDuration = 0.5
        // Two full cycles: 2 × 0.5 s of emission.
        #expect(abs(totalSpawned(seconds: 2, emitter: emitter) - 600) <= 2)
    }

    @Test func burstAddsToBirthRate() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 0
        var spawner = Spawner()
        spawner.pendingBurst = 250
        #expect(spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: 1_000, isEmitting: true).count == 250)
        #expect(spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: 1_000, isEmitting: true).count == 0)
    }

    @Test func notEmittingStillFiresBursts() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 600
        var spawner = Spawner()
        spawner.pendingBurst = 10
        #expect(spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: 1_000, isEmitting: false).count == 10)
    }

    @Test func cursorWrapsAroundRing() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 60 * 7
        var spawner = Spawner()
        for _ in 0..<3 {
            _ = spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: 10, isEmitting: true)
        }
        #expect(spawner.cursor == 21 % 10)
        #expect(spawner.serial == 21)
    }
}

@Suite(.serialized, .requiresMetal4)
struct EmissionGPUTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func makeSystem(_ configure: (inout ParticleEmitter) -> Void = { _ in }) throws -> ParticleSystemRuntime {
        var emitter = ParticleEmitter()
        emitter.lifetime = 5...5
        emitter.birthRate = 600
        configure(&emitter)
        return try ParticleSystemRuntime(device: runner.device, capacity: 10_000, emitter: emitter, seed: 3)
    }

    func step(_ system: ParticleSystemRuntime, count: Int = 1) throws {
        for _ in 0..<count {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func particles(_ system: ParticleSystemRuntime) -> [Particle] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    func liveCount(_ system: ParticleSystemRuntime) -> Int {
        particles(system).filter { $0.velocity.w > 0 && $0.position.w < $0.velocity.w }.count
    }

    @Test func liveCountFollowsBirthRate() throws {
        let system = try makeSystem()
        try step(system, count: 60)
        #expect(abs(liveCount(system) - 600) <= 1)
    }

    @Test func particlesDieAfterLifetime() throws {
        let system = try makeSystem {
            $0.lifetime = 0.5...0.5
            $0.emissionDuration = 0.25
            $0.loops = false
        }
        try step(system, count: 60)
        #expect(liveCount(system) == 0)
    }

    @Test func burstSpawnsImmediately() throws {
        let system = try makeSystem { $0.birthRate = 0 }
        system.burst(123)
        try step(system)
        #expect(liveCount(system) == 123)
    }

    @Test func pauseFreezesParticles() throws {
        let system = try makeSystem()
        try step(system, count: 10)
        system.state = .paused
        let before = particles(system)
        try step(system, count: 10)
        #expect(particles(system) == before)
    }

    @Test func stopRemovesParticlesAndPlayRestarts() throws {
        let system = try makeSystem()
        try step(system, count: 30)
        system.state = .stopped
        try step(system, count: 5)
        #expect(liveCount(system) == 0)
        system.state = .playing
        try step(system, count: 30)
        #expect(abs(liveCount(system) - 300) <= 1)
    }

    @Test func notEmittingKeepsExistingParticles() throws {
        let system = try makeSystem()
        try step(system, count: 30)
        system.isEmitting = false
        try step(system, count: 30)
        #expect(abs(liveCount(system) - 300) <= 1)
    }

    @Test func warmupPreSimulatesOnFirstFrame() throws {
        let system = try makeSystem { $0.warmupDuration = 1 }
        try step(system)
        // One second of warmup plus one frame.
        #expect(abs(liveCount(system) - 610) <= 2)
    }

    @Test func speedFactorScalesTime() throws {
        let system = try makeSystem()
        system.speedFactor = 2
        try step(system, count: 30)
        #expect(abs(liveCount(system) - 600) <= 1)
    }

    @Test func fullRingRecyclesOldestParticles() throws {
        let system = try makeSystem { $0.birthRate = 60_000 }
        try step(system, count: 30)
        #expect(liveCount(system) == system.capacity)
    }
}
