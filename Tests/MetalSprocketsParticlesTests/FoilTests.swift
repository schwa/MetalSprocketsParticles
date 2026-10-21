import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// Foil shading (`ShadingModel.foil`): mesh particles glint when they turn to catch the light and shift color with angle (#155).
@Suite(.serialized, .requiresMetal4)
struct FoilTests {
    /// What the piece is: a mesh particle, or a sprite card oriented some way.
    enum Piece {
        case coin
        case tumblingCard
        case billboard
    }

    /// The color at the middle of the view for one large piece turned to `angle`.
    func centerColor(angle: Float, foil: ParticleFoil?, piece: Piece = .coin) throws -> SIMD3<Float> {
        var coin = EmitterModules.standard
        coin.edit(ShapeModule.self) { $0.shape = .point }
        coin.edit(ShapeModule.self) { $0.position = [0, 0, 0] }
        coin.edit(VelocityModule.self) { $0.velocity = .zero }
        coin.edit(VelocityModule.self) { $0.spread = 0 }
        coin.edit(GravityModule.self) { $0.acceleration = .zero }
        coin.edit(RateModule.self) { $0.birthRate = 0 }
        coin.edit(LifetimeModule.self) { $0.range = 10...10 }
        coin.edit(RotationModule.self, adding: RotationModule()) { $0.angle = angle }
        switch piece {
        case .coin:
            coin[MeshModule.self] = MeshModule(mesh: .coin)
        case .tumblingCard:
            coin.edit(SpriteModule.self) { $0.orientation = .tumbling }
        case .billboard:
            coin.edit(SpriteModule.self) { $0.orientation = .billboard }
        }
        coin.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.8) }
        // Dark, so the glint stands out instead of clipping at white with the base color.
        coin.edit(ColorOverLifeModule.self) { $0.color = .constant([0.3, 0.25, 0.12, 1]) }
        coin.edit(SpriteModule.self) { $0.blendMode = .opaque }
        coin.edit(ShadingModule.self) { $0.model = foil.map { .foil(settings: $0) } ?? .unlit }
        // Light from behind the camera: the glint peaks when the coin faces the camera.
        // A plain square card (the procedural dot fades toward its edges and would hide the glint's extent).
        let sprite: ParticleSprite = piece == .coin ? .softDot : .confetti
        let system = ParticleSystem(
            "Coin", layers: [EmitterDescription("Coin", modules: coin, sprite: sprite, capacity: 1)], lights: [.directional(direction: [0, 0, -1])], cameraEye: [0, 0, 3], cameraTarget: .zero
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

    /// A mesh particle and a tumbling sprite card both glint as they turn (#155, #171).
    @Test(arguments: [Piece.coin, .tumblingCard])
    func foilGlintsAtSomeAnglesAndShiftsColor(piece: Piece) throws {
        let angles = (0..<36).map { Float($0) / 36 * 2 * .pi }
        let foil = try angles.map { try centerColor(angle: $0, foil: ParticleFoil(glint: 3, shininess: 48, iridescence: 0.6), piece: piece) }
        let plain = try angles.map { try centerColor(angle: $0, foil: nil, piece: piece) }
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

    /// Reflective foil on a tumbling card (#175): dark when it reflects nothing and bright when it does; crinkle breaks
    /// the card into brighter and darker patches; and the reflection keeps the metal's hue instead of turning white.
    @Test func foilCardsReflectInTheirOwnColor() throws {
        func render(angle: Float) throws -> [SIMD3<Float>] {
            var card = EmitterModules.standard
            card.edit(ShapeModule.self) { $0.shape = .point }
            card.edit(VelocityModule.self) { $0.velocity = .zero }
            card.edit(VelocityModule.self) { $0.spread = 0 }
            card.edit(GravityModule.self) { $0.acceleration = .zero }
            card.edit(RateModule.self) { $0.birthRate = 0 }
            card.edit(LifetimeModule.self) { $0.range = 10...10 }
            card.edit(RotationModule.self, adding: RotationModule()) { $0.angle = angle }
            card.edit(SpriteModule.self) { $0.orientation = .tumbling }
            card.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.9) }
            card.edit(ColorOverLifeModule.self) { $0.color = .constant([0.3, 0.25, 0.12, 1]) }
            card.edit(SpriteModule.self) { $0.blendMode = .opaque }
            card.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil(glint: 3, shininess: 48, iridescence: 0)) }
            let system = ParticleSystem(
                "Card", layers: [EmitterDescription("Card", modules: card, sprite: .confetti, capacity: 1)],
                lights: [.directional(direction: [0, 0, -1])], cameraEye: [0, 0, 3], cameraTarget: .zero
            )
            let size = CGSize(width: 96, height: 96)
            let renderer = try OffscreenRenderer(size: size)
            let player = try ParticlePlayer(system: system, device: renderer.device)
            player.runtime.burst(1)
            var rendering: OffscreenRenderer.Rendering?
            for _ in 0..<3 {
                rendering = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
            }
            let image = try #require(rendering).cgImage
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
            return (0..<(image.width * image.height)).map { SIMD3(Float(pixels[$0 * 4]), Float(pixels[$0 * 4 + 1]), Float(pixels[$0 * 4 + 2])) / 255 }
        }
        let renders = try (0..<36).map { try render(angle: Float($0) / 36 * 2 * .pi) }
        // The card covers the middle of the view at every angle it faces the camera; measure there.
        func middle(_ pixels: [SIMD3<Float>]) -> [SIMD3<Float>] {
            (36..<60).flatMap { y in (36..<60).map { x in pixels[y * 96 + x] } }
        }
        let totals = renders.map { middle($0).map(brightness).reduce(0, +) }
        let brightest = try #require(renders.indices.max { totals[$0] < totals[$1] })
        let darkest = try #require(renders.indices.min { totals[$0] < totals[$1] })
        #expect(totals[brightest] > totals[darkest] * 3, "brightest \(totals[brightest]), darkest \(totals[darkest])")
        // Crinkle: brightness varies across the card at its brightest.
        let values = middle(renders[brightest]).map(brightness).sorted()
        let spread = values[values.count * 9 / 10] - values[values.count / 10]
        #expect(spread > 0.08, "spread \(spread)")
        // Hue: the brightest pixels keep the gold base's balance (blue well below red), not white.
        let top = middle(renders[brightest]).sorted { brightness($0) > brightness($1) }.prefix(50)
        let mean = top.reduce(SIMD3<Float>.zero, +) / Float(top.count)
        #expect(mean.z < mean.x * 0.75, "brightest pixels \(mean)")
    }

    /// Sparkles: an `.onGlint` sub-emitter fires as a spinning foil card flashes (#171), and only then.
    @Test func glintSubEmittersFireWhenPiecesFlash() throws {
        func children(spin: Float, withView: Bool) throws -> Int {
            var card = EmitterModules.standard
            card.edit(ShapeModule.self) { $0.shape = .point }
            card.edit(VelocityModule.self) { $0.velocity = .zero }
            card.edit(VelocityModule.self) { $0.spread = 0 }
            card.edit(GravityModule.self) { $0.acceleration = .zero }
            card.edit(RateModule.self) { $0.birthRate = 0 }
            card.edit(LifetimeModule.self) { $0.range = 10...10 }
            card.edit(SpriteModule.self) { $0.orientation = .tumbling }
            card.edit(RotationModule.self, adding: RotationModule()) { $0.angularSpeed = spin }
            card.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil()) }
            var sparkle = EmitterModules.standard
            sparkle.edit(ShapeModule.self) { $0.shape = .point }
            sparkle.edit(LifetimeModule.self) { $0.range = 5...5 }
            sparkle.edit(GravityModule.self) { $0.acceleration = .zero }
            card[SubEmittersModule.self] = SubEmittersModule(emitters: [SubEmitter(occasion: .onGlint(threshold: 0.5), countPerEvent: 2, modules: sparkle)])
            let runner = try Runner()
            let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 1, modules: card)
            runtime.burst(1)
            let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
            for _ in 0..<120 {
                try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0, view: withView ? view : nil))
            }
            // Children live in the sub-emitter's slice, after the parent.
            let count = runtime.buffer.length / MemoryLayout<Particle>.stride
            let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: count)
            return (1..<count).filter { pointer[$0].velocity.w > 0 && pointer[$0].position.w < pointer[$0].velocity.w }.count
        }
        #expect(try children(spin: 6, withView: true) > 0)
        #expect(try children(spin: 6, withView: false) == 0)
        #expect(try children(spin: 0, withView: true) == 0)
    }

    @Test func onGlintRoundTripsThroughEffectFiles() throws {
        let sub = SubEmitter(occasion: .onGlint(threshold: 0.6), countPerEvent: 3, modules: .standard)
        #expect(try JSONDecoder().decode(SubEmitter.self, from: JSONEncoder().encode(sub)).occasion == .onGlint(threshold: 0.6))
    }

    /// A billboard always faces the camera, so turning it (in its plane) does not make it glint: why foil needs tumbling.
    @Test func foilBillboardsDoNotGlint() throws {
        let angles = (0..<12).map { Float($0) / 12 * 2 * .pi }
        let colors = try angles.map { try centerColor(angle: $0, foil: ParticleFoil(glint: 3, shininess: 48, iridescence: 0.6), piece: .billboard) }
        let brightness = colors.map(brightness)
        #expect((brightness.max() ?? 0) - (brightness.min() ?? 0) < 0.05, "\(brightness)")
    }

    @Test func tumblingRoundTripsThroughEffectFiles() throws {
        var emitter = EmitterModules.standard
        emitter.edit(SpriteModule.self) { $0.orientation = .tumbling }
        #expect(try roundTrip(emitter)[SpriteModule.self]?.orientation == .tumbling)
    }

    @Test func foilRoundTripsThroughEffectFiles() throws {
        var emitter = EmitterModules.standard
        emitter.edit(ShadingModule.self) { $0.model = .foil(settings: ParticleFoil(glint: 2, shininess: 30, iridescence: 0.4)) }
        let decoded = try roundTrip(emitter)
        #expect(decoded[ShadingModule.self] == emitter[ShadingModule.self])
    }
}
