import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// `ParticleEmitter.foil`: mesh particles glint when they turn to catch the light and shift color with angle (#155).
@Suite(.serialized, .requiresMetal4)
struct FoilTests {
    /// The color at the middle of the view for one large coin turned to `angle`.
    func centerColor(angle: Float, foil: ParticleFoil?) throws -> SIMD3<Float> {
        var coin = ParticleEmitter()
        coin.shape = .point
        coin.position = [0, 0, 0]
        coin.velocity = .zero
        coin.velocitySpread = 0
        coin.gravity = .zero
        coin.birthRate = 0
        coin.lifetime = 10...10
        coin.angle = angle
        coin.particleMesh = .coin
        coin.sizeOverLife = .constant(0.8)
        // Dark, so the glint stands out instead of clipping at white with the base color.
        coin.colorOverLife = .constant([0.3, 0.25, 0.12, 1])
        coin.blendMode = .opaque
        coin.foil = foil
        // Light from behind the camera: the glint peaks when the coin faces the camera.
        let system = ParticleSystem(
            "Coin", layers: [EmitterDescription("Coin", settings: coin, capacity: 1)], lights: [.directional(direction: [0, 0, -1])], cameraEye: [0, 0, 3], cameraTarget: .zero
        )
        let size = CGSize(width: 64, height: 64)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        player.runtime.burst(1)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<3 {
            rendering = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        let image = try #require(rendering).cgImage
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        let pixel = try #require(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return SIMD3(Float(pixel[0]), Float(pixel[1]), Float(pixel[2])) / 255
    }

    func brightness(_ color: SIMD3<Float>) -> Float {
        color.max()
    }

    @Test func foilGlintsAtSomeAnglesAndShiftsColor() throws {
        let angles = (0..<36).map { Float($0) / 36 * 2 * .pi }
        let foil = try angles.map { try centerColor(angle: $0, foil: ParticleFoil(glint: 3, shininess: 48, iridescence: 0.6)) }
        let plain = try angles.map { try centerColor(angle: $0, foil: nil) }
        let foilBrightness = foil.map(brightness).sorted()
        let plainBrightness = plain.map(brightness).sorted()
        // A glint: the brightest angle far above the typical one, much more than plain shading varies.
        let foilPeak = try #require(foilBrightness.last) / max(foilBrightness[foilBrightness.count / 2], 0.01)
        let plainPeak = try #require(plainBrightness.last) / max(plainBrightness[plainBrightness.count / 2], 0.01)
        #expect(foilPeak > 2, "foil \(foilBrightness)")
        #expect(foilPeak > plainPeak * 1.5, "foil \(foilPeak), plain \(plainPeak)")
        // Iridescence: the color's balance (not just its brightness) changes with angle.
        let balances = foil.filter { brightness($0) > 0.05 }.map { $0 / brightness($0) }
        let spread = zip(balances, balances.dropFirst()).map { simd_distance($0, $1) }.max() ?? 0
        #expect(spread > 0.15, "balances \(balances)")
    }

    @Test func foilRoundTripsThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.foil = ParticleFoil(glint: 2, shininess: 30, iridescence: 0.4)
        let decoded = try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter))
        #expect(decoded.foil == emitter.foil)
    }
}
