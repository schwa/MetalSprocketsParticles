import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct TriggerTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    /// An emitter that only emits when a trigger tells it to.
    func quiet(_ triggers: [EmissionTrigger], configure: (inout EmitterModules) -> Void = { _ in }) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter[TriggersModule.self] = triggers.isEmpty ? nil : TriggersModule(triggers: triggers)
        configure(&emitter)
        return emitter
    }

    func step(_ system: ParticleSystemRuntime, frames: Int = 1) throws {
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func aliveCount(_ system: ParticleSystemRuntime, _ emitter: ParticleSystemRuntime.Emitter) -> Int {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return emitter.range.filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
    }

    // Event, timer, object, start/stop, and restart triggers are CPU only; FramePlanTests covers them. These need the
    // GPU's counters, or check that a trigger's burst becomes live particles.

    @Test func eventBurstBecomesLiveParticles() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 100, modules: quiet([EmissionTrigger(.event("boom"), .burst(7))]))
        try step(system, frames: 3)
        #expect(aliveCount(system, system.emitters[0]) == 0)
        system.send(event: "boom")
        try step(system)
        #expect(aliveCount(system, system.emitters[0]) == 7)
    }

    @Test func particlesEnteringAVolumeTriggerAnotherEmitter() throws {
        // A stream moving +x crosses a box at x = 1; the second emitter bursts when the first particle arrives.
        let stream = quiet([]) {
            $0.edit(VelocityModule.self) { $0.velocity = [2, 0, 0] }
            $0.edit(RateModule.self) { $0.birthRate = 30 }
        }
        let gate = TriggerVolume.box(center: [1, 0, 0], halfExtents: [0.1, 1, 1])
        let system = try ParticleSystemRuntime(device: runner.device, modules: [stream, quiet([EmissionTrigger(.particlesEnter(volume: gate), .burst(5))])], capacity: 200)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) >= 5)
    }

    @Test func particlesEnterThresholdAccumulates() throws {
        let stream = quiet([]) {
            $0.edit(VelocityModule.self) { $0.velocity = [2, 0, 0] }
            $0.edit(RateModule.self) { $0.birthRate = 30 }
        }
        let gate = TriggerVolume.box(center: [1, 0, 0], halfExtents: [0.1, 1, 1])
        let system = try ParticleSystemRuntime(device: runner.device, modules: [stream, quiet([EmissionTrigger(.particlesEnter(volume: gate, count: 10), .burst(1))])], capacity: 200)
        // The stream reaches the gate after 0.45 s and delivers 30 particles per second. At 0.67 s about 6 have
        // entered (no burst); at 0.92 s about 14 (one burst per 10).
        try step(system, frames: 40)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 15)
        #expect(aliveCount(system, system.emitters[1]) == 1)
    }

    @Test func colliderHitTriggers() throws {
        let falling = quiet([]) {
            $0.edit(ShapeModule.self) { $0.position = [0, 1, 0] }
            $0.edit(VelocityModule.self) { $0.velocity = [0, -3, 0] }
            $0.edit(CollisionModule.self) { $0.restitution = 0 }
        }
        let system = try ParticleSystemRuntime(device: runner.device, modules: [falling, quiet([EmissionTrigger(.colliderHit(index: 1), .burst(3))])], capacity: 50)
        system.colliders = [.sphere(center: [5, 0, 0], radius: 0.5), .plane(normal: [0, 1, 0], distance: 0)]
        system.emitters[0].burst(1)
        try step(system, frames: 10)
        #expect(aliveCount(system, system.emitters[1]) == 0)
        try step(system, frames: 20)
        #expect(aliveCount(system, system.emitters[1]) >= 3)
    }

    @Test func startAndStopActions() throws {
        var emitter = quiet([EmissionTrigger(.event("on"), .start), EmissionTrigger(.event("off"), .stop)]) {
            $0.edit(RateModule.self) { $0.birthRate = 60 }
        }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 500, modules: emitter)
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
}
