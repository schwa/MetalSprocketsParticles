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
    func render(emitter: ParticleEmitter = .fountain, seed: UInt32 = 0, frames: Int, colliders: Bool = true) throws -> CGImage {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, capacity: 50_000, emitter: emitter, seed: seed)
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
