import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct EmitterTransformTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func makeSystem(count: Int = 64, configure: (inout ParticleEmitter) -> Void = { _ in }) throws -> ParticleSystemRuntime {
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = [0, 4, 0]
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        configure(&emitter)
        return try ParticleSystemRuntime(device: runner.device, capacity: count, emitter: emitter, seed: 8)
    }

    func particles(_ system: ParticleSystemRuntime) -> [Particle] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    func translation(_ offset: SIMD3<Float>) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(offset, 1)
        return matrix
    }

    @Test func worldSpaceSpawnsThroughTransform() throws {
        let system = try makeSystem()
        system.transform = translation([5, 0, 0]) * simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: 0))
        for particle in particles(system) {
            #expect(simd_distance(SIMD3(particle.position.x, particle.position.y, particle.position.z), [5, 0, 0]) < 1e-4)
            // Local +y velocity rotated 90° about z becomes -x.
            #expect(abs(particle.velocity.x + 4) < 1e-4 && abs(particle.velocity.y) < 1e-4)
        }
    }

    @Test func localSpaceKeepsParticlesInEmitterSpace() throws {
        let system = try makeSystem()
        system.simulationSpace = .local
        system.transform = translation([5, 0, 0])
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: 0))
        for particle in particles(system) {
            #expect(simd_length(SIMD3(particle.position.x, particle.position.y, particle.position.z)) < 1e-4)
        }
    }

    @Test func inheritVelocityAddsEmitterMotion() throws {
        let system = try makeSystem { $0.inheritVelocity = 1 }
        let deltaTime: Float = 1.0 / 60.0
        try runner.run(try system.simulate(deltaTime: deltaTime))
        // Emitter moves 0.1 per frame: 6 m/s along +x.
        system.transform = translation([0.1, 0, 0])
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: deltaTime))
        for particle in particles(system) {
            #expect(abs(particle.velocity.x - 6) < 1e-3)
        }
    }

    @Test func fastEmitterSpreadsBirthsAlongItsPath() throws {
        let system = try makeSystem(count: 256) { $0.velocity = .zero }
        try runner.run(try system.simulate(deltaTime: 0))
        system.transform = translation([1, 0, 0])
        system.burst(256)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let xs = particles(system).map(\.position.x)
        // Births fill the segment from the old origin (0) to the new one (1), not just the end.
        #expect(xs.allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 })
        #expect(xs.min()! < 0.1 && xs.max()! > 0.9)
    }

    /// Horizontal screen position of the lit pixels' center.
    func renderedCenterX(space: SimulationSpace, moveAfterSpawn: SIMD3<Float>) throws -> Float {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 128))
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.sizeOverLife = .constant(0.1)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter, seed: 0)
        system.simulationSpace = space
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        _ = try renderer.render(try system.simulate(deltaTime: 0))
        system.transform = translation(moveAfterSpawn)
        let pixels = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.rgbaPixels()
        let lit = pixels.indices.filter { pixels[$0].x > 40 }.map { Float($0 % 128) }
        return lit.reduce(0, +) / Float(max(lit.count, 1))
    }

    @Test func localParticlesFollowTheEmitterAndWorldParticlesStay() throws {
        let local = try renderedCenterX(space: .local, moveAfterSpawn: [0.5, 0, 0])
        let world = try renderedCenterX(space: .world, moveAfterSpawn: [0.5, 0, 0])
        #expect(abs(world - 64) < 2)
        #expect(local > 70)
    }
}
