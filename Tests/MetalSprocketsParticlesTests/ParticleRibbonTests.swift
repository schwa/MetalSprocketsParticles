import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct ParticleRibbonTests {
    /// Particles burst one per frame at each of `positions`, then rendered; returns the middle row of pixels.
    func row(ribbon: ParticleRibbon?, positions: [SIMD3<Float>], lifetimes: Float = 10) throws -> [SIMD4<UInt8>] {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = lifetimes...lifetimes
        emitter.birthRate = 0
        emitter.sizeOverLife = .constant(0.06)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.ribbon = ribbon
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 16, emitter: emitter)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        var image: CGImage?
        for position in positions {
            system.burst(1, at: position)
            image = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage
        }
        let pixels = try #require(image).rgbaPixels()
        return Array(pixels[32 * 128..<33 * 128])
    }

    @Test func ribbonsJoinParticlesInBirthOrder() throws {
        let ends: [SIMD3<Float>] = [[-1, 0, 0], [1, 0, 0]]
        let joined = try row(ribbon: ParticleRibbon(tapers: false), positions: ends)
        let apart = try row(ribbon: nil, positions: ends)
        // Halfway between the two particles: lit by the ribbon, dark with sprites.
        #expect(joined[64].x > 100)
        #expect(apart[64].x < 10)
    }

    @Test func taperingNarrowsTheOldEnd() throws {
        // Three in a row; with tapering, the oldest end has no width.
        let line: [SIMD3<Float>] = [[-1, 0, 0], [0, 0, 0], [1, 0, 0]]
        let tapered = try row(ribbon: ParticleRibbon(tapers: true), positions: line)
        let even = try row(ribbon: ParticleRibbon(tapers: false), positions: line)
        let tail = 48 // Between the oldest and the middle particle.
        #expect(tapered[tail].x < even[tail].x)
    }

    /// A moving ribbon emitter places each step's births in slot order along its path, so the ribbon does not zigzag.
    /// With random birth ages (other emitters), slot order and path order differ within a step.
    @Test func ribbonEmittersBirthInSlotOrderAlongTheirPath() throws {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 1_200
        emitter.ribbon = ParticleRibbon()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 200, emitter: emitter)
        for frame in 0..<4 {
            system.emitters[0].transform = simd_float4x4(translation: [Float(frame), 0, 0])
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 200)
        let xs = (0..<system.emitters[0].liveWindow.count).map { pointer[$0].position.x }
        #expect(xs.count > 40)
        // Later slots are nearer the emitter's latest position: x never decreases along the slots.
        #expect(zip(xs, xs.dropFirst()).allSatisfy { $0 <= $1 + 1e-5 })
    }

    @Test func ribbonsRoundTripThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.ribbon = ParticleRibbon(tapers: false)
        #expect(try roundTrip(emitter).ribbon == emitter.ribbon)
    }
}
