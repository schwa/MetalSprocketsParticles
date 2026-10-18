@testable import MetalSprocketsParticles
import simd
import Testing

/// #76: built-in presets come from JSON resources.
struct BuiltInPresetTests {
    @Test func everyIndexedPresetLoadsWithAUniqueNameAndAComment() {
        let slugs = ParticlePreset.builtInSlugs
        #expect(slugs.count >= 25)
        #expect(ParticlePreset.all.count == slugs.count)
        #expect(Set(ParticlePreset.all.map(\.name)).count == slugs.count)
        #expect(ParticlePreset.all.allSatisfy { !$0.comment.isEmpty && !$0.layers.isEmpty })
        #expect(ParticlePreset.teapot.layers.allSatisfy { $0.mesh != nil })
    }
}

struct PresetBuilderTests {
    func settings(_ birthRate: Float) -> ParticleEmitter {
        var settings = ParticleEmitter()
        settings.birthRate = birthRate
        return settings
    }

    /// Everything but layer ids, which are always fresh.
    func same(_ a: ParticlePreset, _ b: ParticlePreset) -> Bool {
        a.name == b.name
            && a.layers.map(\.name) == b.layers.map(\.name)
            && a.layers.map(\.settings) == b.layers.map(\.settings)
            && a.layers.map(\.capacity) == b.layers.map(\.capacity)
            && a.colliders == b.colliders && a.forceFields == b.forceFields && a.lights == b.lights
            && a.trackedObjects == b.trackedObjects && a.ambientLight == b.ambientLight
            && a.cameraEye == b.cameraEye && a.cameraTarget == b.cameraTarget && a.animatesColliders == b.animatesColliders
    }

    @Test func builderMatchesTheMemberwiseInitializer() {
        let motion = EmitterMotion(kind: .circle)
        let built = ParticlePreset("Test", ambientLight: [0.1, 0.1, 0.1], cameraEye: [1, 2, 3]) {
            Collider.plane(normal: [0, 1, 0], distance: 0)
            EmitterDescription("A", settings: settings(10), capacity: 100)
            ForceField.turbulence(strength: 1)
            ParticleLight.directional(direction: [0, -1, 0])
            EmitterDescription("B", settings: settings(20))
            TrackedObject("ball", motion: motion)
        }
        let explicit = ParticlePreset(
            "Test",
            layers: [EmitterDescription("A", settings: settings(10), capacity: 100), EmitterDescription("B", settings: settings(20))],
            colliders: [.plane(normal: [0, 1, 0], distance: 0)],
            forceFields: [.turbulence(strength: 1)],
            lights: [.directional(direction: [0, -1, 0])],
            ambientLight: [0.1, 0.1, 0.1],
            trackedObjects: ["ball": motion],
            cameraEye: [1, 2, 3]
        )
        #expect(same(built, explicit))
    }

    @Test func controlFlowWorks() {
        func preset(windy: Bool, count: Int, extra: Collider?) -> ParticlePreset {
            ParticlePreset("Flow") {
                for index in 0..<count {
                    EmitterDescription("Layer \(index)", settings: settings(Float(index)))
                }
                if windy {
                    ForceField.wind(velocity: [1, 0, 0], strength: 1)
                } else {
                    ForceField.turbulence(strength: 1)
                }
                if let extra {
                    extra
                }
            }
        }
        let calm = preset(windy: false, count: 2, extra: nil)
        #expect(calm.layers.map(\.name) == ["Layer 0", "Layer 1"])
        #expect(calm.forceFields == [.turbulence(strength: 1)])
        #expect(calm.colliders.isEmpty)
        let windy = preset(windy: true, count: 0, extra: .sphere(center: .zero, radius: 1))
        #expect(windy.layers.isEmpty)
        #expect(windy.forceFields == [.wind(velocity: [1, 0, 0], strength: 1)])
        #expect(windy.colliders == [.sphere(center: .zero, radius: 1)])
    }
}
