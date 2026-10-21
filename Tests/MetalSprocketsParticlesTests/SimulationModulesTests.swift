import Foundation
import Metal
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import Testing

/// Modules write the simulation uniforms (#226).
@Suite(.serialized, .requiresMetal4)
struct SimulationModulesTests {
    func uniforms(_ modules: EmitterModules, forcesPlane: Bool = false, motion: ParticleSystemRuntime.SpawnMotion = .init()) throws -> SimulationUniforms {
        let system = try ParticleSystemRuntime(capacity: 4, modules: modules)
        system.emitters[0].forcesPlane = forcesPlane
        return system.uniforms(for: system.emitters[0], deltaTime: 0, motion: motion, spawn: .init(cursor: 0, count: 0, serial: 0))
    }

    /// With no modules, uniforms hold the neutral values: nothing moves, default lifetime and bounce.
    @Test func noModulesGiveNeutralUniforms() throws {
        let result = try uniforms(EmitterModules())
        let neutral = ParticleEmitter.neutral
        #expect(result.velocity == .zero)
        #expect(result.gravity == .zero)
        #expect(result.drag == 0)
        #expect(result.lifetimeMinimum == neutral.lifetime.lowerBound)
        #expect(result.lifetimeMaximum == neutral.lifetime.upperBound)
        #expect(result.restitution == neutral.restitution)
        #expect(result.constrainsToPlane == 0)
        #expect(result.ordersBirths == 0)
    }

    @Test func modulesWriteTheirFields() throws {
        let modules = EmitterModules {
            VelocityModule(velocity: [1, 2, 3], spread: 0.5, speedVariation: -1)
            GravityModule(acceleration: [0, -2, 0])
            CollisionModule(restitution: 0.9, radius: -1)
            RibbonModule(ribbon: ParticleRibbon())
            ShadingModule(model: .foil(settings: ParticleFoil(shininess: 40)))
        }
        let result = try uniforms(modules)
        #expect(result.velocity == [1, 2, 3])
        #expect(result.velocitySpread == 0.5)
        #expect(result.variation.speed == 0) // Clamped.
        #expect(result.gravity == [0, -2, 0])
        #expect(result.restitution == 0.9)
        #expect(result.collisionRadius == 0) // Clamped.
        #expect(result.ordersBirths == 1)
        #expect(result.glintShininess == 40)
    }

    /// The plane follows the emitter's motion, from the module or from the runtime's 2D mode.
    @Test func planeConstraintFollowsMotion() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = [1, 2, 3, 1]
        let motion = ParticleSystemRuntime.SpawnMotion(transform: transform)
        for result in [try uniforms(EmitterModules { PlaneConstraintModule() }, motion: motion), try uniforms(EmitterModules(), forcesPlane: true, motion: motion)] {
            #expect(result.constrainsToPlane == 1)
            #expect(result.planePoint == [1, 2, 3])
            #expect(result.planeNormal == [0, 0, 1])
        }
    }

    /// Assigning flat settings lifts modules, so code that edits settings directly still drives the uniforms.
    @Test func settingFlatSettingsUpdatesModules() throws {
        let system = try ParticleSystemRuntime(capacity: 4, modules: .standard)
        system.emitters[0].settings.gravity = [0, -1, 0]
        let uniforms = system.uniforms(for: system.emitters[0], deltaTime: 0, motion: .init(), spawn: .init(cursor: 0, count: 0, serial: 0))
        #expect(uniforms.gravity == [0, -1, 0])
    }

    /// A disabled module writes nothing: the uniform keeps its neutral value.
    @Test func disabledModulesContributeNothing() throws {
        var modules = EmitterModules(ParticleEmitter())
        let index = try #require(modules.update.firstIndex { $0.module.kind == GravityModule.kind })
        modules.update[index].isEnabled = false
        let system = try ParticleSystemRuntime(capacity: 4, modules: modules)
        let uniforms = system.uniforms(for: system.emitters[0], deltaTime: 0, motion: .init(), spawn: .init(cursor: 0, count: 0, serial: 0))
        #expect(uniforms.gravity == .zero)
    }
}

/// Modules write their part of each draw (#226).
@Suite(.serialized, .requiresMetal4)
struct DrawModulesTests {
    func draw(_ modules: EmitterModules) throws -> EmitterDraw {
        let system = try ParticleSystemRuntime(capacity: 4, modules: modules)
        let lighting = EmitterDraw.Lighting(ambient: .zero, lightCount: 0, particleLightCount: 0)
        return EmitterDraw(emitter: system.emitters[0], projection: matrix_identity_float4x4, view: matrix_identity_float4x4, lighting: lighting, hasSceneDepth: false)
    }

    @Test func noModulesDrawWhiteAlphaBlendedWithNoExtraColors() throws {
        let result = try draw(EmitterModules())
        #expect(result.blendMode == EmitterModules.neutralSprite.blendMode)
        #expect(result.extraColorCurves.allSatisfy { $0 == .one })
        #expect(result.uniforms.hasSpeedColor == 0)
        #expect(result.uniforms.sizeScale == 1)
        #expect(result.modules.shading == nil)
    }

    @Test func colorModulesFillTheirOwnExtraCurve() throws {
        let red = ParticleCurve<SIMD4<Float>>.constant([1, 0, 0, 1])
        let result = try draw(EmitterModules {
            ColorBySpeedModule(curve: red, range: 1...2)
            ColorByPositionModule(curve: red, atBirth: true)
        })
        let samples = Int(PARTICLE_CURVE_SAMPLES)
        #expect(result.extraColorCurves[0..<samples].allSatisfy { $0 == [1, 0, 0, 1] })
        #expect(result.extraColorCurves[samples..<(2 * samples)].allSatisfy { $0 == .one })
        #expect(result.uniforms.hasSpeedColor == 1)
        #expect(result.uniforms.speedColorRange == [1, 2])
        // At birth, the simulation colors the particle instead.
        #expect(result.uniforms.hasPositionColor == 0)
    }

    /// Disabled modules write nothing and are not handed to the planner.
    @Test func disabledModulesAreSkipped() throws {
        var modules = EmitterModules { ShadingModule(model: .lit) }
        modules.render[0].isEnabled = false
        let result = try draw(modules)
        #expect(result.uniforms.isLit == 0)
        #expect(result.modules.shading == nil)
    }
}
