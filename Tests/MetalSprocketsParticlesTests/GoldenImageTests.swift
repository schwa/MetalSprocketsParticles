import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing
import UniformTypeIdentifiers

// GPU rasterization and float precision vary slightly across hardware; see MetalSprocketsAddOns.
private let psnrThreshold = 30.0

@Suite(.serialized)
struct GoldenImageTests {
    func render(
        emitter: ParticleEmitter = .fountain,
        seed: UInt32 = 0,
        frames: Int,
        colliders: Bool = true,
        configure: (ParticleSystem) throws -> Void = { _ in }
    ) throws -> CGImage {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, capacity: 50_000, emitter: emitter, seed: seed)
        try configure(system)
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<frames {
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass {
                    if colliders {
                        try system.renderColliders(projection: projection, view: view)
                    }
                    try system.render(projection: projection, view: view)
                }
            })
        }
        return try #require(rendering).cgImage
    }

    @Test func fountainEarly() throws {
        #expect(try render(frames: 30).matchesGolden(named: "fountain-early"))
    }

    @Test func fountainSettled() throws {
        #expect(try render(frames: 180).matchesGolden(named: "fountain-settled"))
    }

    // Guards against a threshold so loose that any particle render passes.
    @Test func differentSeedDoesNotMatch() throws {
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Golden Images")
        let outcome = try GoldenImageComparison(imageDirectory: directory, options: .none, psnrThreshold: psnrThreshold)
            .compare(image: try render(seed: 99, frames: 180), toGoldenImageNamed: "fountain-settled")
        print("differentSeedDoesNotMatch PSNR: \(outcome.psnr)")
        #expect(!outcome.isMatch)
    }

    @Test(arguments: [(ParticleBlendMode.additive, "additive"), (.screen, "screen"), (.opaque, "opaque")])
    func blendModes(mode: ParticleBlendMode, name: String) throws {
        var emitter = ParticleEmitter.fountain
        emitter.blendMode = mode
        #expect(try render(emitter: emitter, frames: 120, colliders: false).matchesGolden(named: "fountain-blend-\(name)"))
    }

    // Blending lives in the pipeline descriptor; make sure the pipeline cache does not reuse the old one.
    @Test func blendModeChangeOnSameRendererTakesEffect() throws {
        let size = CGSize(width: 160, height: 90)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, capacity: 5_000, emitter: .fountain, seed: 0)
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        for _ in 0..<60 {
            _ = try renderer.render(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        func draw() throws -> CGImage {
            try renderer.render(try RenderPass { try system.render(projection: projection, view: view) }).cgImage
        }
        let alpha = try draw()
        system.emitter.blendMode = .additive
        let additive = try draw()
        #expect(try ImageComparison().compare(alpha, additive).psnr < psnrThreshold)
    }

    @Test func rotatedBoxAndCapsule() throws {
        var emitter = ParticleEmitter.fountain
        emitter.colliders = [
            .plane(normal: [0, 1, 0], distance: 0),
            .box(center: [0, 2.6, 0], halfExtents: [0.8, 0.1, 0.5], rotation: simd_quatf(angle: 0.5, axis: [0, 0, 1])),
            .capsule(start: [-1.5, 0.3, 0.5], end: [1.5, 0.3, -0.5], radius: 0.25),
        ]
        #expect(try render(emitter: emitter, frames: 120).matchesGolden(named: "rotated-box-and-capsule"))
    }

    @Test func texturedSpinningSprites() throws {
        var emitter = ParticleEmitter.fountain
        emitter.birthRate = 2_000
        emitter.sizeStart = 0.12
        emitter.sizeEnd = 0.06
        emitter.angleVariation = .pi
        emitter.angularSpeed = 4
        emitter.angularSpeedVariation = 2
        let image = try render(emitter: emitter, frames: 120, colliders: false) { system in
            // An arrow pointing up, so rotation is visible.
            system.texture = try makeSpriteSheet(device: system.device, rows: 1, columns: 1) { context, _, rect in
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.move(to: CGPoint(x: rect.midX, y: rect.minY + 4))
                context.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 4))
                context.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 4))
                context.fillPath()
            }
        }
        #expect(try image.matchesGolden(named: "textured-spinning-sprites"))
    }

    @Test func spriteSheetAnimation() throws {
        var emitter = ParticleEmitter.fountain
        emitter.birthRate = 4_000
        emitter.sizeStart = 0.08
        emitter.sizeEnd = 0.08
        emitter.colorStart = [1, 1, 1, 1]
        emitter.colorEnd = [1, 1, 1, 0.3]
        emitter.imageSequence = ImageSequence(rows: 2, columns: 2, frameRate: 2)
        let image = try render(emitter: emitter, frames: 120, colliders: false) { system in
            system.texture = try makeSpriteSheet(device: system.device, rows: 2, columns: 2) { context, index, rect in
                context.setFillColor(frameColors[index])
                context.fillEllipse(in: rect.insetBy(dx: 6, dy: 6))
            }
        }
        #expect(try image.matchesGolden(named: "sprite-sheet-animation"))
    }

    @Test func overLifeCurves() throws {
        var emitter = ParticleEmitter.fountain
        emitter.colorOverLife = ParticleCurve([
            .init(0, [1, 1, 0.8, 1]),
            .init(0.15, [1, 0.6, 0.1, 1]),
            .init(0.5, [0.8, 0.15, 0.05, 1]),
            .init(1, [0.2, 0.2, 0.25, 1]),
        ])
        // Puff up, then shrink away.
        emitter.sizeOverLife = ParticleCurve([.init(0, 0.01), .init(0.3, 0.06), .init(1, 0.005)])
        emitter.opacityOverLife = .power(from: 1, to: 0, exponent: 3)
        #expect(try render(emitter: emitter, frames: 120, colliders: false).matchesGolden(named: "over-life-curves"))
    }

    @Test func fountainWithoutColliderWireframes() throws {
        #expect(try render(frames: 120, colliders: false).matchesGolden(named: "fountain-no-wireframes"))
    }
}

extension CGImage {
    /// Compares against `Golden Images/<name>.png` in the test bundle. On mismatch or a missing golden, writes the
    /// render to `/tmp/<name>.png` so it can be inspected or promoted.
    func matchesGolden(named name: String) throws -> Bool {
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Golden Images")
        let comparison = GoldenImageComparison(imageDirectory: directory, options: .none, psnrThreshold: psnrThreshold)
        let isMatch = (try? comparison.image(image: self, matchesGoldenImageNamed: name)) ?? false
        if !isMatch {
            let url = URL(fileURLWithPath: "/tmp/\(name).png")
            try writePNG(to: url)
            print("Golden image \"\(name)\" did not match. Render written to \(url.path)")
        }
        return isMatch
    }

    func writePNG(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
