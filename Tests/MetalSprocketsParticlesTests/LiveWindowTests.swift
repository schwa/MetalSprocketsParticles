import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

/// The system only simulates and draws the ring slots that can hold live particles. These check that no live particle
/// ever falls outside that window, and that particles leaving it are stored as dead.
@Suite(.serialized)
struct LiveWindowTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    func makeSystem(capacity: Int = 2_000, configure: (inout ParticleEmitter) -> Void = { _ in }) throws -> ParticleSystem {
        var emitter = ParticleEmitter()
        emitter.velocity = .zero
        emitter.velocitySpread = 0.5
        emitter.gravity = .zero
        emitter.lifetime = 1...2
        emitter.birthRate = 300
        configure(&emitter)
        return try ParticleSystem(device: runner.device, capacity: capacity, emitter: emitter, seed: 4)
    }

    func step(_ system: ParticleSystem, seconds: Float) throws {
        for _ in 0..<Int((seconds / deltaTime).rounded()) {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func aliveSlots(_ system: ParticleSystem) -> [Int] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity).filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }
    }

    func windowSlots(_ system: ParticleSystem) -> Set<Int> {
        let emitter = system.emitters[0]
        let window = emitter.liveWindow
        return Set((0..<window.count).map { (window.start + $0) % emitter.capacity })
    }

    @Test func aliveParticlesStayInsideTheWindow() throws {
        let system = try makeSystem()
        for _ in 0..<12 {
            try step(system, seconds: 0.25)
            let window = windowSlots(system)
            #expect(aliveSlots(system).allSatisfy { window.contains($0) })
        }
        // At 300 per second and at most 2 s of life, the window is far smaller than the 2,000-slot ring.
        #expect(windowSlots(system).count < 800)
    }

    @Test func windowEmptiesAfterEmissionStops() throws {
        let system = try makeSystem()
        try step(system, seconds: 1)
        system.isEmitting = false
        try step(system, seconds: 2.5)
        #expect(aliveSlots(system).isEmpty)
        #expect(system.emitters[0].liveWindow.count == 0)
    }

    @Test func loweringLifetimeLeavesNoFrozenParticles() throws {
        let system = try makeSystem { $0.lifetime = 5...5 }
        try step(system, seconds: 1)
        system.emitter.lifetime = 0.2...0.2
        system.isEmitting = false
        try step(system, seconds: 6)
        // Particles born with a 5 s lifetime must have been simulated until they died, not dropped from the window.
        #expect(aliveSlots(system).isEmpty)
    }

    @Test func raisingLifetimeDoesNotRevealOldParticles() throws {
        let system = try makeSystem { $0.lifetime = 0.5...0.5 }
        try step(system, seconds: 2)
        system.emitter.lifetime = 4...4
        system.isEmitting = false
        // Past the old 0.5 s lifetime, every particle is dead, even though the 4 s window now reaches back over slots
        // that died long ago.
        try step(system, seconds: 0.6)
        #expect(system.emitters[0].liveWindow.count > 0)
        #expect(aliveSlots(system).isEmpty)
    }

    @Test func burstsLargerThanTheWindowAreCovered() throws {
        let system = try makeSystem { $0.birthRate = 10 }
        try step(system, seconds: 0.5)
        system.burst(1_500)
        try step(system, seconds: deltaTime)
        let window = windowSlots(system)
        let alive = aliveSlots(system)
        #expect(alive.count >= 1_500)
        #expect(alive.allSatisfy { window.contains($0) })
    }

    @Test func restartClearsEverythingIncludingOutsideTheWindow() throws {
        let system = try makeSystem()
        try step(system, seconds: 1)
        system.restart()
        system.isEmitting = false
        try step(system, seconds: deltaTime)
        #expect(aliveSlots(system).isEmpty)
    }
}
