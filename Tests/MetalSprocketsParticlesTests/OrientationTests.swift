import CoreGraphics
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// Width and height in pixels of the lit region through the image center.
struct Extent: Equatable {
    var width: Int
    var height: Int
}

extension CGImage {
    func rgbaPixels() throws -> [SIMD4<UInt8>] {
        var pixels = [SIMD4<UInt8>](repeating: .zero, count: width * height)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    func centerExtent(threshold: UInt8 = 40) throws -> Extent {
        let pixels = try rgbaPixels()
        func lit(_ x: Int, _ y: Int) -> Bool { pixels[y * width + x].x > threshold }
        let row = height / 2
        let column = width / 2
        return Extent(
            width: (0..<width).filter { lit($0, row) }.count,
            height: (0..<height).filter { lit(column, $0) }.count
        )
    }
}

@Suite(.serialized, .requiresMetal4)
struct OrientationTests {
    /// One white particle at the origin moving at `velocity`, rendered after one step from `eye`.
    func render(orientation: ParticleOrientation, velocity: SIMD3<Float> = .zero, eye: SIMD3<Float> = [0, 0, 3]) throws -> CGImage {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 128))
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = velocity
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.sizeOverLife = .constant(0.3)
        emitter.orientation = orientation
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter, seed: 0)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: eye, at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        // Zero time step: the particle spawns but stays at the origin.
        return try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage
    }

    @Test func billboardIsRoundFromAnyAngle() throws {
        let front = try render(orientation: .billboard).centerExtent()
        let above = try render(orientation: .billboard, eye: [0, 2.1, 2.1]).centerExtent()
        #expect(front.width > 10)
        #expect(abs(front.width - front.height) <= 2)
        #expect(abs(above.width - above.height) <= 2)
    }

    @Test func yAlignedForeshortensFromAbove() throws {
        // Viewed from 45° above, an upright quad looks about cos 45° as tall as it is wide.
        let extent = try render(orientation: .yAligned, eye: [0, 2.1, 2.1]).centerExtent()
        #expect(Float(extent.height) < Float(extent.width) * 0.85)
    }

    @Test func velocityAlignedStretchesAlongMotion() throws {
        let still = try render(orientation: .velocityAligned(stretch: 1), velocity: [3, 0, 0]).centerExtent()
        let plain = try render(orientation: .velocityAligned(), velocity: [3, 0, 0]).centerExtent()
        // Moving along +x: 1 + 1 × 3 = 4× longer horizontally; the cross axis is unchanged.
        #expect(Float(still.width) > Float(plain.width) * 2.5)
        #expect(abs(still.height - plain.height) <= 2)
    }

    @Test func velocityAlignedFollowsDirection() throws {
        let extent = try render(orientation: .velocityAligned(stretch: 1), velocity: [0, 3, 0]).centerExtent()
        #expect(Float(extent.height) > Float(extent.width) * 2.5)
    }

    @Test func fixedPlaneSeenEdgeOnIsInvisible() throws {
        let edgeOn = try render(orientation: .fixed(normal: [0, 1, 0])).centerExtent()
        let faceOn = try render(orientation: .fixed(normal: [0, 0, 1])).centerExtent()
        #expect(edgeOn.height <= 1)
        #expect(faceOn.width > 10)
    }
}
