import CoreGraphics
import Foundation
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// `ParticleEmitter.foil`: mesh particles glint when they turn to catch the light and shift color with angle (#155).
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
        var coin = ParticleEmitter()
        coin.shape = .point
        coin.position = [0, 0, 0]
        coin.velocity = .zero
        coin.velocitySpread = 0
        coin.gravity = .zero
        coin.birthRate = 0
        coin.lifetime = 10...10
        coin.angle = angle
        switch piece {
        case .coin:
            coin.particleMesh = .coin
        case .tumblingCard:
            coin.orientation = .tumbling
        case .billboard:
            coin.orientation = .billboard
        }
        coin.sizeOverLife = .constant(0.8)
        // Dark, so the glint stands out instead of clipping at white with the base color.
        coin.colorOverLife = .constant([0.3, 0.25, 0.12, 1])
        coin.blendMode = .opaque
        coin.foil = foil
        // Light from behind the camera: the glint peaks when the coin faces the camera.
        // A plain square card (the procedural dot fades toward its edges and would hide the glint's extent).
        let sprite: ParticleSprite = piece == .coin ? .softDot : .confetti
        let system = ParticleSystem(
            "Coin", layers: [EmitterDescription("Coin", settings: coin, sprite: sprite, capacity: 1)], lights: [.directional(direction: [0, 0, -1])], cameraEye: [0, 0, 3], cameraTarget: .zero
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

    /// Sparkles: an `.onGlint` sub-emitter fires as a spinning foil card flashes (#171), and only then.
    @Test func glintSubEmittersFireWhenPiecesFlash() throws {
        func children(spin: Float, withView: Bool) throws -> Int {
            var card = ParticleEmitter()
            card.shape = .point
            card.velocity = .zero
            card.velocitySpread = 0
            card.gravity = .zero
            card.birthRate = 0
            card.lifetime = 10...10
            card.orientation = .tumbling
            card.angularSpeed = spin
            card.foil = ParticleFoil()
            var sparkle = ParticleEmitter()
            sparkle.shape = .point
            sparkle.lifetime = 5...5
            sparkle.gravity = .zero
            card.subEmitters = [SubEmitter(occasion: .onGlint(threshold: 0.5), countPerEvent: 2, settings: sparkle)]
            let runner = try Runner()
            let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: card)
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
        let sub = SubEmitter(occasion: .onGlint(threshold: 0.6), countPerEvent: 3, settings: ParticleEmitter())
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
        var emitter = ParticleEmitter()
        emitter.orientation = .tumbling
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).orientation == .tumbling)
    }

    @Test func foilRoundTripsThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.foil = ParticleFoil(glint: 2, shininess: 30, iridescence: 0.4)
        let decoded = try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter))
        #expect(decoded.foil == emitter.foil)
    }
}
