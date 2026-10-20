import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

struct EmitterModulesTests {
    /// Every preset's emitters (sub-emitters too) lift to modules and lower back unchanged.
    @Test func presetsRoundTrip() throws {
        for system in ParticleSystem.all {
            for layer in system.layers {
                let settings = layer.settings
                #expect(EmitterModules(settings).lowered() == settings, "\(system.name) / \(layer.name)")
            }
        }
    }

    @Test func defaultEmitterRoundTrips() {
        #expect(EmitterModules(ParticleEmitter()).lowered() == ParticleEmitter())
        #expect(EmitterModules(ParticleEmitter.default2D).lowered() == ParticleEmitter.default2D)
    }

    @Test func disabledModulesAreSkippedAndKept() throws {
        var layer = EmitterDescription("Test", settings: ParticleEmitter())
        let index = try #require(layer.modules.update.firstIndex { if case .gravity = $0.module { true } else { false } })
        layer.modules.update[index].isEnabled = false
        #expect(layer.settings.gravity == .zero)
        layer.settings.drag = 0.9
        #expect(layer.modules.update.contains { !$0.isEnabled })
        #expect(layer.settings.drag == 0.9)
    }

    @Test func stitchedUpdateModulesMatchAHandWrittenFunction() throws {
        // Covered end to end with the runtime in StitchingSpikeTests; here: the slot gets one function from the stack.
        var emitter = ParticleEmitter()
        emitter.updateModules = [StitchedModule(source: "x", name: "a", parameters: [[1, 0, 0, 0]]), StitchedModule(source: "y", name: "b", parameterCount: 2)]
        let function = try #require(emitter.function(for: .update))
        #expect(function.parameters.count == 3)
        #expect(StitchedModule.modules(in: function)?.map(\.name) == ["a", "b"])
        #expect(StitchedModule.modules(in: function)?.map(\.source) == ["x", "y"])
        #expect(emitter.function(for: .spawn) == nil)
    }

    @Test func jsonRoundTrips() throws {
        for system in ParticleSystem.all {
            let (json, files) = try system.encoded()
            let decoded = try ParticleSystem(json: json, resources: EffectResources(files: files))
            #expect(decoded.layers.map(\.modules) == system.layers.map(\.modules), "\(system.name)")
        }
    }
}
