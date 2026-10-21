import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftMesh
import Testing

@Suite(.serialized, .requiresMetal4)
struct EmitterDescriptionTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func liveCount(_ system: ParticleSystemRuntime) -> Int {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity).filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
    }

    func description(_ name: String, sprite: ParticleSprite = .star, mesh: Mesh? = nil) -> EmitterDescription {
        var settings = EmitterModules.standard
        settings.edit(RateModule.self) { $0.birthRate = 600 }
        settings.edit(LifetimeModule.self) { $0.range = 5...5 }
        return EmitterDescription(name, modules: settings, sprite: sprite, capacity: 1_000, mesh: mesh)
    }

    @Test func editingInPlaceKeepsParticlesAndChangingIDsRebuilds() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        var descriptions = [description("A"), description("B")]
        try system.apply(descriptions)
        for _ in 0..<10 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let alive = liveCount(system)
        #expect(alive > 0)

        descriptions[0].modules.edit(GravityModule.self) { $0.acceleration = [0, -1, 0] }
        descriptions[1].isEmitting = false
        try system.apply(descriptions)
        #expect(liveCount(system) == alive)
        #expect(system.emitters[0].modules[GravityModule.self]?.acceleration == [0, -1, 0])
        #expect(system.emitters[1].isEmitting == false)

        descriptions.append(descriptions[0].copy(named: "A Copy"))
        try system.apply(descriptions)
        #expect(system.emitters.count == 3)
        #expect(liveCount(system) == 0)
    }

    @Test func resourcesAreResolvedOnceAndReused() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        let mesh = Mesh.teapot(diameter: 1)
        var descriptions = [description("A", mesh: mesh), description("B", sprite: .star)]
        descriptions[0].modules.edit(ShapeModule.self) { $0.shape = .mesh }
        try system.apply(descriptions)
        let texture = try #require(system.emitters[0].texture)
        let emitterMesh = try #require(system.emitters[0].mesh)
        #expect(system.emitters[1].texture === texture)

        descriptions[0].modules.edit(RateModule.self) { $0.birthRate = 1 }
        try system.apply(descriptions)
        #expect(system.emitters[0].texture === texture)
        #expect(system.emitters[0].mesh === emitterMesh)

        descriptions[0].mesh = nil
        descriptions[0].sprite = .softDot
        try system.apply(descriptions)
        #expect(system.emitters[0].mesh == nil)
        #expect(system.emitters[0].texture == nil)
    }

    @Test func copyHasANewIDAndTheSameContents() {
        let original = description("A", mesh: Mesh.teapot())
        let copy = original.copy(named: "B")
        #expect(copy.id != original.id)
        #expect(copy.name == "B")
        #expect(copy.modules == original.modules && copy.mesh == original.mesh && copy.sprite == original.sprite)
    }
}
