import Foundation
import Metal
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
        // Only member accesses outside comments count (#213).
        #expect(!SlotFunction.usesCustomAttributes("// custom colors\nfloat customize = 1; /* p.custom */"))
        #expect(SlotFunction.usesCustomAttributes("p.custom3.y += 1;"))
        #expect(SlotFunction.usesCustomAttributes("particle . custom = float4(1);"))
        #expect(!SlotFunction.usesCustomAttributes("p.customValue = 1;"))
    }

    @Test func builderPlacesModulesAndFillsRequiredOnes() {
        let windy = true
        let layer = EmitterDescription("Flame", sprite: .smoke) {
            DragModule(amount: 0.3)
            ShapeModule(shape: .disc(radius: 0.3))
            GravityModule(acceleration: [0, 1, 0])
            if windy {
                ShadingModule(model: .foil(settings: ParticleFoil()))
            }
        }
        #expect(layer.modules.update.prefix(2).map(\.module.kind) == ["drag", "gravity"])
        #expect(layer.modules.update.map(\.module.kind) == ["drag", "gravity", "collision"])
        #expect(layer.modules.spawn.map(\.module.kind) == ["shape", "rate", "lifetime"])
        #expect(layer.modules.render.map(\.module.kind) == ["shading", "sprite", "colorOverLife", "sizeOverLife"])
        #expect(layer.settings.foil == ParticleFoil())
        #expect(layer.settings.shape == .disc(radius: 0.3))
        #expect(layer.settings.gravity == [0, 1, 0])
        #expect(layer.settings.birthRate == ParticleEmitter().birthRate)
        #expect(layer.settings.velocity == .zero)
    }

    /// The README's example, kept compiling.
    @Test func readmeExample() {
        let built = ParticleSystem("Torch", cameraEye: [0, 1, 3], cameraTarget: [0, 0.6, 0]) {
            EmitterDescription("Flame", sprite: .smoke) {
                ShapeModule(shape: .disc(radius: 0.3))
                RateModule(birthRate: 400)
                LifetimeModule(range: 0.6...1.2)
                VelocityModule(velocity: [0, 1.5, 0], spread: 0.3)
                SizeOverLifeModule(curve: .linear(from: 0.15, to: 0.4))
                ColorOverLifeModule(color: .linear(from: [1, 0.8, 0.3, 1], to: [1, 0.1, 0, 0]))
                SpriteModule(blendMode: .additive)
            }
            Collider.plane(normal: [0, 1, 0], distance: 0)
            ForceField.turbulence(strength: 1.5, scale: 1, speed: 0.5)
        }
        var description = built.layers[0]
        description.modules.update.append(ModuleSlot(.stitched(StitchedUpdateModule(module: StitchedModule(source: """
            [[stitchable]] constant float4 *swirl(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
                p.velocity += cross(float3(0, 1, 0), p.position) * parameters[0].x * dt;
                return parameters + 1;
            }
            """, name: "swirl", parameters: [[2, 0, 0, 0]])))))
        #expect(description.settings.blendMode == .additive)
        #expect(description.settings.updateModules.count == 1)
    }

    @Test func formatTwoAppearanceModulesMoveToRender() throws {
        let json = """
        {"update": [{"module": {"gravity": {"acceleration": [0, -1, 0]}}}, {"module": {"sizeOverLife": {"curve": {"keyframes": [{"time": 0, "value": 0.5}]}}}}],
        "render": [], "spawn": []}
        """
        let modules = try JSONDecoder().decode(EmitterModules.self, from: Data(json.utf8))
        #expect(modules.update.map(\.module.kind) == ["gravity"])
        #expect(modules.render.map(\.module.kind) == ["sizeOverLife", "shading"])
        let bad = #"{"update": [{"module": {"gravity": {"acceleration": "x"}}}]}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EmitterModules.self, from: Data(bad.utf8)) }
    }

    @Test func typedSubscriptReadsAddsReplacesAndRemoves() {
        var modules = EmitterModules.standard
        modules[RateModule.self]?.birthRate = 7
        #expect(modules.lowered().birthRate == 7)
        modules[ShadingModule.self] = ShadingModule(model: .foil(settings: ParticleFoil(glint: 2)))
        #expect(modules.render.filter { $0.module.kind == "shading" }.count == 1)
        #expect(modules[ShadingModule.self]?.model == .foil(settings: ParticleFoil(glint: 2)))
        #expect(modules.lowered().foil?.glint == 2)
        modules[GravityModule.self] = nil
        #expect(modules[GravityModule.self] == nil)
        #expect(modules.lowered().gravity == .zero)
    }

    @Test(.requiresMetal4) func stitchedTemplatesCompile() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        try StitchedModule.template.validate(device: device)
        try #require(StitchedSpawnModule.added).module.validate(device: device)
        let broken = StitchedModule(source: "not metal", name: "x")
        #expect(throws: ParticleFunctionError.self) { try broken.validate(device: device) }
    }

    /// Format 3 effects: a foil module or a lit sprite become the shading module (#172).
    @Test func formatThreeFoilAndLitBecomeShading() throws {
        func render(_ json: String) throws -> [RenderModule] {
            try JSONDecoder().decode(EmitterModules.self, from: Data(json.utf8)).render.map(\.module)
        }
        let lit = try render(#"{"render": [{"module": {"sprite": {"blendMode": 0, "sortMode": "None", "orientation": {"billboard": {}}, "softness": 0, "isLit": true, "minimumScreenSize": 0}}}]}"#)
        #expect(lit.last == .shading(ShadingModule(model: .lit)))
        let foil = try render(#"{"render": [{"module": {"foil": {"foil": {"glint": 5, "shininess": 10, "iridescence": 0.25}}}}]}"#)
        #expect(foil == [.shading(ShadingModule(model: .foil(settings: ParticleFoil(glint: 5, shininess: 10, iridescence: 0.25))))])
        #expect(try render(#"{"render": []}"#) == [.shading(ShadingModule())])
    }

    /// Custom shading (#173): the model and its per-pixel flag survive saving, and bad source is rejected before it
    /// reaches the runtime.
    @Test(.requiresMetal4) func customShadingRoundTripsAndRejectsBadSource() throws {
        let modules = EmitterModules {
            ShadingModule(model: .custom(function: ShadingModule.template), perPixel: true)
        }
        let system = ParticleSystem("Custom", layers: [EmitterDescription("A", modules: modules)])
        let (json, files) = try system.encoded()
        let decoded = try ParticleSystem(json: json, resources: EffectResources(files: files))
        #expect(decoded.layers[0].modules[ShadingModule.self] == modules[ShadingModule.self])
        #expect(decoded.layers[0].settings.shadingFunction == ShadingModule.template)
        let device = try #require(MTLCreateSystemDefaultDevice())
        try ShadingModule.template.validateShading(device: device)
        #expect(throws: ParticleFunctionError.self) { try ParticleFunction(source: "not metal", name: "x").validateShading(device: device) }
        // Simulation-style source is not a shading function.
        let update = ParticleFunction(source: "[[visible]] void f(thread ParticleState &p, float, float, constant float4 *) {}", name: "f")
        #expect(throws: ParticleFunctionError.self) { try update.validateShading(device: device) }
    }

    @Test func jsonRoundTrips() throws {
        for system in ParticleSystem.all {
            let (json, files) = try system.encoded()
            let decoded = try ParticleSystem(json: json, resources: EffectResources(files: files))
            #expect(decoded.layers.map(\.modules) == system.layers.map(\.modules), "\(system.name)")
        }
    }
}
