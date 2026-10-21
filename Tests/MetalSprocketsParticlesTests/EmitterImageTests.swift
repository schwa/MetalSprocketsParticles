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

@Suite(.serialized, .requiresMetal4)
struct EmitterImageTests {
    /// A 40×20 PNG: the left half filled with `left`, the right half with `right` (nil = transparent).
    func png(left: CGColor?, right: CGColor?) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for (color, x) in [(left, 0), (right, 20)] {
            if let color {
                context.setFillColor(color)
                context.fill(CGRect(x: x, y: 0, width: 20, height: 20))
            }
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    @Test func alphaWeightingEmitsOnlyFromOpaquePixelsInTheirColor() throws {
        let image = EmitterImage(data: try png(left: red, right: nil), width: 4, pointCount: 500)
        let points = image.points()
        #expect(points.count == 500)
        // 4 units wide, 2 tall, centered: the opaque half is x in -2...0.
        #expect(points.allSatisfy { $0.position.x >= -2 && $0.position.x <= 0 && abs($0.position.y) <= 1 && $0.position.z == 0 })
        #expect(points.allSatisfy { $0.color == [1, 0, 0, 1] })
    }

    @Test func brightnessWeightingSkipsBlack() throws {
        let image = EmitterImage(data: try png(left: black, right: white), width: 4, pointCount: 500, weighting: .brightness, usesColors: false)
        let points = image.points()
        #expect(points.allSatisfy { $0.position.x >= 0 && $0.color == nil })
    }

    @Test func samplingIsRepeatable() throws {
        let image = EmitterImage(data: try png(left: red, right: white), pointCount: 100, weighting: .brightness)
        let first = image.points()
        let second = image.points()
        #expect(first == second)
    }

    @Test func badDataGivesNoPoints() {
        #expect(EmitterImage(data: Data([1, 2, 3])).points().isEmpty)
    }

    @Test func appliedImagesSpawnTintedParticles() throws {
        let runner = try Runner()
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .points }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        var description = EmitterDescription("Image", modules: emitter, capacity: 64)
        description.image = EmitterImage(data: try png(left: red, right: nil), width: 4, pointCount: 200)
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, modules: .standard)
        try system.apply([description])
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        #expect((0..<64).allSatisfy { pointer[$0].position.x <= 0 && pointer[$0].properties.w.bitPattern == 0xFF00_00FF })
    }

    @Test func imagesRoundTripThroughEffectFiles() throws {
        var description = EmitterDescription("Image", modules: .standard)
        description.image = EmitterImage(data: try png(left: red, right: nil), width: 3, pointCount: 10, weighting: .brightness, usesColors: false)
        let resources = EffectResources()
        let decoded = try resources.decoder().decode(EmitterDescription.self, from: resources.encoder().encode(description))
        #expect(decoded.image == description.image)
    }
}
