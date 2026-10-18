import CoreGraphics
import Metal
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Makes a premultiplied RGBA sprite sheet. `draw` paints one cell, given its index and the cell rect.
func makeSpriteSheet(device: MTLDevice, rows: Int, columns: Int, cellSize: Int = 64, draw: (CGContext, Int, CGRect) -> Void) throws -> MTLTexture {
    let width = columns * cellSize
    let height = rows * cellSize
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    // CoreGraphics is y-up; flip so cell 0 is top-left like the texture.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    for index in 0..<(rows * columns) {
        let rect = CGRect(x: (index % columns) * cellSize, y: (index / columns) * cellSize, width: cellSize, height: cellSize)
        context.saveGState()
        draw(context, index, rect)
        context.restoreGState()
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: try #require(context.data), bytesPerRow: width * 4)
    return texture
}

/// Red, green, blue, white.
let frameColors: [CGColor] = [
    CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
    CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
    CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
]

extension CGImage {
    /// RGBA of the center pixel, 0...255.
    func centerPixel() throws -> SIMD4<UInt8> {
        var pixel = SIMD4<UInt8>.zero
        try withUnsafeMutableBytes(of: &pixel) { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(self, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
        return pixel
    }
}

@Suite(.serialized)
struct SpriteTests {
    /// One large still particle at the origin, viewed head-on, rendered after `steps` steps.
    func renderSingleParticle(texture: (MTLDevice) throws -> MTLTexture, sequence: ImageSequence?, steps: Int) throws -> CGImage {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.colorStart = [1, 1, 1, 1]
        emitter.colorEnd = [1, 1, 1, 1]
        emitter.sizeStart = 0.5
        emitter.sizeEnd = 0.5
        emitter.imageSequence = sequence
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter, seed: 0)
        system.texture = try texture(renderer.device)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<steps {
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass { try system.render(projection: projection, view: view) }
            })
        }
        return try #require(rendering).cgImage
    }

    func colorSheet(_ device: MTLDevice) throws -> MTLTexture {
        try makeSpriteSheet(device: device, rows: 2, columns: 2) { context, index, rect in
            context.setFillColor(frameColors[index])
            context.fill(rect)
        }
    }

    // 10 fps over 4 frames. After 28 steps the particle is 0.45...0.467 s old: raw frame 4.
    @Test(arguments: [
        (ParticleImageSequenceMode.repeat, SIMD4<UInt8>(255, 0, 0, 255)),   // 4 wraps to frame 0
        (.clamp, SIMD4<UInt8>(255, 255, 255, 255)),                         // holds frame 3
        (.autoReverse, SIMD4<UInt8>(0, 0, 255, 255)),                       // 0 1 2 3 2: frame 2
    ])
    func sequenceModes(mode: ParticleImageSequenceMode, expected: SIMD4<UInt8>) throws {
        let image = try renderSingleParticle(texture: colorSheet, sequence: ImageSequence(rows: 2, columns: 2, frameRate: 10, mode: mode), steps: 28)
        #expect(try image.centerPixel() == expected)
    }

    @Test func frameAdvancesWithAge() throws {
        // 9 steps: 0.133...0.15 s old, frame 1.
        let image = try renderSingleParticle(texture: colorSheet, sequence: ImageSequence(rows: 2, columns: 2, frameRate: 10), steps: 9)
        #expect(try image.centerPixel() == SIMD4<UInt8>(0, 255, 0, 255))
    }

    @Test func textureWithoutSequenceUsesWholeImage() throws {
        // With no sequence the full 2x2 sheet covers the quad; the center pixel sits on the corner of four cells, so
        // instead sample a sheet that is a single solid color.
        let image = try renderSingleParticle(texture: { device in
            try makeSpriteSheet(device: device, rows: 1, columns: 1) { context, _, rect in
                context.setFillColor(frameColors[1])
                context.fill(rect)
            }
        }, sequence: nil, steps: 1)
        #expect(try image.centerPixel() == SIMD4<UInt8>(0, 255, 0, 255))
    }
}
