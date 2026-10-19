import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ParticleLightEmissionTests {
    func still(at position: SIMD3<Float>, _ configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = position
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        configure(&emitter)
        return emitter
    }

    @Test func liveParticlesBecomeLightsWhereTheyAre() throws {
        let runner = try Runner()
        let glowing = still(at: [1, 2, 3]) { $0.light = ParticleLightEmission(count: 4, color: [1, 0.5, 0], intensity: 2, range: 3) }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: glowing)
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let lights = system.emittedLights()
        #expect(lights.count == 4)
        for light in lights {
            guard case let .point(position, color, _, range) = light else {
                Issue.record("Expected point lights")
                continue
            }
            #expect(simd_distance(position, [1, 2, 3]) < 1e-4)
            // Nearly full remaining life, so nearly full color.
            #expect(simd_distance(color, [2, 1, 0]) < 0.01)
            #expect(range == 3)
        }
    }

    /// A few live particles in a big ring: lights come from where they are, not from evenly spaced empty slots.
    @Test func sparseEmittersStillLightEveryLight() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1_000, emitter: still(at: .zero) { $0.light = ParticleLightEmission(count: 8) })
        system.burst(20)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        #expect(system.emittedLights().count == 8)
    }

    /// Four particles a frame apart along x; color fades from white to black over life, so the newest is brightest.
    @Test func lightsPickTheBrightestParticle() throws {
        func lightX(picksBrightest: Bool) throws -> Float {
            let runner = try Runner()
            let settings = still(at: .zero) {
                $0.colorOverLife = .linear(from: [1, 1, 1, 1], to: [0, 0, 0, 1])
                $0.lifetime = 1...1
                $0.light = ParticleLightEmission(count: 1, picksBrightest: picksBrightest)
            }
            let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, emitter: settings)
            for x in 0..<4 {
                system.burst(1, at: [Float(x), 0, 0])
                try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
            }
            guard case let .point(position, _, _, _) = try #require(system.emittedLights().first) else {
                Issue.record("Expected a point light")
                return .nan
            }
            return position.x
        }
        #expect(try lightX(picksBrightest: true) == 3)
        #expect(try lightX(picksBrightest: false) == 0)
    }

    @Test func noLiveParticlesNoLights() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: still(at: .zero) { $0.light = ParticleLightEmission() })
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        #expect(system.particleLightCount == 4)
        #expect(system.emittedLights().isEmpty)
    }

    @Test func lightsAreCappedAcrossTheSystem() throws {
        let many = still(at: .zero) { $0.light = ParticleLightEmission(count: 10) }
        let system = try ParticleSystemRuntime(emitters: [many, many], capacity: 64)
        system.planParticleLights()
        #expect(system.particleLightCount == Int(PARTICLE_MAX_PARTICLE_LIGHTS))
        #expect(system.particleLightGathers.map(\.count) == [10, 6])
    }

    /// A lit gray particle next to a glowing one, with no other light: brighter than with the glow turned off.
    @Test func particleLightsLightLitParticles() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        func brightness(glowing: Bool) throws -> Int {
            let lit = still(at: .zero) {
                $0.isLit = true
                $0.sizeOverLife = .constant(1)
                $0.colorOverLife = .constant([1, 1, 1, 1])
                $0.blendMode = .opaque
            }
            let glow = still(at: [0, 0, 0.6]) {
                $0.sizeOverLife = .constant(0.001)
                $0.light = glowing ? ParticleLightEmission(count: 1, color: [1, 1, 1], intensity: 1, range: 3) : nil
            }
            let system = try ParticleSystemRuntime(device: renderer.device, emitters: [lit, glow], capacity: 1)
            system.ambientLight = .zero
            system.emitters.forEach { $0.burst(1) }
            let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
            let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
            let image = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage
            return Int(try image.rgbaPixels()[32 * 64 + 32].x)
        }
        let dark = try brightness(glowing: false)
        let bright = try brightness(glowing: true)
        #expect(dark < 10)
        #expect(bright > 100)
    }

    @Test func lightEmissionRoundTripsThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.light = ParticleLightEmission(count: 3, color: [0.2, 1, 0.4], intensity: 1.5, range: 2.5)
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).light == emitter.light)
    }
}
