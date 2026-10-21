import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `colorBySpeed`, `alternateColorOverLife`, and `colorByPosition`.
@Suite(.serialized, .requiresMetal4)
struct ColorGradientTests {
    /// A particle sitting at `position` with `velocity` (the step is 0 s, so it does not move).
    func still(at position: SIMD3<Float>, velocity: SIMD3<Float> = .zero, _ configure: (inout EmitterModules) -> Void = { _ in }) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(ShapeModule.self) { $0.position = position }
        emitter.edit(VelocityModule.self) { $0.velocity = velocity }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(VelocityModule.self) { $0.speedVariation = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter.edit(SpriteModule.self) { $0.blendMode = .opaque }
        emitter.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.15) }
        emitter.edit(ColorOverLifeModule.self) { $0.color = .constant([1, 1, 1, 1]) }
        configure(&emitter)
        return emitter
    }

    /// Renders one particle per emitter into a 128×64 view and returns the RGB at each emitter's position, which must
    /// be at y = 0 and x in -1.5...1.5.
    func colors(_ emitters: [EmitterModules], burst: Int = 1) throws -> [SIMD3<Int>] {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        let system = try ParticleSystemRuntime(device: renderer.device, modules: emitters, capacity: burst)
        system.emitters.forEach { $0.burst(burst) }
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        let pixels = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.rgbaPixels()
        return emitters.map { emitter in
            let clip = projection * view * SIMD4(emitter[ShapeModule.self]?.position ?? .zero, 1)
            let x = Int((clip.x / clip.w * 0.5 + 0.5) * 128)
            let pixel = pixels[32 * 128 + min(max(x, 0), 127)]
            return SIMD3(Int(pixel.x), Int(pixel.y), Int(pixel.z))
        }
    }

    @Test func colorBySpeedMapsSpeedThroughTheRange() throws {
        func bySpeed(_ emitter: inout EmitterModules) {
            emitter[ColorBySpeedModule.self] = ColorBySpeedModule(curve: .linear(from: [0, 0, 1, 1], to: [1, 0, 0, 1]), range: 1...5)
        }
        let result = try colors([
            still(at: [-1, 0, 0], velocity: [0, 0.5, 0], bySpeed),
            still(at: [1, 0, 0], velocity: [0, 9, 0], bySpeed),
        ])
        #expect(result[0].z > 200 && result[0].x < 30) // Below the range: blue.
        #expect(result[1].x > 200 && result[1].z < 30) // Above it: red.
    }

    @Test func colorByPositionFollowsTheAxis() throws {
        func byPosition(_ emitter: inout EmitterModules) {
            emitter[ColorByPositionModule.self] = ColorByPositionModule(curve: .linear(from: [0, 1, 0, 1], to: [1, 0, 1, 1]), start: [-1, 0, 0], end: [1, 0, 0])
        }
        let result = try colors([still(at: [-1, 0, 0], byPosition), still(at: [0, 0, 0], byPosition), still(at: [1, 0, 0], byPosition)])
        #expect(result[0].y > 200 && result[0].x < 30)
        // Halfway: an even mix (the exact value depends on the target's sRGB encoding).
        #expect(abs(result[1].x - result[1].y) < 10 && result[1].x > 60 && result[1].x < 230)
        #expect(result[2].x > 200 && result[2].y < 30)
    }

    @Test func alternateGradientsBlendPerParticle() throws {
        // Many particles on one spot would hide each other, so spread them along x and look at all lit pixels.
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        let emitter = still(at: .zero) {
            $0.edit(ShapeModule.self) { $0.shape = .box(size: [3, 1, 0]) }
            $0.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.04) }
            $0.edit(ColorOverLifeModule.self) { $0.color = .constant([1, 0, 0, 1]) }
            $0.edit(ColorOverLifeModule.self) { $0.alternate = .constant([0, 0, 1, 1]) }
        }
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 200, modules: emitter)
        system.burst(200)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        let lit = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.rgbaPixels().filter { Int($0.x) + Int($0.z) > 100 }
        #expect(lit.contains { $0.x > 200 && $0.z < 60 }) // Mostly red.
        #expect(lit.contains { $0.z > 200 && $0.x < 60 }) // Mostly blue.
        #expect(lit.contains { $0.x > 70 && $0.z > 70 }) // In between.
    }

    /// Born at x = -1 (green end), then moved to x = +1 (magenta end): at birth keeps green; current position is magenta.
    @Test func birthPositionColorStaysWithTheParticle() throws {
        func color(atBirth: Bool) throws -> SIMD3<Int> {
            let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
            var emitter = still(at: [-1, 0, 0], velocity: [20, 0, 0])
            emitter[ColorByPositionModule.self] = ColorByPositionModule(curve: .linear(from: [0, 1, 0, 1], to: [1, 0, 1, 1]), start: [-1, 0, 0], end: [1, 0, 0], atBirth: atBirth)
            emitter.edit(DragModule.self) { $0.amount = 0 }
            let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, modules: emitter)
            system.burst(1)
            let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
            let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
            // Steps are capped at 1/30 s, so four of them carry it 2 to 2.7 units right; drawn where it ends up.
            var image: CGImage?
            for _ in 0..<4 {
                image = try renderer.render(Group {
                    try system.simulate(deltaTime: 1.0 / 30.0)
                    try RenderPass { try system.render(projection: projection, view: view) }
                }).cgImage
            }
            let pixels = try #require(image).rgbaPixels()
            let particle = system.buffer.contents().bindMemory(to: Particle.self, capacity: 1)[0]
            let clip = projection * view * SIMD4(particle.position.x, particle.position.y, particle.position.z, 1)
            let x = Int((clip.x / clip.w * 0.5 + 0.5) * 128)
            let pixel = pixels[32 * 128 + min(max(x, 0), 127)]
            return SIMD3(Int(pixel.x), Int(pixel.y), Int(pixel.z))
        }
        let atBirth = try color(atBirth: true)
        let current = try color(atBirth: false)
        #expect(atBirth.y > 200 && atBirth.x < 60)
        #expect(current.x > 200 && current.y < 60)
    }

    @Test func gradientsRoundTripThroughEffectFiles() throws {
        var emitter = EmitterModules.standard
        emitter[ColorBySpeedModule.self] = ColorBySpeedModule(curve: .linear(from: [1, 1, 1, 1], to: [1, 0, 0, 1]), range: 2...8)
        emitter.edit(ColorOverLifeModule.self) { $0.alternate = .constant([0, 1, 0, 1]) }
        emitter[ColorByPositionModule.self] = ColorByPositionModule(curve: .constant([0.5, 0.5, 0.5, 1]), start: [1, 2, 3], end: [4, 5, 6])
        #expect(try roundTrip(emitter) == emitter)
    }
}
