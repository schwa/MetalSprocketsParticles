import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// `minimumScreenSize` and `lodScalesSize` (#124).
@Suite(.serialized, .requiresMetal4)
struct ScreenSizeTests {
    /// Lit pixels of one opaque particle `distance` units in front of the camera, after `frames` frames.
    func litPixels(distance: Float, size: Float, frames: Int = 2, configure: (inout ParticleEmitter) -> Void = { _ in }) throws -> Int {
        let renderer = try OffscreenRenderer(size: CGSize(width: 200, height: 200))
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [0, 0, -distance]
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.blendMode = .opaque
        emitter.sizeOverLife = .constant(size)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        configure(&emitter)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter)
        system.burst(1)
        let view = matrix_identity_float4x4
        let projection = simd_float4x4.perspective(fovY: .pi / 2, aspect: 1, near: 0.1, far: 1_000)
        var image: CGImage?
        for _ in 0..<frames {
            image = try renderer.render(Group {
                try system.simulate(deltaTime: 0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage
        }
        return try #require(image).rgbaPixels().filter { $0.x > 128 }.count
    }

    @Test func farParticlesKeepAMinimumScreenSize() throws {
        // Half-size 0.01 at 100 units with a 90 degree view: a fraction of a pixel.
        #expect(try litPixels(distance: 100, size: 0.01) == 0)
        // Half-size at least 5% of the view height: a 20-pixel quad. Opaque keeps the soft dot's middle (coverage over
        // half, the inner 29% of the radius), a disc about 6 pixels across.
        let lit = try litPixels(distance: 100, size: 0.01) { $0.minimumScreenSize = 0.05 }
        #expect(lit > 15 && lit < 60)
    }

    @Test func nearParticlesAreNotShrunk() throws {
        let plain = try litPixels(distance: 2, size: 0.3)
        let withMinimum = try litPixels(distance: 2, size: 0.3) { $0.minimumScreenSize = 0.01 }
        #expect(plain == withMinimum)
    }

    @Test func lodGrowsParticlesItThinsOut() throws {
        func lod(_ emitter: inout ParticleEmitter) {
            emitter.lodNearDistance = 1
            emitter.lodFarDistance = 10
            emitter.lodFarRateScale = 0.25
        }
        // At the far distance the rate scale is 1/4, so sizes double and the area is about four times larger.
        let plain = try litPixels(distance: 20, size: 4, frames: 3, configure: lod)
        let grown = try litPixels(distance: 20, size: 4, frames: 3) {
            lod(&$0)
            $0.lodScalesSize = true
        }
        #expect(Double(grown) > Double(plain) * 3 && Double(grown) < Double(plain) * 5)
    }

    @Test func settingsRoundTripThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.minimumScreenSize = 0.003
        emitter.lodScalesSize = true
        let decoded = try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter))
        #expect(decoded.minimumScreenSize == 0.003 && decoded.lodScalesSize)
    }
}
