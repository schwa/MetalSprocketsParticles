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
        worldColliders: [Collider] = ParticleEmitter.fountainColliders(time: 0),
        forceFields: [ForceField] = [],
        configure: (ParticleSystem) throws -> Void = { _ in },
        perFrame: (ParticleSystem, Int) -> Void = { _, _ in }
    ) throws -> CGImage {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, capacity: 50_000, emitter: emitter, seed: seed)
        system.colliders = worldColliders
        system.forceFields = forceFields
        try configure(system)
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        var rendering: OffscreenRenderer.Rendering?
        for frame in 0..<frames {
            perFrame(system, frame)
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
        system.colliders = ParticleEmitter.fountainColliders(time: 0)
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
        let colliders: [Collider] = [
            .plane(normal: [0, 1, 0], distance: 0),
            .box(center: [0, 2.6, 0], halfExtents: [0.8, 0.1, 0.5], rotation: simd_quatf(angle: 0.5, axis: [0, 0, 1])),
            .capsule(start: [-1.5, 0.3, 0.5], end: [1.5, 0.3, -0.5], radius: 0.25),
        ]
        #expect(try render(frames: 120, worldColliders: colliders).matchesGolden(named: "rotated-box-and-capsule"))
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

    @Test func forceFields() throws {
        let fields: [ForceField] = [
            .vortex(center: .zero, strength: 6, radius: 2.5),
            .turbulence(strength: 4, scale: 1.2, speed: 0.5),
        ]
        #expect(try render(frames: 120, worldColliders: [.plane(normal: [0, 1, 0], distance: 0)], forceFields: fields).matchesGolden(named: "force-fields"))
    }

    @Test func velocityStretchedSparks() throws {
        var emitter = ParticleEmitter.fountain
        emitter.birthRate = 3_000
        emitter.velocity = [0, 6, 0]
        emitter.velocitySpread = 3
        emitter.orientation = .velocityAligned(stretch: 0.8)
        emitter.sizeOverLife = .constant(0.02)
        emitter.colorOverLife = .linear(from: [1, 0.9, 0.5, 1], to: [1, 0.3, 0.05, 0])
        emitter.blendMode = .additive
        #expect(try render(emitter: emitter, frames: 120).matchesGolden(named: "velocity-stretched-sparks"))
    }

    @Test func birthVariation() throws {
        var emitter = ParticleEmitter.fountain
        emitter.birthRate = 6_000
        emitter.sizeVariation = 0.8
        emitter.speedVariation = 1.5
        emitter.colorVariation = [0.15, 0.3, 0.2, 0]
        emitter.restitutionVariation = 0.3
        #expect(try render(emitter: emitter, frames: 120, colliders: false).matchesGolden(named: "birth-variation"))
    }

    @Test func movingEmitterTrail() throws {
        var emitter = ParticleEmitter.fountain
        emitter.velocity = [0, 0.5, 0]
        emitter.velocitySpread = 0.3
        emitter.gravity = [0, -0.5, 0]
        emitter.birthRate = 8_000
        emitter.inheritVelocity = 0.3
        let image = try render(emitter: emitter, frames: 120, worldColliders: [.plane(normal: [0, 1, 0], distance: 0)], perFrame: { system, frame in
            let angle = Float(frame) / 60 * 2.5
            var transform = matrix_identity_float4x4
            transform.columns.3 = [cos(angle) * 1.5, 1.5, sin(angle) * 1.5, 1]
            system.transform = transform
        })
        #expect(try image.matchesGolden(named: "moving-emitter-trail"))
    }

    @Test func fireSmokeAndEmbers() throws {
        var fire = ParticleEmitter()
        fire.position = [0, 0.1, 0]
        fire.radius = 0.25
        fire.velocity = [0, 1.2, 0]
        fire.velocitySpread = 0.3
        fire.gravity = [0, 1, 0]
        fire.lifetime = 0.5...1
        fire.birthRate = 6_000
        fire.blendMode = .additive
        fire.sizeOverLife = ParticleCurve([.init(0, 0.06), .init(0.4, 0.1), .init(1, 0.02)])
        fire.colorOverLife = ParticleCurve([
            .init(0, [1, 0.9, 0.5, 0.6]),
            .init(0.4, [1, 0.4, 0.05, 0.4]),
            .init(1, [0.4, 0.05, 0.02, 0]),
        ])

        var smoke = ParticleEmitter()
        smoke.position = [0, 1, 0]
        smoke.radius = 0.2
        smoke.velocity = [0, 0.8, 0]
        smoke.velocitySpread = 0.25
        smoke.gravity = [0, 0.2, 0]
        smoke.lifetime = 2...3.5
        smoke.birthRate = 400
        smoke.sizeOverLife = .linear(from: 0.1, to: 0.45)
        smoke.colorOverLife = .linear(from: [0.25, 0.25, 0.27, 0.25], to: [0.4, 0.4, 0.42, 0])
        smoke.warmupDuration = 2

        var embers = ParticleEmitter()
        embers.position = [0, 0.3, 0]
        embers.radius = 0.2
        embers.velocity = [0, 3, 0]
        embers.velocitySpread = 1
        embers.gravity = [0, -1, 0]
        embers.lifetime = 1...2.5
        embers.birthRate = 150
        embers.blendMode = .additive
        embers.orientation = .velocityAligned(stretch: 0.6)
        embers.sizeOverLife = .constant(0.012)
        embers.colorOverLife = .linear(from: [1, 0.6, 0.2, 1], to: [1, 0.2, 0.05, 0])

        let image = try render(
            emitter: smoke,
            frames: 120,
            colliders: false,
            worldColliders: [],
            forceFields: [.turbulence(strength: 1.5, scale: 1.5, speed: 0.6)]
        ) { system in
            // Smoke first so the additive fire and embers draw over it.
            try system.addEmitter(fire, capacity: 50_000)
            try system.addEmitter(embers, capacity: 5_000)
        }
        #expect(try image.matchesGolden(named: "fire-smoke-embers"))
    }

    @Test func rainDiesOnCollision() throws {
        var rain = ParticleEmitter()
        rain.position = [0, 4.5, 0]
        rain.radius = 2.5
        rain.velocity = [0, -6, 0]
        rain.velocitySpread = 0.2
        rain.lifetime = 2...2
        rain.birthRate = 20_000
        rain.diesOnCollision = true
        rain.orientation = .velocityAligned(stretch: 0.25)
        rain.sizeOverLife = .constant(0.008)
        rain.colorOverLife = .constant([0.6, 0.7, 0.9, 0.7])
        let colliders: [Collider] = [
            .plane(normal: [0, 1, 0], distance: 0),
            .box(center: [0, 1.4, 0.5], halfExtents: [1.4, 0.05, 1.2], rotation: simd_quatf(angle: 0.25, axis: [0, 0, 1])),
        ]
        #expect(try render(emitter: rain, frames: 120, worldColliders: colliders).matchesGolden(named: "rain-dies-on-collision"))
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
