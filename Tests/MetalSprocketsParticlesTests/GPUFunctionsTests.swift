import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import Testing

/// GPUFunctions (#222): every visible function the pipelines call, compiled once, linked the right way, and reported
/// clearly when it does not compile.
@Suite(.serialized, .requiresMetal4)
struct GPUFunctionsTests {
    let device: MTLDevice
    let functions: GPUFunctions

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        functions = GPUFunctions(device: device, library: try ShaderLibrary(bundle: .metalSprocketsParticlesShaders(), device: device))
    }

    let update = ParticleFunction(source: """
    [[visible]] void lift(thread ParticleState &p, float dt, float time, constant float4 *parameters) { p.velocity.y += 1; }
    """, name: "lift", parameters: [[1, 0, 0, 0]])

    func message(_ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch let error as ParticleFunctionError {
            return error.message
        } catch {
            return "\(error)"
        }
    }

    @Test func compilesEachSourceOnceRegardlessOfParameters() throws {
        let first = try functions.simulation(.user(update), slot: .update)
        var changed = update
        changed.parameters = [[9, 9, 9, 9]]
        let again = try functions.simulation(.user(changed), slot: .update)
        #expect(first.reference == again.reference)
        let shading = try functions.shading(ShadingModule.template)
        #expect(try functions.shading(ShadingModule.template).reference == shading.reference)
    }

    @Test func emptySlotsGetTheirOwnNoOps() throws {
        let names = try ParticleFunctionSlot.allCases.map { try functions.simulation(nil, slot: $0).reference.name }
        #expect(Set(names).count == ParticleFunctionSlot.allCases.count)
    }

    /// Built-ins static (inlinable), user code binary (no pipeline rebuild).
    @Test func linkingFollowsWhoWroteTheCode() throws {
        let builtIns = try functions.builtInShading()
        #expect(builtIns.all.allSatisfy { $0.linking == .static })
        #expect(try functions.shading(ShadingModule.template).linking == .binary)
        #expect(try functions.simulation(.user(update), slot: .update).linking == .binary)
    }

    @Test func badSourceIsReportedByName() {
        let broken = ParticleFunction(source: "not metal", name: "broken")
        #expect(message { _ = try functions.simulation(.user(broken), slot: .update) } != nil)
        let missing = ParticleFunction(source: "[[visible]] void other(thread ParticleState &p, float, float, constant float4 *) {}", name: "absent")
        #expect(message { _ = try functions.simulation(.user(missing), slot: .update) }?.contains("no [[visible]] function") == true)
        // Simulation code is not shading code: the shading prelude has no ParticleState.
        #expect(message { _ = try functions.shading(update) } != nil)
        #expect(message { try ParticleFunction(source: "not metal", name: "x").validateShading(device: device) } != nil)
    }

    /// Templates the demo offers compile as they are.
    @Test func templatesCompile() throws {
        try ShadingModule.template.validateShading(device: device)
        try StitchedModule.template.validate(device: device)
        try #require(StitchedSpawnModule.added).module.validate(device: device)
        #expect(message { try StitchedModule(source: "not metal", name: "x").validate(device: device) } != nil)
    }

    /// Stitched stacks: modules from different sources may share helper names; two modules with one name but different
    /// sources are an error.
    @Test func stitchedStacks() throws {
        let first = StitchedModule(source: """
        static float3 helper(float3 v) { return v + float3(0, 1, 0); }
        [[stitchable]] constant float4 *up(thread ParticleState &p, float dt, float time, constant float4 *parameters) { p.velocity = helper(p.velocity); return parameters; }
        """, name: "up")
        let second = StitchedModule(source: """
        static float3 helper(float3 v) { return v * 2; }
        [[stitchable]] constant float4 *speedUp(thread ParticleState &p, float dt, float time, constant float4 *parameters) { p.velocity = helper(p.velocity); return parameters; }
        """, name: "speedUp")
        _ = try functions.simulation(.stitched([first, second], slot: .update), slot: .update)
        var clash = second
        clash.name = "up"
        #expect(message { _ = try functions.simulation(.stitched([first, clash], slot: .update), slot: .update) }?.contains("named 'up'") == true)
    }
}
