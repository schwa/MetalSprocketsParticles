import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing
import UniformTypeIdentifiers

// GPU rasterization and float precision vary slightly across hardware; see MetalSprocketsAddOns.
private let psnrThreshold = 30.0

@Suite(.serialized, .requiresMetal4)
struct GoldenImageTests {
    func render(
        emitter: EmitterModules = .fountain,
        seed: UInt32 = 0,
        frames: Int,
        colliders: Bool = true,
        worldColliders: [Collider] = Collider.fountain(time: 0),
        forceFields: [ForceField] = [],
        configure: (ParticleSystemRuntime) throws -> Void = { _ in },
        perFrame: (ParticleSystemRuntime, Int) -> Void = { _, _ in }
    ) throws -> CGImage {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 50_000, modules: emitter, seed: seed)
        system.colliders = worldColliders
        system.forceFields = forceFields
        try configure(system)
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        var rendering: OffscreenRenderer.Rendering?
        for frame in 0..<frames {
            perFrame(system, frame)
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0, view: view)
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

    /// Sand on a teapot baked into a distance field collider (#151): the pile takes the lid, spout, and handle.
    @Test func sandOnABakedTeapot() throws {
        // The model's spout points along z; turned so it points along x, side on to the camera.
        let teapot = try #require(Collider.signedDistanceField(
            mesh: .teapot(diameter: 2.4), resolution: 64, center: [0, 0.6, 0], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        ))
        let sand = EmitterModules.standard { modules in
            modules.edit(ShapeModule.self) {
                $0.shape = .box(size: [2.8, 0.05, 1.6])
                $0.position = [0, 3.2, 0]
            }
            modules.edit(VelocityModule.self) {
                $0.velocity = .zero
                $0.spread = 0.1
            }
            // About the helper's 50 000 particles alive by the end, so the coating builds up without recycling.
            modules.edit(RateModule.self) { $0.birthRate = 9_000 }
            modules.edit(LifetimeModule.self) { $0.range = 6...6 }
            modules.edit(CollisionModule.self) {
                $0.restitution = 0.05
                $0.friction = 0.8
            }
            modules.edit(ColorOverLifeModule.self) { $0.color = .constant([0.95, 0.78, 0.48, 1]) }
            modules[VariationModule.self] = VariationModule(color: [0.08, 0.06, 0.04, 0])
            modules.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.022) }
            modules.edit(SpriteModule.self) { $0.blendMode = .opaque }
        }
        let image = try render(emitter: sand, frames: 330, colliders: false, worldColliders: [.plane(normal: [0, 1, 0], distance: 0), teapot])
        #expect(try image.matchesGolden(named: "sand-on-baked-teapot"))
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
        let emitter = EmitterModules.fountain { $0.edit(SpriteModule.self) { $0.blendMode = mode } }
        #expect(try render(emitter: emitter, frames: 120, colliders: false).matchesGolden(named: "fountain-blend-\(name)"))
    }

    // Blending lives in the pipeline descriptor; make sure the pipeline cache does not reuse the old one.
    @Test func blendModeChangeOnSameRendererTakesEffect() throws {
        let size = CGSize(width: 160, height: 90)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 5_000, modules: .fountain, seed: 0)
        system.colliders = Collider.fountain(time: 0)
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        for _ in 0..<60 {
            _ = try renderer.render(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        func draw() throws -> CGImage {
            try renderer.render(try RenderPass { try system.render(projection: projection, view: view) }).cgImage
        }
        let alpha = try draw()
        system.emitters[0].modules.edit(SpriteModule.self) { $0.blendMode = .additive }
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
        let emitter = EmitterModules.fountain { modules in
            modules.edit(RateModule.self) { $0.birthRate = 2_000 }
            modules.edit(SizeOverLifeModule.self) {
                $0.curve.start = 0.12
                $0.curve.end = 0.06
            }
            modules[RotationModule.self] = RotationModule(angleVariation: .pi, angularSpeed: 4, angularSpeedVariation: 2)
        }
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
        let emitter = EmitterModules.fountain { modules in
            modules.edit(RateModule.self) { $0.birthRate = 4_000 }
            modules.edit(SizeOverLifeModule.self) {
                $0.curve.start = 0.08
                $0.curve.end = 0.08
            }
            modules.edit(ColorOverLifeModule.self) {
                $0.color.start = [1, 1, 1, 1]
                $0.color.end = [1, 1, 1, 0.3]
            }
            modules[ImageSequenceModule.self] = ImageSequenceModule(sequence: ImageSequence(rows: 2, columns: 2, frameRate: 2))
        }
        let image = try render(emitter: emitter, frames: 120, colliders: false) { system in
            system.texture = try makeSpriteSheet(device: system.device, rows: 2, columns: 2) { context, index, rect in
                context.setFillColor(frameColors[index])
                context.fillEllipse(in: rect.insetBy(dx: 6, dy: 6))
            }
        }
        #expect(try image.matchesGolden(named: "sprite-sheet-animation"))
    }

    @Test func overLifeCurves() throws {
        let emitter = EmitterModules.fountain {
            $0.edit(ColorOverLifeModule.self) {
                $0.color = ParticleCurve([
                    .init(0, [1, 1, 0.8, 1]),
                    .init(0.15, [1, 0.6, 0.1, 1]),
                    .init(0.5, [0.8, 0.15, 0.05, 1]),
                    .init(1, [0.2, 0.2, 0.25, 1]),
                ])
                $0.opacity = .power(from: 1, to: 0, exponent: 3)
            }
            // Puff up, then shrink away.
            $0.edit(SizeOverLifeModule.self) { $0.curve = ParticleCurve([.init(0, 0.01), .init(0.3, 0.06), .init(1, 0.005)]) }
        }
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
        let emitter = EmitterModules.fountain {
            $0.edit(RateModule.self) { $0.birthRate = 3_000 }
            $0.edit(VelocityModule.self) {
                $0.velocity = [0, 6, 0]
                $0.spread = 3
            }
            $0.edit(SpriteModule.self) {
                $0.orientation = .velocityAligned(stretch: 0.8)
                $0.blendMode = .additive
            }
            $0.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.02) }
            $0.edit(ColorOverLifeModule.self) { $0.color = .linear(from: [1, 0.9, 0.5, 1], to: [1, 0.3, 0.05, 0]) }
        }
        #expect(try render(emitter: emitter, frames: 120).matchesGolden(named: "velocity-stretched-sparks"))
    }

    @Test func birthVariation() throws {
        let emitter = EmitterModules.fountain {
            $0.edit(RateModule.self) { $0.birthRate = 6_000 }
            $0[VariationModule.self] = VariationModule(size: 0.8, color: [0.15, 0.3, 0.2, 0])
            $0.edit(VelocityModule.self) { $0.speedVariation = 1.5 }
            $0.edit(CollisionModule.self) { $0.restitutionVariation = 0.3 }
        }
        #expect(try render(emitter: emitter, frames: 120, colliders: false).matchesGolden(named: "birth-variation"))
    }

    @Test func movingEmitterTrail() throws {
        let emitter = EmitterModules.fountain {
            $0.edit(VelocityModule.self) {
                $0.velocity = [0, 0.5, 0]
                $0.spread = 0.3
                $0.inherit = 0.3
            }
            $0.edit(GravityModule.self) { $0.acceleration = [0, -0.5, 0] }
            $0.edit(RateModule.self) { $0.birthRate = 8_000 }
        }
        // render takes two closures (configure, perFrame); a trailing closure would bind to configure.
        // swiftlint:disable:next trailing_closure
        let image = try render(emitter: emitter, frames: 120, worldColliders: [.plane(normal: [0, 1, 0], distance: 0)], perFrame: { system, frame in
            let angle = Float(frame) / 60 * 2.5
            var transform = matrix_identity_float4x4
            transform.columns.3 = [cos(angle) * 1.5, 1.5, sin(angle) * 1.5, 1]
            system.transform = transform
        })
        #expect(try image.matchesGolden(named: "moving-emitter-trail"))
    }

    @Test func fireSmokeAndEmbers() throws {
        // A sphere-shaped emitter rising (or falling) at `velocity`, with the parts these three share.
        // swiftlint:disable:next function_parameter_count
        func puff(at position: SIMD3<Float>, radius: Float, velocity: SIMD3<Float>, spread: Float, gravity: SIMD3<Float>, lifetime: ClosedRange<Float>, birthRate: Float) -> EmitterModules {
            EmitterModules.standard {
                $0.edit(ShapeModule.self) {
                    $0.position = position
                    $0.shape = .sphere(radius: radius)
                }
                $0.edit(VelocityModule.self) {
                    $0.velocity = velocity
                    $0.spread = spread
                }
                $0.edit(GravityModule.self) { $0.acceleration = gravity }
                $0.edit(LifetimeModule.self) { $0.range = lifetime }
                $0.edit(RateModule.self) { $0.birthRate = birthRate }
            }
        }
        var fire = puff(at: [0, 0.1, 0], radius: 0.25, velocity: [0, 1.2, 0], spread: 0.3, gravity: [0, 1, 0], lifetime: 0.5...1, birthRate: 6_000)
        fire.edit(SpriteModule.self) { $0.blendMode = .additive }
        fire.edit(SizeOverLifeModule.self) { $0.curve = ParticleCurve([.init(0, 0.06), .init(0.4, 0.1), .init(1, 0.02)]) }
        fire.edit(ColorOverLifeModule.self) {
            $0.color = ParticleCurve([
                .init(0, [1, 0.9, 0.5, 0.6]),
                .init(0.4, [1, 0.4, 0.05, 0.4]),
                .init(1, [0.4, 0.05, 0.02, 0]),
            ])
        }

        var smoke = puff(at: [0, 1, 0], radius: 0.2, velocity: [0, 0.8, 0], spread: 0.25, gravity: [0, 0.2, 0], lifetime: 2...3.5, birthRate: 400)
        smoke.edit(SizeOverLifeModule.self) { $0.curve = .linear(from: 0.1, to: 0.45) }
        smoke.edit(ColorOverLifeModule.self) { $0.color = .linear(from: [0.25, 0.25, 0.27, 0.25], to: [0.4, 0.4, 0.42, 0]) }
        smoke.edit(RateModule.self) { $0.warmupDuration = 2 }

        var embers = puff(at: [0, 0.3, 0], radius: 0.2, velocity: [0, 3, 0], spread: 1, gravity: [0, -1, 0], lifetime: 1...2.5, birthRate: 150)
        embers.edit(SpriteModule.self) {
            $0.blendMode = .additive
            $0.orientation = .velocityAligned(stretch: 0.6)
        }
        embers.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.012) }
        embers.edit(ColorOverLifeModule.self) { $0.color = .linear(from: [1, 0.6, 0.2, 1], to: [1, 0.2, 0.05, 0]) }

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
        let rain = EmitterModules.standard {
            $0.edit(ShapeModule.self) {
                $0.position = [0, 4.5, 0]
                $0.shape = .sphere(radius: 2.5)
            }
            $0.edit(VelocityModule.self) {
                $0.velocity = [0, -6, 0]
                $0.spread = 0.2
            }
            $0.edit(LifetimeModule.self) { $0.range = 2...2 }
            $0.edit(RateModule.self) { $0.birthRate = 20_000 }
            $0.edit(CollisionModule.self) { $0.diesOnCollision = true }
            $0.edit(SpriteModule.self) { $0.orientation = .velocityAligned(stretch: 0.25) }
            $0.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.008) }
            $0.edit(ColorOverLifeModule.self) { $0.color = .constant([0.6, 0.7, 0.9, 0.7]) }
        }
        let colliders: [Collider] = [
            .plane(normal: [0, 1, 0], distance: 0),
            .box(center: [0, 1.4, 0.5], halfExtents: [1.4, 0.05, 1.2], rotation: simd_quatf(angle: 0.25, axis: [0, 0, 1])),
        ]
        #expect(try render(emitter: rain, frames: 120, worldColliders: colliders).matchesGolden(named: "rain-dies-on-collision"))
    }

    @Test func emitterShapes() throws {
        func emitter(_ shape: EmitterShape, at x: Float, location: ParticleBirthLocation, color: SIMD4<Float>) -> EmitterModules {
            EmitterModules.standard {
                $0.edit(ShapeModule.self) {
                    $0.position = [x, 1.4, 0]
                    $0.shape = shape
                    $0.birthLocation = location
                    $0.birthDirection = .normal
                }
                $0.edit(VelocityModule.self) {
                    $0.velocity = [0, 0.15, 0]
                    $0.spread = 0
                }
                $0.edit(GravityModule.self) { $0.acceleration = .zero }
                $0.edit(LifetimeModule.self) { $0.range = 1...2 }
                $0.edit(RateModule.self) { $0.birthRate = 3_000 }
                $0.edit(SpriteModule.self) { $0.blendMode = .additive }
                $0.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.015) }
                $0.edit(ColorOverLifeModule.self) { $0.color = .linear(from: color, to: color * [1, 1, 1, 0]) }
            }
        }
        let shapes = [
            emitter(.torus(radius: 0.4, tubeRadius: 0.08), at: -2.1, location: .surface, color: [1, 0.5, 0.2, 0.8]),
            emitter(.cone(radius: 0.35, height: 0.8), at: -0.7, location: .surface, color: [0.3, 1, 0.4, 0.8]),
            emitter(.box(size: [0.6, 0.6, 0.6]), at: 0.7, location: .surface, color: [0.3, 0.6, 1, 0.8]),
            emitter(.sphere(radius: 0.4), at: 2.1, location: .surface, color: [1, 0.3, 0.8, 0.8]),
        ]
        let image = try render(emitter: shapes[0], frames: 90, colliders: false, worldColliders: []) { system in
            // Tilt the torus toward the camera so its hole shows. Its shape is centered on its own origin.
            system.emitters[0].modules.edit(ShapeModule.self) { $0.position = .zero }
            var transform = simd_float4x4(simd_quatf(angle: 1.1, axis: [1, 0, 0]))
            transform.columns.3 = [-2.1, 1.4, 0, 1]
            system.transform = transform
            for shape in shapes.dropFirst() {
                try system.addEmitter(shape, capacity: 50_000)
            }
        }
        #expect(try image.matchesGolden(named: "emitter-shapes"))
    }

    /// A large foil coin shaded per pixel (#174, #175): the reflection changes smoothly across its face instead of the
    /// whole face taking one color.
    @Test func largeFoilMeshPerPixel() throws {
        let coin = EmitterModules.standard { modules in
            modules.edit(ShapeModule.self) {
                $0.shape = .point
                $0.position = [0, 1.5, 0]
            }
            modules.edit(VelocityModule.self) {
                $0.velocity = .zero
                $0.spread = 0
            }
            modules.edit(GravityModule.self) { $0.acceleration = .zero }
            modules.edit(RateModule.self) { $0.birthRate = 0 }
            modules.edit(LifetimeModule.self) { $0.range = 10...10 }
            modules[RotationModule.self] = RotationModule(angle: 0.9)
            modules[MeshModule.self] = MeshModule(mesh: .coin)
            modules.edit(SizeOverLifeModule.self) { $0.curve = .constant(1.2) }
            modules.edit(ColorOverLifeModule.self) { $0.color = .constant([0.85, 0.65, 0.25, 1]) }
            modules.edit(SpriteModule.self) { $0.blendMode = .opaque }
            modules.edit(ShadingModule.self) {
                $0.model = .foil(settings: ParticleFoil(glint: 3, shininess: 48, iridescence: 0.3))
                $0.perPixel = true
            }
        }
        let image = try render(emitter: coin, frames: 2, colliders: false, worldColliders: []) { system in
            system.lights = [.directional(direction: simd_normalize([-0.3, -1, -0.6]))]
            system.burst(1)
        }
        #expect(try image.matchesGolden(named: "foil-mesh-per-pixel"))
    }

    /// A custom shading function (#173): the rim-light template on lit-looking spheres of particles.
    @Test func customRimLightShading() throws {
        let emitter = EmitterModules.standard {
            $0.edit(ShapeModule.self) {
                $0.position = [0, 1.5, 0]
                $0.shape = .sphere(radius: 0.8)
            }
            $0.edit(VelocityModule.self) {
                $0.velocity = .zero
                $0.spread = 0
            }
            $0.edit(GravityModule.self) { $0.acceleration = .zero }
            $0.edit(LifetimeModule.self) { $0.range = 10...10 }
            $0.edit(RateModule.self) { $0.birthRate = 0 }
            $0.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.35) }
            $0.edit(ColorOverLifeModule.self) { $0.color = .constant([0.2, 0.4, 0.9, 1]) }
            $0.edit(SpriteModule.self) {
                $0.blendMode = .opaque
                $0.orientation = .tumbling
            }
            $0.edit(ShadingModule.self) { $0.model = .custom(function: ShadingModule.template) }
        }
        let image = try render(emitter: emitter, frames: 2, colliders: false, worldColliders: []) { system in
            system.lights = [.directional(direction: simd_normalize([-0.3, -1, -0.6]))]
            system.burst(24)
        }
        #expect(try image.matchesGolden(named: "custom-rim-light-shading"))
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
