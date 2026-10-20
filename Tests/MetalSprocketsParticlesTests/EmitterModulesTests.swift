import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

struct EmitterModulesTests {
    /// Every preset's emitters (sub-emitters too) lift to modules and lower back unchanged.
    @Test func presetsRoundTrip() {
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
        #expect(function.parameters == [[1, 0, 0, 0], .zero, .zero])
        #expect(function == .stitched(emitter.updateModules, slot: .update))
        #expect(emitter.function(for: .spawn) == nil)
        // Parameter values do not change what is compiled.
        var changed = emitter
        changed.updateModules[0].parameters = [[9, 9, 9, 9]]
        #expect(changed.function(for: .update)?.key == function.key)
    }

    @Test func editingSettingsKeepsModuleOrder() {
        var layer = EmitterDescription("Test", settings: ParticleEmitter())
        layer.modules.update.reverse()
        let order = layer.modules.update.map(\.module.kind)
        layer.settings.gravity = [0, -1, 0]
        #expect(layer.modules.update.map(\.module.kind) == order)
        layer.settings.flocking = ParticleFlocking()
        #expect(layer.modules.update.map(\.module.kind) == order + ["flocking"])
    }

    @Test func addableModulesLowerAndLiftToTheirKind() {
        for module in UpdateModule.addable {
            var modules = EmitterModules(ParticleEmitter.neutral)
            modules.update.append(ModuleSlot(module))
            #expect(EmitterModules(modules.lowered()).update.contains { $0.module.kind == module.kind }, "\(module.kind)")
        }
        for module in SpawnModule.addable {
            var modules = EmitterModules(ParticleEmitter.neutral)
            modules.spawn.append(ModuleSlot(module))
            #expect(EmitterModules(modules.lowered()).spawn.contains { $0.module.kind == module.kind }, "\(module.kind)")
        }
        for module in RenderModule.addable {
            var modules = EmitterModules(ParticleEmitter.neutral)
            modules.render.append(ModuleSlot(module))
            #expect(EmitterModules(modules.lowered()).render.contains { $0.module.kind == module.kind }, "\(module.kind)")
        }
    }

    @Test func customAttributesOnlyWhenAFunctionMentionsThem() {
        var emitter = ParticleEmitter()
        #expect(!emitter.usesCustomAttributes)
        emitter.updateFunction = ParticleFunction(source: "[[visible]] void f(thread ParticleState &p, float, float, constant float4 *) {}", name: "f")
        #expect(!emitter.usesCustomAttributes)
        emitter.spawnModules = [StitchedModule(source: "p.custom.x = 1;", name: "g")]
        #expect(emitter.usesCustomAttributes)
    }

    @Test func jsonRoundTrips() throws {
        for system in ParticleSystem.all {
            let (json, files) = try system.encoded()
            let decoded = try ParticleSystem(json: json, resources: EffectResources(files: files))
            #expect(decoded.layers.map(\.modules) == system.layers.map(\.modules), "\(system.name)")
        }
    }
}
