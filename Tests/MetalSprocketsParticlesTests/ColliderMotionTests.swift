import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Rotating colliders fling particles, and fast particles do not pass through thin colliders between steps.
@Suite(.serialized)
struct ColliderMotionTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    /// One still particle at `start` with `velocity`, no gravity; colliders per frame. Returns its final position and
    /// velocity.
    func run(start: SIMD3<Float>, velocity: SIMD3<Float> = .zero, frames: Int, colliders: (Int) -> [Collider]) throws -> (position: SIMD3<Float>, velocity: SIMD3<Float>) {
        var emitter = ParticleEmitter()
        emitter.position = start
        emitter.shape = .point
        emitter.velocity = velocity
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.restitution = 0
        emitter.friction = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystem(device: runner.device, capacity: 1, emitter: emitter)
        system.burst(1)
        for frame in 0..<frames {
            try runner.run(try system.simulate(deltaTime: deltaTime, colliders: colliders(frame)))
        }
        let particle = system.buffer.contents().bindMemory(to: Particle.self, capacity: 1)[0]
        return (SIMD3(particle.position.x, particle.position.y, particle.position.z), SIMD3(particle.velocity.x, particle.velocity.y, particle.velocity.z))
    }

    @Test func spinningPaddleFlingsParticles() throws {
        // A paddle along x spinning about y at 6 rad/s sweeps through a still particle 0.84 from the axis.
        let result = try run(start: [0.8, 0, -0.25], frames: 20) { frame in
            [.box(center: .zero, halfExtents: [1, 0.2, 0.2], rotation: simd_quatf(angle: Float(frame) * 0.1, axis: [0, 1, 0]))]
        }
        // Without rotation speed the particle is only pushed out and barely moves; with it, it leaves at about ω·r.
        #expect(simd_length(result.velocity) > 2, "speed \(simd_length(result.velocity))")
    }

    @Test func colliderSpinsTurnBoxesAndCapsulesAboutTheirPivot() {
        let colliders: [Collider] = [
            .plane(normal: [0, 1, 0], distance: 0),
            .box(center: [1, 2, 3], halfExtents: [1, 0.1, 0.1]),
            .capsule(start: [-1, 1, 0], end: [1, 1, 0], radius: 0.1),
        ]
        let spins = [
            ColliderSpin(collider: 1, axis: [0, 0, 1], speed: .pi / 2),
            ColliderSpin(collider: 2, axis: [0, 1, 0], speed: .pi / 2),
            ColliderSpin(collider: 9, axis: [0, 1, 0], speed: 1),
        ]
        let spun = colliders.spun(spins, at: 1)
        #expect(spun[0] == colliders[0])
        guard case let .box(center, _, rotation) = spun[1].shape, case let .capsule(start, end, _) = spun[2].shape else {
            Issue.record("Shapes changed kind")
            return
        }
        #expect(center == [1, 2, 3])
        #expect(simd_distance(rotation.act([1, 0, 0]), [0, 1, 0]) < 1e-5)
        // A quarter turn about y swings the capsule from along x to along z, around its midpoint.
        #expect(simd_distance(start, [0, 1, 1]) < 1e-5)
        #expect(simd_distance(end, [0, 1, -1]) < 1e-5)
    }

    @Test func paddleWheelPresetSpinsItsBlades() throws {
        let preset = ParticlePreset.paddleWheel
        #expect(preset.colliderSpins.count == 2)
        #expect(preset.colliders(at: 0.5) != preset.colliders(at: 0))
        let decoded = try JSONDecoder().decode(ParticlePreset.self, from: try JSONEncoder().encode(preset))
        #expect(decoded.colliderSpins == preset.colliderSpins)
    }

    @Test func fastParticlesDoNotTunnelThroughThinBoxes() throws {
        // 20 units/s covers 0.33 per step; the box is 0.04 thick.
        let result = try run(start: [0, 1, 0], velocity: [0, -20, 0], frames: 10) { _ in
            [.box(center: .zero, halfExtents: [1, 0.02, 1])]
        }
        #expect(result.position.y > 0, "ended at y = \(result.position.y)")
    }

    @Test func fastParticlesDoNotTunnelThroughSmallSpheres() throws {
        let result = try run(start: [0, 1, 0], velocity: [0, -20, 0], frames: 10) { _ in
            [.sphere(center: .zero, radius: 0.05)]
        }
        #expect(result.position.y > 0, "ended at y = \(result.position.y)")
    }

    @Test func fastParticlesDoNotTunnelThroughThinCapsules() throws {
        let result = try run(start: [0, 1, 0], velocity: [0, -20, 0], frames: 10) { _ in
            [.capsule(start: [-1, 0, 0], end: [1, 0, 0], radius: 0.03)]
        }
        #expect(result.position.y > 0, "ended at y = \(result.position.y)")
    }

    @Test func fastMovingThinBoxesDoNotPassThroughStillParticles() throws {
        // A thin box rising at 20 units/s overtakes a still particle; it should carry it, not pass it.
        let result = try run(start: [0, 0.5, 0], frames: 10) { frame in
            [.box(center: [0, Float(frame) * 20 * deltaTime, 0], halfExtents: [1, 0.02, 1])]
        }
        #expect(result.position.y > 1, "ended at y = \(result.position.y)")
    }

    @Test func planningDerivesAngularVelocity() {
        let before = Collider.box(center: .zero, halfExtents: [1, 1, 1])
        let after = Collider.box(center: .zero, halfExtents: [1, 1, 1], rotation: simd_quatf(angle: 0.1, axis: [0, 1, 0]))
        let motion = after.motion(from: before, deltaTime: 0.1)
        #expect(simd_length(motion.linear) < 1e-5)
        #expect(simd_distance(motion.angular, [0, 1, 0]) < 1e-3)
    }
}
