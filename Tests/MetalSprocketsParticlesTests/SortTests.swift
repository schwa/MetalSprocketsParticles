import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct SortTests {
    let view = simd_float4x4(lookingFrom: [0, 1, 6], at: [0, 1, 0]).inverse
    let cameraPosition: SIMD3<Float> = [0, 1, 6]
    let cameraForward = simd_normalize(SIMD3<Float>(0, 0, -6))

    func makeSystem(capacity: Int, sortMode: ParticleSortMode = .backToFront, device: MTLDevice) throws -> ParticleSystem {
        var emitter = ParticleEmitter()
        emitter.position = [0, 1, 0]
        emitter.shape = .sphere(radius: 2)
        emitter.velocity = .zero
        emitter.velocitySpread = 1
        emitter.gravity = .zero
        emitter.lifetime = 1...3
        emitter.birthRate = Float(capacity) / 2
        emitter.sortMode = sortMode
        return try ParticleSystem(device: device, capacity: capacity, emitter: emitter, seed: 6)
    }

    @Test(arguments: [100, 5_000, 70_000])
    func recordsAreBackToFrontAndCoverTheWindow(capacity: Int) throws {
        let runner = try Runner()
        let system = try makeSystem(capacity: capacity, device: runner.device)
        for _ in 0..<90 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0, view: view))
        }
        let emitter = system.emitters[0]
        let window = emitter.liveWindow
        #expect(emitter.sortedCount == window.count)
        let buffers = try #require(emitter.sortBuffers)
        let records = buffers.recordsA.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: window.count)
        let particles = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)

        // Every slot of the window appears exactly once.
        let expected = Set((0..<window.count).map { (window.start + $0) % emitter.capacity })
        let actual = (0..<window.count).map { Int(records[$0].y) }
        #expect(Set(actual) == expected)
        #expect(actual.count == expected.count)

        // Live particles come first, farthest first; dead particles after them.
        func depth(_ index: Int) -> Float? {
            let particle = particles[index]
            guard particle.velocity.w > 0, particle.position.w < particle.velocity.w else {
                return nil
            }
            return simd_dot(SIMD3(particle.position.x, particle.position.y, particle.position.z) - cameraPosition, cameraForward)
        }
        let depths = actual.map(depth)
        let firstDead = depths.firstIndex { $0 == nil } ?? depths.count
        #expect(depths[firstDead...].allSatisfy { $0 == nil })
        let live = depths[..<firstDead].compactMap(\.self)
        #expect(live.count > 0)
        // Keys are 16-bit halves, so neighbors may tie or swap within half precision.
        for (farther, nearer) in zip(live, live.dropFirst()) {
            #expect(farther >= nearer - max(abs(farther), abs(nearer)) * 0.002)
        }
    }

    @Test func withoutAViewNothingIsSorted() throws {
        let runner = try Runner()
        let system = try makeSystem(capacity: 1_000, device: runner.device)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        #expect(system.emitters[0].sortedCount == 0)
    }

    @Test func unsortedEmittersAllocateNothing() throws {
        let runner = try Runner()
        let system = try makeSystem(capacity: 1_000, sortMode: .none, device: runner.device)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0, view: view))
        #expect(system.emitters[0].sortBuffers == nil)
    }

    /// Two overlapping, nearly opaque discs: red near the camera, blue behind it. Red is declared first, so unsorted it
    /// draws first and blue covers it.
    func centerPixel(sortMode: ParticleSortMode) throws -> SIMD4<UInt8> {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        func disc(z: Float, color: SIMD4<Float>) -> ParticleEmitter {
            var emitter = ParticleEmitter()
            emitter.position = [0, 1, z]
            emitter.shape = .point
            emitter.velocity = .zero
            emitter.velocitySpread = 0
            emitter.gravity = .zero
            emitter.lifetime = 10...10
            emitter.birthRate = 0
            emitter.sizeOverLife = .constant(0.8)
            emitter.colorOverLife = .constant(color)
            emitter.sortMode = sortMode
            return emitter
        }
        let system = try ParticleSystem(device: renderer.device, emitters: [disc(z: 1, color: [1, 0, 0, 1]), disc(z: -1, color: [0, 0, 1, 1])], capacity: 1)
        system.emitters.forEach { $0.burst(1) }
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 20)
        return try renderer.render(Group {
            try system.simulate(deltaTime: 0, view: view)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.centerPixel()
    }

    @Test func sortedEmittersDrawFarthestFirst() throws {
        let unsorted = try centerPixel(sortMode: .none)
        let sorted = try centerPixel(sortMode: .backToFront)
        #expect(unsorted.z > unsorted.x)
        #expect(sorted.x > sorted.z)
    }
}
