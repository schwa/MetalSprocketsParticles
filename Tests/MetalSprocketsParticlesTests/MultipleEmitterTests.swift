import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct MultipleEmitterTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func still(at position: SIMD3<Float>, birthRate: Float = 0) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.position = position }
        emitter.edit(ShapeModule.self) { $0.shape = .sphere(radius: 0.01) }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = birthRate }
        return emitter
    }

    func particles(_ system: ParticleSystemRuntime) -> [Particle] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    func isAlive(_ particle: Particle) -> Bool {
        particle.velocity.w > 0 && particle.position.w < particle.velocity.w
    }

    @Test func emittersOwnDisjointSlices() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [still(at: [-1, 0, 0]), still(at: [1, 0, 0])], capacity: 100, seed: 1)
        #expect(system.emitters.map(\.range) == [0..<100, 100..<200])
        system.emitters[0].burst(30)
        system.emitters[1].burst(70)
        try runner.run(try system.simulate(deltaTime: 0))
        let all = particles(system)
        let first = all[system.emitters[0].range].filter(isAlive)
        let second = all[system.emitters[1].range].filter(isAlive)
        #expect(first.count == 30)
        #expect(second.count == 70)
        #expect(first.allSatisfy { $0.position.x < 0 })
        #expect(second.allSatisfy { $0.position.x > 0 })
    }

    @Test func emittersRunTheirOwnBirthRates() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [still(at: .zero, birthRate: 120), still(at: .zero, birthRate: 600)], capacity: 1_000, seed: 1)
        for _ in 0..<60 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let all = particles(system)
        #expect(abs(all[system.emitters[0].range].filter(isAlive).count - 120) <= 1)
        #expect(abs(all[system.emitters[1].range].filter(isAlive).count - 600) <= 1)
    }

    @Test func identicalEmittersGetDifferentRandomStreams() throws {
        var settings = still(at: .zero)
        settings.edit(ShapeModule.self) { $0.shape = .sphere(radius: 1) }
        let system = try ParticleSystemRuntime(device: runner.device, modules: [settings, settings], capacity: 32, seed: 3)
        system.emitters.forEach { $0.burst(32) }
        try runner.run(try system.simulate(deltaTime: 0))
        let all = particles(system)
        #expect(all[0..<32].map(\.position) != all[32..<64].map(\.position))
    }

    @Test func firstEmitterMatchesASingleEmitterSystem() throws {
        var settings = EmitterModules.fountain
        settings.edit(RateModule.self) { $0.birthRate = 2_000 }
        let single = try ParticleSystemRuntime(device: runner.device, capacity: 500, modules: settings, seed: 7)
        let multiple = try ParticleSystemRuntime(device: runner.device, modules: [settings, still(at: .zero, birthRate: 100)], capacity: 500, seed: 7)
        for _ in 0..<30 {
            try runner.run(try single.simulate(deltaTime: 1.0 / 60.0))
            try runner.run(try multiple.simulate(deltaTime: 1.0 / 60.0))
        }
        #expect(particles(single) == Array(particles(multiple)[multiple.emitters[0].range]))
    }

    @Test func sharedCollidersAffectEveryEmitter() throws {
        var falling = still(at: [0, 1, 0])
        falling.edit(GravityModule.self) { $0.acceleration = [0, -9.8, 0] }
        falling.edit(CollisionModule.self) { $0.restitution = 0 }
        let system = try ParticleSystemRuntime(device: runner.device, modules: [falling, falling], capacity: 16, seed: 2)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        system.emitters.forEach { $0.burst(16) }
        for _ in 0..<90 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        #expect(particles(system).allSatisfy { $0.position.y >= -1e-3 })
    }

    @Test func localEmitterCollidesWithWorldColliders() throws {
        var falling = still(at: .zero)
        falling.edit(GravityModule.self) { $0.acceleration = [0, -9.8, 0] }
        falling.edit(CollisionModule.self) { $0.restitution = 0 }
        let system = try ParticleSystemRuntime(device: runner.device, modules: [falling], capacity: 16, seed: 2)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        let emitter = system.emitters[0]
        emitter.simulationSpace = .local
        var transform = matrix_identity_float4x4
        transform.columns.3 = [0, 2, 0, 1]
        emitter.transform = transform
        emitter.burst(16)
        for _ in 0..<120 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        // The world floor is 2 below the emitter's origin, so particles rest at local y ≈ -2.
        for particle in particles(system) {
            #expect(abs(particle.position.y + 2) < 0.02)
        }
    }

    @Test func simulateAppliesTransformsByIndex() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [still(at: .zero), still(at: .zero)], capacity: 4, seed: 1)
        var moved = matrix_identity_float4x4
        moved.columns.3 = [3, 0, 0, 1]
        system.emitters.forEach { $0.burst(4) }
        try runner.run(try system.simulate(deltaTime: 0, transforms: [moved]))
        #expect(system.emitters[0].transform == moved)
        #expect(system.emitters[1].transform == matrix_identity_float4x4)
        let all = particles(system)
        #expect(all[system.emitters[0].range].allSatisfy { abs($0.position.x - 3) < 0.02 })
        #expect(all[system.emitters[1].range].allSatisfy { abs($0.position.x) < 0.02 })
    }

    @Test func restartingOneEmitterLeavesTheOthers() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [still(at: .zero), still(at: .zero)], capacity: 10, seed: 1)
        system.emitters.forEach { $0.burst(10) }
        try runner.run(try system.simulate(deltaTime: 0))
        system.emitters[0].restart()
        try runner.run(try system.simulate(deltaTime: 0))
        let all = particles(system)
        #expect(!all[system.emitters[0].range].contains(where: isAlive))
        #expect(all[system.emitters[1].range].filter(isAlive).count == 10)
    }

    @Test func addEmitterKeepsRuntimeStateAndClearsParticles() throws {
        let system = try ParticleSystemRuntime(device: runner.device, modules: [still(at: .zero)], capacity: 10, seed: 1)
        let texture = try makeSpriteSheet(device: runner.device, rows: 1, columns: 1) { _, _, _ in }
        system.texture = texture
        system.burst(10)
        try runner.run(try system.simulate(deltaTime: 0))
        let added = try system.addEmitter(still(at: [1, 0, 0]), capacity: 5)
        #expect(system.emitters.count == 2)
        #expect(system.texture === texture)
        #expect(added.range == 10..<15)
        #expect(!particles(system).contains(where: isAlive))
    }

    /// Two emitters side by side with different colors and blend modes both draw.
    @Test func eachEmitterDrawsWithItsOwnSettings() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        var left = still(at: [-1, 0, 0])
        left.edit(ColorOverLifeModule.self) { $0.color = .constant([1, 0, 0, 1]) }
        left.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.3) }
        var right = still(at: [1, 0, 0])
        right.edit(ColorOverLifeModule.self) { $0.color = .constant([0, 0, 1, 1]) }
        right.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.3) }
        right.edit(SpriteModule.self) { $0.blendMode = .additive }
        let system = try ParticleSystemRuntime(device: renderer.device, modules: [left, right], capacity: 1, seed: 0)
        system.emitters.forEach { $0.burst(1) }
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        let image = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage
        let pixels = try image.rgbaPixels()
        let leftHalf = pixels.indices.filter { $0 % 128 < 64 }.map { pixels[$0] }
        let rightHalf = pixels.indices.filter { $0 % 128 >= 64 }.map { pixels[$0] }
        #expect(leftHalf.contains { $0.x > 200 && $0.z == 0 })
        #expect(rightHalf.contains { $0.z > 200 && $0.x == 0 })
        #expect(!leftHalf.contains { $0.z > 0 })
        #expect(!rightHalf.contains { $0.x > 0 })
    }
}
