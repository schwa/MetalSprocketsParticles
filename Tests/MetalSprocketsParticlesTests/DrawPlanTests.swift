import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// What `planDraws` decides for each emitter (#221), checked without rendering.
@Suite(.serialized, .requiresMetal4)
struct DrawPlanTests {
    let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 100)

    func plan(_ configure: (inout EmitterModules) -> Void) throws -> EmitterDraw {
        var settings = EmitterModules.standard
        settings.edit(RateModule.self) { $0.birthRate = 0 }
        configure(&settings)
        let system = try ParticleSystemRuntime(capacity: 16, modules: settings)
        system.burst(16)
        return try #require(try system.planDraws(projection: projection, view: view, sceneDepth: nil).first)
    }

    /// The vertex shader's bool function constant `name`; false when it is not set.
    func constant(_ shader: VertexShader?, _ name: String) -> Bool {
        if case let .bool(value)? = shader?.reference.constants[name] {
            return value
        }
        return false
    }

    @Test func unlitSpritesSkipShading() throws {
        let draw = try plan { _ in }
        #expect(draw.kind.vertexShaderName == "particleVertex")
        #expect(draw.shading == nil)
        #expect(constant(draw.vertexShader, "particleHasShading") == false)
        #expect(constant(draw.vertexShader, "particleShadesPerPixel") == false)
    }

    @Test func litSpritesShadePerVertex() throws {
        let draw = try plan { $0.edit(ShadingModule.self) { $0.model = .lit } }
        #expect(draw.shading?.reference.name == "particleShadeLit")
        #expect(draw.shadingStage == .vertex)
        #expect(constant(draw.vertexShader, "particleHasShading") == true)
    }

    /// Foil sprites always shade per pixel, for their crinkle (#175), with foil linked statically.
    @Test func foilSpritesShadePerPixel() throws {
        let draw = try plan {
            $0.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil()) }
            $0.edit(SpriteModule.self) { $0.orientation = .tumbling }
        }
        #expect(draw.shading?.reference.name == "particleShadeFoil")
        #expect(draw.shading?.linking == .static)
        #expect(draw.shadingStage == .fragment)
        #expect(constant(draw.vertexShader, "particleShadesPerPixel") == true)
        #expect(constant(draw.vertexShader, "particleHasShading") == false)
    }

    /// Meshes always call a shading function, even unlit; foil meshes stay per vertex.
    @Test func meshesAlwaysShade() throws {
        let unlit = try plan { $0[MeshModule.self] = MeshModule(mesh: .cube) }
        #expect(unlit.kind.isMesh)
        #expect(unlit.shading?.reference.name == "particleShadeUnlit")
        let foil = try plan {
            $0[MeshModule.self] = MeshModule(mesh: .coin)
            $0.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil()) }
        }
        #expect(foil.shading?.reference.name == "particleShadeFoil")
        #expect(foil.shadingStage == .vertex)
    }

    /// A ribbon wins over a mesh; strips never get foil.
    @Test func ribbonsWinAndStripsGetNoFoil() throws {
        let draw = try plan {
            $0[RibbonModule.self] = RibbonModule(ribbon: ParticleRibbon())
            $0[MeshModule.self] = MeshModule(mesh: .cube)
            $0.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil()) }
        }
        guard case .ribbon = draw.kind else {
            Issue.record("Expected a ribbon, got \(draw.kind)")
            return
        }
        #expect(draw.shading == nil)
    }

    /// Custom shading functions link binary, so a new one does not rebuild the pipeline.
    @Test func customShadingLinksBinary() throws {
        let draw = try plan { $0.edit(ShadingModule.self) { $0.model = .custom(function: ShadingModule.template) } }
        #expect(draw.shading?.reference.name == "rimLight")
        #expect(draw.shading?.linking == .binary)
        #expect(draw.shadingParameters.count >= ParticleFunction.minimumParameterCount)
    }

    /// Sorted emitters draw after unsorted ones, farthest first.
    @Test func sortedEmittersDrawLastFarthestFirst() throws {
        func emitter(z: Float, sorted: Bool) -> EmitterModules {
            var settings = EmitterModules.standard
            settings.edit(RateModule.self) { $0.birthRate = 0 }
            settings.edit(ShapeModule.self) { $0.position = [0, 0, z] }
            settings.edit(SpriteModule.self) { $0.sortMode = sorted ? .backToFront : .none }
            return settings
        }
        let system = try ParticleSystemRuntime(modules: [emitter(z: 1, sorted: true), emitter(z: 0, sorted: false), emitter(z: -2, sorted: true)], capacity: 8)
        system.burst(8)
        // A debug view records each draw's emitter index.
        system.debugView = .emitter
        let draws = try system.planDraws(projection: projection, view: view, sceneDepth: nil)
        // The unsorted emitter (1) first; then the sorted one farther from the camera (2, at z = -2) before the nearer one (0).
        #expect(draws.map(\EmitterDraw.uniforms.debugEmitterIndex) == [1, 2, 0])
    }
}
