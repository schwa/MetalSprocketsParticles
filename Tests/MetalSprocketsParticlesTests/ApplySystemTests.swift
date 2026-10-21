import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import Testing

/// `ParticleSystemRuntime.apply(_:rebuild:)`: a description reaches the runtime in one step.
@Suite(.serialized, .requiresMetal4)
struct ApplySystemTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func run(_ runtime: ParticleSystemRuntime, frames: Int) throws {
        for _ in 0..<frames {
            try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        }
    }

    func liveCount(_ runtime: ParticleSystemRuntime) -> Int {
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: runtime.capacity)
        return (0..<runtime.capacity).filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
    }

    @Test func everythingInTheDescriptionArrives() throws {
        var system = ParticleSystem.fountain
        system.forceFields = [.wind(velocity: [1, 0, 0], strength: 2)]
        system.lights = [.point(position: [0, 2, 0], color: [1, 0.5, 0.2], range: 3)]
        system.ambientLight = [0.1, 0.1, 0.1]
        let runtime = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        try runtime.apply(system)
        #expect(runtime.emitters.count == system.layers.count)
        #expect(runtime.colliders == system.colliders)
        #expect(runtime.forceFields == system.forceFields)
        #expect(runtime.lights == system.lights)
        #expect(runtime.ambientLight == system.ambientLight)
    }

    @Test func settingAndWorldChangesKeepTheParticles() throws {
        var system = ParticleSystem.fountain
        let runtime = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        try runtime.load(system)
        try run(runtime, frames: 30)
        let buffer = runtime.buffer
        let before = liveCount(runtime)
        system.layers[0].modules.edit(GravityModule.self) { $0.acceleration = [0, -2, 0] }
        system.colliders = []
        system.forceFields = [.turbulence(strength: 1)]
        try runtime.apply(system)
        #expect(runtime.buffer === buffer)
        #expect(liveCount(runtime) == before)
        #expect(runtime.emitters[0].modules[GravityModule.self]?.acceleration == [0, -2, 0])
        #expect(runtime.colliders.isEmpty && runtime.forceFields == [.turbulence(strength: 1)])
    }

    @Test func reapplyingKeepsRuntimeStartAndStop() throws {
        // Triggers start and stop emitters while running. Applying the same description again (as ParticlePlayer does
        // every frame) must not undo that.
        var system = ParticleSystem.fountain
        system.layers[0].modules[TriggersModule.self] = TriggersModule(triggers: [EmissionTrigger(.event("halt"), .stop)])
        let runtime = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        try runtime.load(system)
        runtime.send(event: "halt")
        try run(runtime, frames: 3)
        #expect(!runtime.emitters[0].isEmitting)
        try runtime.apply(system)
        #expect(!runtime.emitters[0].isEmitting)
        // A change to isEmitting in the description still applies.
        system.layers[0].isEmitting = false
        try runtime.apply(system)
        system.layers[0].isEmitting = true
        try runtime.apply(system)
        #expect(runtime.emitters[0].isEmitting)
    }

    @Test func layoutChangesAndLoadStartOver() throws {
        var system = ParticleSystem.fountain
        let runtime = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        try runtime.load(system)
        try run(runtime, frames: 30)
        #expect(liveCount(runtime) > 0)
        // Same layout, but rebuild asked for: particles go.
        try runtime.apply(system, rebuild: true)
        #expect(liveCount(runtime) == 0)
        try run(runtime, frames: 30)
        // A new emitter changes the layout: rebuilt, and both emitters exist.
        system.layers.append(system.layers[0].copy(named: "Second"))
        let buffer = runtime.buffer
        try runtime.apply(system)
        #expect(runtime.buffer !== buffer)
        #expect(runtime.emitters.count == 2)
    }
}
