import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

private let deltaTime: Float = 1.0 / 60.0

@Suite(.requiresMetal4)
struct SpawnerTests {
    func totalSpawned(seconds: Float, rate: RateModule, capacity: Int = 1_000_000) -> Int {
        var spawner = Spawner()
        var total = 0
        for _ in 0..<Int((seconds / deltaTime).rounded()) {
            total += Int(spawner.advance(deltaTime: deltaTime, rate: rate, maxLifetime: 3, capacity: capacity, isEmitting: true).count)
        }
        return total
    }

    @Test func birthRateIsIndependentOfCapacity() {
        var rate = RateModule()
        rate.birthRate = 600
        #expect(abs(totalSpawned(seconds: 1, rate: rate) - 600) <= 1)
        #expect(abs(totalSpawned(seconds: 1, rate: rate, capacity: 10_000) - 600) <= 1)
    }

    @Test func fractionalRatesAccumulate() {
        var rate = RateModule()
        rate.birthRate = 3
        #expect(abs(totalSpawned(seconds: 2, rate: rate) - 6) <= 1)
    }

    @Test func emissionDurationWithoutLoopStops() {
        var rate = RateModule()
        rate.birthRate = 600
        rate.emissionDuration = 0.5
        rate.loops = false
        #expect(abs(totalSpawned(seconds: 2, rate: rate) - 300) <= 1)
    }

    @Test func emissionAndIdleCycle() {
        var rate = RateModule()
        rate.birthRate = 600
        rate.emissionDuration = 0.5
        rate.idleDuration = 0.5
        // Two full cycles: 2 × 0.5 s of emission.
        #expect(abs(totalSpawned(seconds: 2, rate: rate) - 600) <= 2)
    }

    @Test func burstAddsToBirthRate() {
        var rate = RateModule()
        rate.birthRate = 0
        var spawner = Spawner()
        spawner.pendingBurst = 250
        #expect(spawner.advance(deltaTime: deltaTime, rate: rate, maxLifetime: 3, capacity: 1_000, isEmitting: true).count == 250)
        #expect(spawner.advance(deltaTime: deltaTime, rate: rate, maxLifetime: 3, capacity: 1_000, isEmitting: true).count == 0)
    }

    @Test func notEmittingStillFiresBursts() {
        var rate = RateModule()
        rate.birthRate = 600
        var spawner = Spawner()
        spawner.pendingBurst = 10
        #expect(spawner.advance(deltaTime: deltaTime, rate: rate, maxLifetime: 3, capacity: 1_000, isEmitting: false).count == 10)
    }

    @Test func cursorWrapsAroundRing() {
        var rate = RateModule()
        rate.birthRate = 60 * 7
        var spawner = Spawner()
        for _ in 0..<3 {
            _ = spawner.advance(deltaTime: deltaTime, rate: rate, maxLifetime: 3, capacity: 10, isEmitting: true)
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

    func makeSystem(_ configure: (inout EmitterModules) -> Void = { _ in }) throws -> ParticleSystemRuntime {
        var emitter = EmitterModules.standard
        emitter.edit(LifetimeModule.self) { $0.range = 5...5 }
        emitter.edit(RateModule.self) { $0.birthRate = 600 }
        configure(&emitter)
        return try ParticleSystemRuntime(device: runner.device, capacity: 10_000, modules: emitter, seed: 3)
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
            $0.edit(LifetimeModule.self) { $0.range = 0.5...0.5 }
            $0.edit(RateModule.self) { $0.emissionDuration = 0.25 }
            $0.edit(RateModule.self) { $0.loops = false }
        }
        try step(system, count: 60)
        #expect(liveCount(system) == 0)
    }

    @Test func burstSpawnsImmediately() throws {
        let system = try makeSystem { $0.edit(RateModule.self) { $0.birthRate = 0 } }
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
        let system = try makeSystem { $0.edit(RateModule.self) { $0.warmupDuration = 1 } }
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
        let system = try makeSystem { $0.edit(RateModule.self) { $0.birthRate = 60_000 } }
        try step(system, count: 30)
        #expect(liveCount(system) == system.capacity)
    }
}
