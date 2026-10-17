import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ColliderShapeTests {
    /// Spawns still particles in a small cloud around `origin` with one collider and runs one step.
    func pushOut(origin: SIMD3<Float>, collider: Collider) throws -> [SIMD3<Float>] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.position = origin
        emitter.radius = 0.05
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystem(device: runner.device, capacity: 64, emitter: emitter, seed: 4)
        system.colliders = [collider]
        system.burst(64)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return UnsafeBufferPointer(start: pointer, count: system.capacity).map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
    }

    @Test func rotatedBoxPushesOutParticlesOutsideItsAxisAlignedBounds() throws {
        // A unit cube turned 45° about z reaches up to y = √2. Particles at y = 1.2 are inside it but would be outside
        // the unrotated cube.
        let rotation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
        let positions = try pushOut(origin: [0, 1.2, 0], collider: .box(center: .zero, halfExtents: [1, 1, 1], rotation: rotation))
        for position in positions {
            let local = rotation.inverse.act(position)
            let outside = (abs(local) - SIMD3<Float>(1, 1, 1)).max()
            #expect(outside >= -1e-4)
        }
    }

    @Test func unrotatedBoxLeavesParticlesOutsideAlone() throws {
        let positions = try pushOut(origin: [0, 1.2, 0], collider: .box(center: .zero, halfExtents: [1, 1, 1]))
        #expect(positions.allSatisfy { $0.y > 1.1 && $0.y < 1.3 })
    }

    @Test func capsulePushesParticlesToItsSurface() throws {
        let start: SIMD3<Float> = [-1, 0, 0]
        let end: SIMD3<Float> = [1, 0, 0]
        let positions = try pushOut(origin: [0.3, 0.2, 0], collider: .capsule(start: start, end: end, radius: 0.5))
        for position in positions {
            // Distance to the segment, which lies on the x axis here.
            let distance = simd_length(SIMD2(position.y, position.z))
            #expect(distance >= 0.5 - 1e-4)
        }
    }

    @Test func capsuleEndCapsAreRounded() throws {
        // Just past the end along the axis, within the radius: inside the cap.
        let positions = try pushOut(origin: [1.3, 0, 0], collider: .capsule(start: [-1, 0, 0], end: [1, 0, 0], radius: 0.5))
        for position in positions {
            #expect(simd_distance(position, [1, 0, 0]) >= 0.5 - 1e-4)
        }
    }

    @Test func wireframesHaveLinePairs() {
        let colliders: [Collider] = [
            .box(center: .zero, halfExtents: [1, 2, 3], rotation: simd_quatf(angle: 0.3, axis: [0, 1, 0])),
            .capsule(start: .zero, end: [0, 1, 0], radius: 0.25),
        ]
        for collider in colliders {
            let vertices = collider.wireframe
            #expect(!vertices.isEmpty)
            #expect(vertices.count.isMultiple(of: 2))
        }
    }
}
