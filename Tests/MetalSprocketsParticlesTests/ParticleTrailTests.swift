import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ParticleTrailTests {
    func mover(_ configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = [6, 0, 0]
        emitter.velocitySpread = 0
        emitter.speedVariation = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.trail = ParticleTrail(pointCount: 8)
        configure(&emitter)
        return emitter
    }

    func trail(_ system: ParticleSystemRuntime, particle: Int) throws -> [SIMD3<Float>] {
        let trails = try #require(system.trails)
        let points = trails.contents().bindMemory(to: SIMD4<Float>.self, capacity: trails.length / 16)
        return (0..<8).map { SIMD3(points[particle * system.trailStride + $0].x, points[particle * system.trailStride + $0].y, points[particle * system.trailStride + $0].z) }
    }

    @Test func trailsHoldRecentPositionsHeadFirst() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: mover())
        system.burst(1)
        for _ in 0..<5 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let points = try trail(system, particle: 0)
        let particle = system.buffer.contents().bindMemory(to: Particle.self, capacity: 4)[0]
        #expect(simd_distance(points[0], SIMD3(particle.position.x, particle.position.y, particle.position.z)) < 1e-5)
        // Each older point is one step (0.1 units at 6 units per second) further back.
        for index in 1..<5 {
            #expect(abs((points[index - 1].x - points[index].x) - 0.1) < 1e-3)
        }
        // Points older than the particle hold its first position, so the ribbon does not reach back to the origin.
        #expect(points[4...].allSatisfy { $0 == points[4] })
    }

    @Test func reusedSlotsDoNotStreakFromTheirLastParticle() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: mover { $0.lifetime = 0.05...0.05 })
        system.burst(1)
        for _ in 0..<10 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        // The old particle got far down +X; a new one in its slot starts back at the origin with a collapsed trail.
        system.burst(1)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let points = try trail(system, particle: 0)
        #expect(points.allSatisfy { $0.x < 0.2 })
    }

    @Test func systemsWithoutTrailsDoNotAllocate() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: mover { $0.trail = nil })
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        #expect(system.trails == nil)
    }

    /// One particle moving right draws a long horizontal ribbon, not a dot.
    @Test func ribbonsCoverThePath() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        let settings = mover {
            $0.position = [-1.5, 0, 0]
            $0.sizeOverLife = .constant(0.08)
            $0.colorOverLife = .constant([1, 1, 1, 1])
            $0.blendMode = .additive
            $0.trail = ParticleTrail(pointCount: 16, tapers: false, fades: false)
        }
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: settings)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        var image: CGImage?
        for _ in 0..<20 {
            image = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage
        }
        let pixels = try #require(image).rgbaPixels()
        let litColumns = (0..<128).filter { x in (24..<40).contains { y in pixels[y * 128 + x].x > 100 } }
        // 15 steps of 0.1 units is 1.5 units, about 29 of the view's 128 columns (6.6 units wide there); a lone sprite
        // would light about 3.
        #expect(litColumns.count > 22)
    }

    /// Head-to-tail length of an 8-point trail after 0.5 s at `stepsPerSecond`.
    func trailLength(stepsPerSecond: Int, interval: Float) throws -> Float {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: mover {
            $0.trail = ParticleTrail(pointCount: 8, pointInterval: interval)
        })
        system.burst(1)
        for _ in 0..<(stepsPerSecond / 2) {
            try runner.run(try system.simulate(deltaTime: 1 / Float(stepsPerSecond)))
        }
        let points = try trail(system, particle: 0)
        return points[0].x - points[7].x
    }

    @Test func timedTrailsCoverTheSameTimeAtAnyFrameRate() throws {
        // 8 points 0.05 s apart at 6 units per second: 7 full intervals (2.1 units) plus however much of the current one
        // the moving head has covered, so 2.1 to 2.4 units at 60 and at 120 steps per second.
        let at60 = try trailLength(stepsPerSecond: 60, interval: 0.05)
        let at120 = try trailLength(stepsPerSecond: 120, interval: 0.05)
        #expect((2.0...2.5).contains(at60))
        #expect((2.0...2.5).contains(at120))
        // Per step, the 120 fps trail covers half the time.
        let perStep60 = try trailLength(stepsPerSecond: 60, interval: 0)
        let perStep120 = try trailLength(stepsPerSecond: 120, interval: 0)
        #expect(abs(perStep120 * 2 - perStep60) < 0.05)
    }

    @Test func trailsRoundTripThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.trail = ParticleTrail(pointCount: 24, tapers: false, fades: true)
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).trail == emitter.trail)
    }
}
