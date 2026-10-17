import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct TriggerTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    /// An emitter that only emits when a trigger tells it to.
    func quiet(_ triggers: [EmissionTrigger], configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.triggers = triggers
        configure(&emitter)
        return emitter
    }

    func step(_ system: ParticleSystem, frames: Int = 1) throws {
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func aliveCount(_ system: ParticleSystem, _ emitter: ParticleSystem.Emitter) -> Int {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return emitter.range.filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
    }

    @Test func namedEventBursts() throws {
        let system = try ParticleSystem(device: runner.device, capacity: 100, emitter: quiet([EmissionTrigger(.event("boom"), .burst(7))]))
        try step(system, frames: 3)
        #expect(aliveCount(system, system.emitters[0]) == 0)
        system.send(event: "boom")
        system.send(event: "other")
        try step(system)
        #expect(aliveCount(system, system.emitters[0]) == 7)
        system.send(event: "boom")
        system.send(event: "boom")
        try step(system)
        #expect(aliveCount(system, system.emitters[0]) == 21)
    }

    @Test func afterFiresOnceAndEveryRepeats() throws {
        let system = try ParticleSystem(device: runner.device, emitters: [
            quiet([EmissionTrigger(.after(seconds: 0.5), .burst(1))]),
            quiet([EmissionTrigger(.every(seconds: 0.25), .burst(1))]),
        ], capacity: 100)
        try step(system, frames: 29)
        #expect(aliveCount(system, system.emitters[0]) == 0)
        try step(system, frames: 37)
        // 1.1 s in: after(0.5) fired once; every(0.25) fired at 0.25, 0.5, 0.75, and 1.0. (Not checked exactly at 1.0 s:
        // summed frame times land a hair either side of it.)
        #expect(aliveCount(system, system.emitters[0]) == 1)
        #expect(aliveCount(system, system.emitters[1]) == 4)
    }

    @Test func objectEnteringAVolumeFiresOncePerEntry() throws {
        let volume = TriggerVolume.sphere(center: .zero, radius: 1)
        let system = try ParticleSystem(device: runner.device, capacity: 100, emitter: quiet([EmissionTrigger(.objectEnters(name: "ball", volume: volume), .burst(2))]))
        system.trackedObjects["ball"] = [3, 0, 0]
        try step(system)
        system.trackedObjects["ball"] = [0.5, 0, 0]
        try step(system, frames: 5)
        #expect(aliveCount(system, system.emitters[0]) == 2)
        system.trackedObjects["ball"] = [3, 0, 0]
        try step(system)
        system.trackedObjects["ball"] = [0, 0, 0]
        try step(system)
        #expect(aliveCount(system, system.emitters[0]) == 4)
    }

    @Test func particlesEnteringAVolumeTriggerAnotherEmitter() throws {
        // A stream moving +x crosses a box at x = 1; the second emitter bursts when the first particle arrives.
        let stream = quiet([]) {
            $0.velocity = [2, 0, 0]
            $0.birthRate = 30
        }
        let gate = TriggerVolume.box(center: [1, 0, 0], halfExtents: [0.1, 1, 1])
        let system = try ParticleSystem(device: runner.device, emitters: [stream, quiet([EmissionTrigger(.particlesEnter(volume: gate), .burst(5))])], capacity: 200)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) >= 5)
    }

    @Test func particlesEnterThresholdAccumulates() throws {
        let stream = quiet([]) {
            $0.velocity = [2, 0, 0]
            $0.birthRate = 30
        }
        let gate = TriggerVolume.box(center: [1, 0, 0], halfExtents: [0.1, 1, 1])
        let system = try ParticleSystem(device: runner.device, emitters: [stream, quiet([EmissionTrigger(.particlesEnter(volume: gate, count: 10), .burst(1))])], capacity: 200)
        // The stream reaches the gate after 0.45 s and delivers 30 particles per second. At 0.67 s about 6 have
        // entered (no burst); at 0.92 s about 14 (one burst per 10).
        try step(system, frames: 40)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 15)
        #expect(aliveCount(system, system.emitters[1]) == 1)
    }

    @Test func colliderHitTriggers() throws {
        let falling = quiet([]) {
            $0.position = [0, 1, 0]
            $0.velocity = [0, -3, 0]
            $0.restitution = 0
        }
        let system = try ParticleSystem(device: runner.device, emitters: [falling, quiet([EmissionTrigger(.colliderHit(index: 1), .burst(3))])], capacity: 50)
        system.colliders = [.sphere(center: [5, 0, 0], radius: 0.5), .plane(normal: [0, 1, 0], distance: 0)]
        system.emitters[0].burst(1)
        try step(system, frames: 10)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) >= 3)
    }

    @Test func startAndStopActions() throws {
        var emitter = quiet([EmissionTrigger(.event("on"), .start), EmissionTrigger(.event("off"), .stop)]) {
            $0.birthRate = 60
        }
        emitter.lifetime = 10...10
        let system = try ParticleSystem(device: runner.device, capacity: 500, emitter: emitter)
        system.isEmitting = false
        try step(system, frames: 10)
        #expect(aliveCount(system, system.emitters[0]) == 0)
        system.send(event: "on")
        try step(system, frames: 30)
        let running = aliveCount(system, system.emitters[0])
        #expect(running > 25)
        system.send(event: "off")
        try step(system, frames: 30)
        #expect(aliveCount(system, system.emitters[0]) == running + 1 || aliveCount(system, system.emitters[0]) == running)
    }

    @Test func restartResetsTimers() throws {
        let system = try ParticleSystem(device: runner.device, capacity: 10, emitter: quiet([EmissionTrigger(.after(seconds: 0.1), .burst(1))]))
        try step(system, frames: 10)
        #expect(aliveCount(system, system.emitters[0]) == 1)
        system.restart()
        try step(system, frames: 10)
        #expect(aliveCount(system, system.emitters[0]) == 1)
        #expect(system.simulationTime < 0.2)
    }
}
