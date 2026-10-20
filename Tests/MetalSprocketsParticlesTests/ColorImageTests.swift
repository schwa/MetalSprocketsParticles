import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing
import UniformTypeIdentifiers

/// `ParticleEmitter.colorImage`: particles take the image's color under their current position (#123).
@Suite(.serialized, .requiresMetal4)
struct ColorImageTests {
    /// 40×20: red on the left half, blue on the right.
    func redBluePNG() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// The color of a white particle born at x = -1 after `steps` steps moving right at 15 units per second.
    func color(afterSteps steps: Int) throws -> SIMD3<Int> {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = [-1, 0, 0]
        emitter.velocity = [15, 0, 0]
        emitter.velocitySpread = 0
        emitter.speedVariation = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.blendMode = .opaque
        emitter.sizeOverLife = .constant(0.15)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        // 4 by 2 units centered on the origin: x < 0 is red, x > 0 is blue.
        emitter.colorImage = ParticleColorImage(data: try redBluePNG(), center: .zero, size: 4)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        var image: CGImage?
        for step in 0..<max(steps, 1) {
            image = try renderer.render(Group {
                try system.simulate(deltaTime: step < steps ? 1.0 / 30.0 : 0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage
        }
        let particle = system.buffer.contents().bindMemory(to: Particle.self, capacity: 1)[0]
        let clip = projection * view * SIMD4(particle.position.x, particle.position.y, particle.position.z, 1)
        let x = Int((clip.x / clip.w * 0.5 + 0.5) * 128)
        let pixel = try #require(image).rgbaPixels()[32 * 128 + min(max(x, 0), 127)]
        return SIMD3(Int(pixel.x), Int(pixel.y), Int(pixel.z))
    }

    @Test func particlesTakeTheImageColorWhereTheyAre() throws {
        // Just born, over the red half.
        let start = try color(afterSteps: 0)
        #expect(start.x > 200 && start.z < 40)
        // Four 1/30 s steps at 15 units per second: about 1.5 to 2 units right, over the blue half.
        let later = try color(afterSteps: 4)
        #expect(later.z > 200 && later.x < 40)
    }

    @Test func centeredImagesKeepTheirAspectRatio() throws {
        let image = ParticleColorImage(data: try redBluePNG(), center: [0, 1, 0], size: 4)
        #expect(image.width == [4, 0, 0])
        #expect(image.height == [0, 2, 0])
        #expect(image.origin == [-2, 0, 0])
    }

    @Test func colorImagesRoundTripThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.colorImage = ParticleColorImage(data: try redBluePNG(), center: .zero, size: 2)
        let resources = EffectResources()
        #expect(try resources.decoder().decode(ParticleEmitter.self, from: resources.encoder().encode(emitter)).colorImage == emitter.colorImage)
    }
}
