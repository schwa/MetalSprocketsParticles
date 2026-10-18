import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import Testing

@MainActor
struct OutlineTests {
    @Test func selectingAnEmitterChildSelectsTheEmitter() {
        let model = ParticlesDemoModel(preset: .fireworks)
        let second = model.emitters[1].id
        model.selection = .subEmitter(second, 0)
        #expect(model.selectedEmitter.id == second)
        model.selection = .scene
        #expect(model.selectedEmitter.id == second)
    }

    @Test func addAndRemoveChildren() {
        let model = ParticlesDemoModel()
        let id = model.emitters[0].id
        model.addSubEmitter(to: id)
        #expect(model.selection == .subEmitter(id, 0))
        model.addTrigger(to: id)
        #expect(model.selection == .trigger(id, 0))
        #expect(model.selectedEmitter.settings.triggers.count == 1)
        model.removeSelection()
        #expect(model.selection == .emitter(id))
        #expect(model.selectedEmitter.settings.triggers.isEmpty)
        model.selection = .subEmitter(id, 0)
        model.removeSelection()
        #expect(model.selectedEmitter.settings.subEmitters.isEmpty)
    }

    @Test func addAndRemoveWorldItems() throws {
        let model = ParticlesDemoModel()
        let colliders = model.colliders.count
        model.addCollider(.box)
        guard case let .collider(id) = model.selection else {
            Issue.record("expected a collider selection")
            return
        }
        #expect(model.colliders[id: id]?.collider.kind == .box)
        model.colliders[id: id]?.collider.radius = 2
        #expect(model.colliders.count == colliders + 1)
        model.removeSelection()
        #expect(model.colliders.count == colliders)
        #expect(model.selection == .scene)
        model.addForceField(.vortex)
        #expect(model.forceFields.count == 1)
    }

    @Test func presetMeshReachesTheSystem() throws {
        let model = ParticlesDemoModel(preset: .teapot)
        let system = try #require(model.system)
        #expect(system.emitters.allSatisfy { ($0.mesh?.triangleCount ?? 0) > 1_000 })
        model.duplicateSelectedEmitter()
        #expect(system.emitters.last?.mesh != nil)
    }

    @Test func changingPresetKeepsSceneSelectedOrSelectsFirstEmitter() {
        let model = ParticlesDemoModel()
        model.presetName = ParticlePreset.campfire.name
        #expect(model.selection == .scene)
        model.selection = .emitter(model.emitters[1].id)
        model.presetName = ParticlePreset.rain.name
        #expect(model.selection == .emitter(model.emitters[0].id))
    }
}
