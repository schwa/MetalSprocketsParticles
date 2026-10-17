import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct VariationTests {
    /// Spawns `count` particles in one burst and runs one zero-length step so birth values are untouched.
    func spawn(count: Int = 512, configure: (inout ParticleEmitter) -> Void) throws -> [Particle] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.velocity = [0, 4, 0]
        emitter.velocitySpread = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.colliders = []
        configure(&emitter)
        let system = try ParticleSystem(device: runner.device, capacity: count, emitter: emitter, seed: 21)
        system.burst(count)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    @Test func defaultsDoNotVary() throws {
        let particles = try spawn { _ in }
        #expect(particles.allSatisfy { $0.properties == [1, 0, 0, 0] && $0.color == .zero })
        #expect(particles.allSatisfy { abs(simd_length(SIMD3($0.velocity.x, $0.velocity.y, $0.velocity.z)) - 4) < 1e-4 })
    }

    @Test func sizeVariationScalesWithinRange() throws {
        let scales = try spawn { $0.sizeVariation = 0.25 }.map(\.properties.x)
        #expect(scales.allSatisfy { $0 >= 0.75 && $0 <= 1.25 })
        #expect(scales.min()! < 0.8 && scales.max()! > 1.2)
    }

    @Test func restitutionAndFrictionOffsetsWithinRange() throws {
        let particles = try spawn {
            $0.restitutionVariation = 0.2
            $0.frictionVariation = 0.1
        }
        #expect(particles.allSatisfy { abs($0.properties.y) <= 0.2 && abs($0.properties.z) <= 0.1 })
        #expect(Set(particles.map(\.properties.y)).count > 100)
    }

    @Test func speedVariationKeepsDirection() throws {
        let particles = try spawn { $0.speedVariation = 1 }
        let speeds = particles.map { simd_length(SIMD3($0.velocity.x, $0.velocity.y, $0.velocity.z)) }
        #expect(speeds.allSatisfy { $0 >= 3 - 1e-4 && $0 <= 5 + 1e-4 })
        #expect(speeds.min()! < 3.2 && speeds.max()! > 4.8)
        #expect(particles.allSatisfy { $0.velocity.x == 0 && $0.velocity.z == 0 })
    }

    @Test func colorOffsetsWithinRange() throws {
        let variation: SIMD4<Float> = [0.1, 0.2, 0.3, 0.4]
        let offsets = try spawn { $0.colorVariation = variation }.map(\.color)
        #expect(offsets.allSatisfy { all(abs($0) .<= variation) })
        #expect(Set(offsets.map(\.x)).count > 100)
    }

    /// Red particles with hue variation must render with some green or blue; without it, none.
    @Test func hueVariationChangesRenderedColor() throws {
        func render(hueVariation: Float) throws -> [SIMD4<UInt8>] {
            let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
            var emitter = ParticleEmitter()
            emitter.radius = 0.6
            emitter.velocity = .zero
            emitter.velocitySpread = 0
            emitter.gravity = .zero
            emitter.lifetime = 10...10
            emitter.birthRate = 0
            emitter.colliders = []
            emitter.colorOverLife = .constant([1, 0, 0, 1])
            emitter.sizeOverLife = .constant(0.08)
            emitter.colorVariation = [hueVariation, 0, 0, 0]
            let system = try ParticleSystem(device: renderer.device, capacity: 200, emitter: emitter, seed: 2)
            system.burst(200)
            let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
            let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
            return try renderer.render(Group {
                try system.simulate(deltaTime: 0)
                try RenderPass { try system.render(projection: projection, view: view) }
            }).cgImage.rgbaPixels()
        }
        let plain = try render(hueVariation: 0)
        let varied = try render(hueVariation: 0.5)
        #expect(plain.allSatisfy { $0.y == 0 && $0.z == 0 })
        #expect(varied.contains { $0.y > 100 || $0.z > 100 })
    }
}

struct BirthRateVariationTests {
    @Test func rateChangesPerCycleWithinRange() {
        var emitter = ParticleEmitter()
        emitter.birthRate = 600
        emitter.birthRateVariation = 300
        emitter.emissionDuration = 1
        var spawner = Spawner(seed: 5)
        var perCycle: [Int] = []
        for _ in 0..<5 {
            var total = 0
            for _ in 0..<60 {
                total += Int(spawner.advance(deltaTime: 1.0 / 60.0, emitter: emitter, capacity: 1_000_000, isEmitting: true).count)
            }
            perCycle.append(total)
        }
        #expect(perCycle.allSatisfy { $0 >= 299 && $0 <= 901 })
        #expect(Set(perCycle).count > 1)
    }

    @Test func rateIsDeterministicForSeed() {
        var emitter = ParticleEmitter()
        emitter.birthRateVariation = 500
        #expect(Spawner(seed: 1).birthRate(emitter: emitter) == Spawner(seed: 1).birthRate(emitter: emitter))
        #expect(Spawner(seed: 1).birthRate(emitter: emitter) != Spawner(seed: 2).birthRate(emitter: emitter))
    }
}
