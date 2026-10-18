import Foundation
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
        model.colliders[id: id]?.collider.shape.radius = 2
        #expect(model.colliders.count == colliders + 1)
        model.removeSelection()
        #expect(model.colliders.count == colliders)
        #expect(model.selection == .scene)
        model.addForceField(.vortex)
        #expect(model.forceFields.count == 1)
    }

    /// #56: after a removal SwiftUI may read and write an editor's bindings once more. They must not trap, and writes must
    /// not bring the item back or touch another one.
    @Test func selectedItemsSurviveRemoval() {
        let model = ParticlesDemoModel()
        model.addCollider(.box)
        model.selectedCollider = .sphere(center: [1, 1, 1], radius: 2)
        #expect(model.colliders.last?.collider == .sphere(center: [1, 1, 1], radius: 2))
        let colliderCount = model.colliders.count
        let removed = model.selection
        model.removeSelection()
        model.selection = removed
        _ = model.selectedCollider
        model.selectedCollider = .sphere(center: .zero, radius: 9)
        #expect(model.colliders.count == colliderCount - 1)
        #expect(!model.colliders.contains { $0.collider == .sphere(center: .zero, radius: 9) })

        model.addForceField(.vortex)
        let field = model.selection
        model.removeSelection()
        model.selection = field
        _ = model.selectedForceField
        model.selectedForceField = .turbulence(strength: 9)
        #expect(model.forceFields.isEmpty)

        let emitter = model.emitters[0].id
        model.addSubEmitter(to: emitter)
        model.addTrigger(to: emitter)
        model.selection = .subEmitter(emitter, 0)
        model.removeSelection()
        model.selection = .subEmitter(emitter, 0)
        _ = model.selectedSubEmitter
        model.selectedSubEmitter = SubEmitter(occasion: .onBirth, countPerEvent: 9, settings: ParticleEmitter())
        #expect(model.selectedEmitter.settings.subEmitters.isEmpty)
        model.selection = .trigger(emitter, 0)
        model.removeSelection()
        model.selection = .trigger(emitter, 0)
        _ = model.selectedTrigger
        model.selectedTrigger = EmissionTrigger(.event("x"), .stop)
        #expect(model.selectedEmitter.settings.triggers.isEmpty)
    }

    /// #57: curve rows bind by position; after removing a stop, stale row bindings must not trap or write.
    @Test func curveStopAccessSurvivesRemoval() {
        var curve = ParticleCurve<Float>([.init(0, 1), .init(0.5, 2), .init(1, 3)])
        curve[stop: 1].value = 5
        #expect(curve.keyframes[1].value == 5)
        curve.keyframes.remove(at: 2)
        #expect(curve[stop: 2] == curve.keyframes[1])
        let before = curve
        curve[stop: 2].time = 0.9
        curve[stop: 2].value = 9
        #expect(curve == before)
    }

    /// #25: the current scene saves to a file and opens again as a picker entry.
    @Test func saveAndOpenEffect() throws {
        let model = ParticlesDemoModel(preset: .fireworks)
        model.emitters[0].settings.birthRate = 7
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("My Fireworks-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try model.currentEffect.write(to: url)

        model.presetName = ParticlePreset.rain.name
        try model.openEffect(at: url)
        #expect(model.presetName.hasPrefix("My Fireworks"))
        #expect(model.presets.contains { $0.name == model.presetName })
        #expect(model.emitters[0].settings.birthRate == 7)
        #expect(model.emitters.count == ParticlePreset.fireworks.layers.count)

        // A file named like a built-in preset does not shadow it.
        model.open(ParticlePreset.rain, named: "Fireworks")
        #expect(model.presetName == "Fireworks (File)")
    }

    /// #63: an effect with no emitters must not trap the inspector, and edits to the placeholder go nowhere.
    @Test func effectWithNoEmittersIsSafe() {
        let model = ParticlesDemoModel()
        model.open(ParticlePreset("Empty", layers: []), named: "Empty")
        #expect(model.emitters.isEmpty)
        _ = model.selectedEmitter
        model.selectedEmitter.settings.birthRate = 99
        #expect(model.emitters.isEmpty)
        model.burstSelectedEmitter()
        model.addEmitter()
        #expect(model.emitters.count == 1)
    }

    /// #69: tracked objects come from the preset, move each frame, and are saved with the effect.
    @Test func trackedObjectsFollowThePreset() {
        let model = ParticlesDemoModel(preset: .dunk)
        let start = model.frameTrackedObjects(time: 0)["ball"]
        let later = model.frameTrackedObjects(time: 0.5)["ball"]
        #expect(start != nil && later != nil && start != later)
        #expect(model.currentEffect.trackedObjects == ParticlePreset.dunk.trackedObjects)
        model.presetName = ParticlePreset.rain.name
        #expect(model.frameTrackedObjects(time: 0).isEmpty)
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
