import Metal
import MetalSprockets
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import MetalSprocketsParticlesSamples
import simd
import SwiftUI
import Testing

@Suite(.requiresMetal4)
struct ColorPipelineTests {
    /// Golden images and particles-render use OffscreenRenderer. If the app renders to a different format, tests
    /// check different colors than users see (#15).
    @Test func appRendersToSameFormatAsOffscreenRenderer() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 4, height: 4))
        #expect(ParticleViewportView.colorPixelFormat == renderer.colorTexture.pixelFormat)
    }
}

@Suite(.requiresMetal4)
struct EmitterAdapterTests {
    @Test func lifetimeSlidersMoveTheRangeAndKeepTheSpread() {
        var emitter = ParticleEmitter()
        emitter.lifetime = 1...2
        #expect(emitter.lifetimeAverage == 1.5)
        #expect(emitter.lifetimeVariation == 0.5)
        // One slider makes particles live longer, and the spread stays.
        emitter.lifetimeAverage = 10
        #expect(emitter.lifetime == 9.5...10.5)
        emitter.lifetimeVariation = 2
        #expect(emitter.lifetime == 8...12)
    }

    @Test func categorySummariesShowEveryBit() {
        #expect(UInt32.max.categorySummary == "All")
        #expect(UInt32(0).categorySummary == "None")
        #expect(UInt32(0b101).categorySummary == "1, 3")
        // Bits above 8 are no longer invisible.
        #expect((UInt32(0b10) | UInt32.upperCategories).categorySummary == "2 + 9–32")
        #expect((UInt32(1) << 20).categorySummary == "some of 9–32")
    }

    @Test func upperCategoriesToggleTogether() {
        var mask: UInt32 = 0b1
        mask.hasUpperCategories = true
        #expect(mask == 0b1 | UInt32.upperCategories)
        #expect(mask.hasUpperCategories)
        mask.hasUpperCategories = false
        #expect(mask == 0b1)
    }

    @Test func matchSummariesCountSharedBits() {
        #expect(categoryMatchSummary(0b1, categories: [0b1, 0b10, .max], noun: "collider") == "Matches 2 of 3 colliders")
        #expect(categoryMatchSummary(0, categories: [.max], noun: "field") == "Matches 0 of 1 field")
    }

    @Test func capacityStaysInItsRange() {
        var description = EmitterDescription("Dots", settings: ParticleEmitter(), capacity: 1_000)
        description.editableCapacity = 5_000
        #expect(description.capacity == 5_000)
        description.editableCapacity = 0
        #expect(description.capacity == EmitterDescription.editableCapacityRange.lowerBound)
        description.editableCapacity = 50_000_000
        #expect(description.capacity == EmitterDescription.editableCapacityRange.upperBound)
    }

    @Test func warnsWhenRateAndLifetimeNeedMoreParticles() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 1_000
        emitter.birthRateVariation = 0
        emitter.lifetime = 1...2
        // 1,000 a second for up to 2 seconds: 2,000 alive at most.
        #expect(emitter.particlesNeeded(capacity: 2_000) == nil)
        #expect(emitter.particlesNeeded(capacity: 1_500) == 2_000)
        emitter.birthRateVariation = 500
        #expect(emitter.particlesNeeded(capacity: 2_000) == 3_000)
    }

    @MainActor
    @Test func editedCapacityReachesTheRunningSystem() throws {
        let model = ParticlesDemoModel()
        model.presetName = "Fountain"
        model.selectedEmitter.editableCapacity = 12_345
        #expect(model.currentEffect.layers.first { $0.id == model.selectedEmitter.id }?.capacity == 12_345)
        let player = try #require(try model.player(projection: matrix_identity_float4x4, cameraToWorld: matrix_identity_float4x4))
        #expect(player.runtime.emitters.contains { $0.capacity == 12_345 })
    }

    @Test func lifetimesNeverGoBelowTheMinimum() {
        var emitter = ParticleEmitter()
        emitter.lifetime = 1...3
        // Shorter than the spread allows: the spread narrows instead of going below the minimum.
        emitter.lifetimeAverage = 0.5
        #expect(emitter.lifetime.lowerBound >= ParticleEmitter.minimumEditableLifetime)
        #expect(abs(emitter.lifetimeAverage - 0.5) < 1e-6)
        emitter.lifetimeVariation = 100
        #expect(emitter.lifetime.lowerBound >= ParticleEmitter.minimumEditableLifetime - 1e-6)
        emitter.lifetimeAverage = -1
        #expect(emitter.lifetime == ParticleEmitter.minimumEditableLifetime...ParticleEmitter.minimumEditableLifetime)
    }

    @Test func limitedEmissionToggle() {
        var emitter = ParticleEmitter()
        #expect(!emitter.hasLimitedEmission)
        emitter.hasLimitedEmission = true
        #expect(emitter.emissionDuration == 1)
        emitter.limitedEmissionDuration = 4
        emitter.hasLimitedEmission = true
        #expect(emitter.emissionDuration == 4)
        emitter.hasLimitedEmission = false
        #expect(emitter.emissionDuration == nil)
    }

    @Test func velocityStretch() {
        var emitter = ParticleEmitter()
        emitter.velocityStretch = 0.7
        #expect(emitter.orientation == .velocityAligned(stretch: 0.7))
        emitter.orientation.kind = .yAligned
        #expect(emitter.velocityStretch == 0)
    }

    @Test func shapeParameters() {
        var emitter = ParticleEmitter()
        emitter.shape.kind = .cone
        emitter.shapeRadius = 0.7
        emitter.shapeSecondary = 2
        #expect(emitter.shape == .cone(radius: 0.7, height: 2))
        emitter.shape.kind = .plane
        emitter.shapeSize = [2, 9, 3]
        #expect(emitter.shape == .plane(size: [2, 3]))
        // Parameters that do not apply are ignored.
        emitter.shapeRadius = 5
        #expect(emitter.shape == .plane(size: [2, 3]))
    }

    @Test func imageSequenceToggleAndGrid() {
        var emitter = ParticleEmitter()
        emitter.hasImageSequence = true
        #expect(emitter.imageSequence?.frameCount == 4)
        emitter.editableImageSequence.gridColumns = 4
        #expect(emitter.imageSequence?.frameCount == 8)
        emitter.hasImageSequence = false
        #expect(emitter.imageSequence == nil)
    }

    @Test func colorKeyframeRoundTripsThroughLinearSRGB() {
        var curve = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.7, 0.2, 1], to: [0.8, 0.1, 0.05, 0])
        let start = curve.keyframes[0].value
        curve.keyframes[0].color = curve.keyframes[0].color
        #expect(abs(curve.keyframes[0].value - start).max() < 1e-4)
        curve.keyframes[1].color = Color(.sRGBLinear, red: 0, green: 0.5, blue: 1, opacity: 0.25)
        #expect(abs(curve.keyframes[1].value - SIMD4<Float>(0, 0.5, 1, 0.25)).max() < 1e-4)
    }
}

@Suite(.requiresMetal4)
struct ColliderAdapterTests {
    @Test func kindChangeKeepsCenter() {
        var collider = Collider.sphere(center: [1, 2, 3], radius: 0.5, categoryBitMask: 0b10)
        collider.kind = .box
        #expect(collider.shape.center == [1, 2, 3])
        #expect(collider.categoryBitMask == 0b10)
        collider.kind = .capsule
        #expect(simd_distance(collider.shape.center, [1, 2, 3]) < 1e-5)
    }

    @Test func planeCenterMovesAlongNormal() {
        var collider = Collider.plane(normal: [0, 1, 0], distance: 0)
        collider.shape.center.y = 1.5
        #expect(collider == .plane(normal: [0, 1, 0], distance: 1.5))
    }

    @Test func boxSizeAndTilt() {
        var collider = Collider.box(center: .zero, halfExtents: [1, 1, 1])
        collider.shape.size = [2, 4, 6]
        collider.shape.tilt = 0.5
        #expect(collider.shape.size == [2, 4, 6])
        #expect(abs(collider.shape.tilt - 0.5) < 1e-5)
    }

    @Test func capsuleLengthKeepsMidpoint() {
        var collider = Collider.capsule(start: [-1, 0, 0], end: [1, 0, 0], radius: 0.2)
        collider.shape.length = 4
        #expect(collider == .capsule(start: [-2, 0, 0], end: [2, 0, 0], radius: 0.2))
    }

    @Test func categoryBits() {
        var mask: UInt32 = .max
        mask[bit: 1] = false
        #expect(mask == ~UInt32(0b10))
        #expect(!mask[bit: 1] && mask[bit: 0])
        mask[bit: 1] = true
        #expect(mask == .max)
    }
}

@Suite(.requiresMetal4)
struct ForceFieldAdapterTests {
    @Test func kindAndStrength() {
        var field = ForceField.wind(velocity: [1, 0, 0], strength: 2)
        field.effect.strength = 5
        #expect(field == .wind(velocity: [1, 0, 0], strength: 5))
        field.kind = .vortex
        field.effect.radius = 3
        field.effect.center = [0, 1, 0]
        #expect(field.kind == .vortex)
        #expect(field.effect.radius == 3)
        #expect(field.effect.center == [0, 1, 0])
        field.kind = .turbulence
        field.effect.turbulenceScale = 2
        field.effect.turbulenceSpeed = 0.25
        #expect(field.effect.turbulenceScale == 2 && field.effect.turbulenceSpeed == 0.25)
    }
}

@MainActor
@Suite(.requiresMetal4)
struct ModelTests {
    /// The scene the model hands the player must be the preset itself, so settings added later cannot be dropped by the
    /// editor without a test failing. Layer ids differ on purpose (load renews them).
    @Test func currentEffectRoundTripsEveryPreset() throws {
        func normalized(_ system: ParticleSystem) throws -> NSDictionary {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(system)) as? [String: Any])
            object["layers"] = (object["layers"] as? [[String: Any]])?.map { layer in
                var layer = layer
                layer["id"] = nil
                return layer
            }
            return object as NSDictionary
        }
        let model = ParticlesDemoModel()
        for preset in ParticleSystem.all {
            model.presetName = preset.name
            let expected = try normalized(preset)
            let actual = try normalized(model.currentEffect)
            let differing = (expected.allKeys as? [String] ?? []).filter { expected[$0] as? NSObject != actual[$0] as? NSObject }
            #expect(differing.isEmpty, "\(preset.name): \(differing)")
        }
    }

    @Test func loadsEveryPreset() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        for preset in ParticleSystem.all {
            model.presetName = preset.name
            #expect(model.emitters.map(\.name) == preset.layers.map(\.name))
            #expect(system.emitters.map(\.capacity) == preset.layers.map(\.capacity))
            #expect(system.colliders == preset.colliders)
            #expect(system.forceFields == preset.forceFields)
            #expect(model.animateColliders == preset.animatesColliders)
            #expect(model.cameraEye == preset.cameraEye)
            // Sprites reach the system: soft dots have no texture, everything else does.
            for (layer, emitter) in zip(preset.layers, system.emitters) {
                #expect((emitter.texture == nil) == (layer.sprite == .softDot))
            }
        }
    }

    @Test func pointerBindingsLoadSaveAndSurviveRemovals() {
        let model = ParticlesDemoModel()
        var preset = ParticleSystem("Pointer", layers: [ParticleSystem.Layer("A", settings: ParticleEmitter())])
        preset.colliders = [.plane(normal: [0, 1, 0], distance: 0), .sphere(center: .zero, radius: 0.5)]
        preset.forceFields = [.wind(velocity: [1, 0, 0], strength: 1), .attractor(center: .zero, strength: 2)]
        preset.pointerBindings = [.collider(1), .forceField(1), .emitter(0)]
        model.open(preset, named: "Pointer")
        #expect(Set(model.pointerBindings) == Set(preset.pointerBindings))
        #expect(Set(model.currentEffect.pointerBindings) == Set(preset.pointerBindings))

        let pointer: SIMD3<Float> = [1, 2, 3]
        #expect(model.currentEffect.colliders(at: 0, pointer: pointer)[1] == .sphere(center: pointer, radius: 0.5))
        #expect(model.currentEffect.forceFields(at: 0, pointer: pointer)[1] == .attractor(center: pointer, strength: 2))
        #expect(model.currentEffect.transforms(at: 0, pointer: pointer)[0].columns.3 == SIMD4(pointer, 1))

        // Removing the first collider keeps the sphere bound; its saved index moves down.
        model.colliders.removeFirst()
        #expect(model.pointerBindings.contains(.collider(0)))
        #expect(model.currentEffect.colliders(at: 0, pointer: pointer)[0] == .sphere(center: pointer, radius: 0.5))
    }

    @Test func stepPresetWrapsAround() {
        let model = ParticlesDemoModel()
        let names = model.presets.map(\.name)
        model.presetName = names[0]
        model.stepPreset(by: 1)
        #expect(model.presetName == names[1])
        model.stepPreset(by: -2)
        #expect(model.presetName == names[names.count - 1])
        model.stepPreset(by: 1)
        #expect(model.presetName == names[0])
    }

    @Test func revertDiscardsEdits() {
        let model = ParticlesDemoModel()
        model.selectedEmitter.settings.birthRate = 1
        model.colliders = []
        model.reloadPreset()
        #expect(model.selectedEmitter.settings == ParticleSystem.fountain.layers[0].settings)
        #expect(model.colliders.map(\.collider) == ParticleSystem.fountain.colliders)
    }

    @Test func pushesPlaybackToSystem() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        model.speedFactor = 2
        model.playback = .paused
        #expect(system.speedFactor == 2)
        #expect(system.state == .paused)
        model.restart()
        #expect(system.state == .playing)
        #expect(model.playback == .playing)
    }

    @Test func editingSelectedEmitterReachesSystem() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        model.selectedEmitter.settings.birthRate = 123
        model.selectedEmitter.isEmitting = false
        model.selectedEmitter.simulationSpace = .local
        model.selectedEmitter.sprite = .star
        #expect(system.emitters[0].settings.birthRate == 123)
        #expect(!system.emitters[0].isEmitting)
        #expect(system.emitters[0].simulationSpace == .local)
        #expect(system.emitters[0].texture != nil)
    }

    @Test func addingDuplicatingAndRemovingEmitters() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        model.selectedEmitter.sprite = .ring
        model.duplicateSelectedEmitter()
        #expect(model.emitters.count == 2)
        #expect(system.emitters.count == 2)
        #expect(model.selectedEmitter.sprite == .ring)
        #expect(system.emitters[1].texture != nil)
        // The duplicate keeps the preset layer's capacity.
        #expect(system.emitters[1].capacity == ParticleSystem.fountain.layers[0].capacity)
        model.addEmitter()
        #expect(system.emitters.count == 3)
        model.removeSelectedEmitter()
        model.removeSelectedEmitter()
        model.removeSelectedEmitter()
        #expect(model.emitters.count == 1)
        #expect(system.emitters.count == 1)
    }

    @Test func collidersAndForceFieldsReachSystem() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        model.colliders = [ColliderItem(collider: .sphere(center: .zero, radius: 1))]
        model.forceFields = [ForceFieldItem(field: .turbulence(strength: 1))]
        #expect(system.colliders == [.sphere(center: .zero, radius: 1)])
        #expect(system.forceFields == [.turbulence(strength: 1)])
        model.animateColliders = false
        #expect(model.currentEffect.colliders(at: 5) == [.sphere(center: .zero, radius: 1)])
    }

    @Test func emitterMotionReachesTheEffect() {
        let model = ParticlesDemoModel()
        model.selectedEmitter.motion = EmitterMotion(kind: .circle, radius: 1, speed: 1)
        #expect(model.currentEffect.transforms(at: 0).first?.columns.3 == [1, 0, 0, 1])
    }
}
