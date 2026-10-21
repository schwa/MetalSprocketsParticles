import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import Testing

/// Every module type has an inspector editor (#225), so a new module cannot silently show an empty section.
struct ModuleEditorTests {
    @Test func everyModuleTypeIsEditable() {
        let types: [any ParticleModule.Type] = SpawnModule.types + UpdateModule.types + RenderModule.types
        let missing = types.filter { !($0 is any EditableModule.Type) }.map { "\($0)" }
        #expect(missing.isEmpty, "No editor for \(missing)")
    }
}
