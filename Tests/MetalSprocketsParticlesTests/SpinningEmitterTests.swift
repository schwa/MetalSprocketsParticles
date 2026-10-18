import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Emitters that rotate quickly should spread a step's births along the arc they swept, and pass their spin on.
@Suite(.serialized)
struct SpinningEmitterTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0
    /// Radians per frame.
    let spinPerFrame: Float = 0.6

    init() throws {
        runner = try Runner()
    }

    /// A point emitter 1 unit out along x, spun around y by `spinPerFrame` each frame. Returns positions and velocities
    /// of the particles alive after `frames` frames.
    func spin(frames: Int, inheritVelocity: Float = 0) throws -> [(position: SIMD3<Float>, velocity: SIMD3<Float>)] {
        var emitter = ParticleEmitter()
        emitter.position = [1, 0, 0]
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 10...10
        emitter.birthRate = 1_200
        emitter.inheritVelocity = inheritVelocity
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1_000, emitter: emitter)
        for frame in 0..<frames {
            let rotation = simd_float4x4(simd_quatf(angle: Float(frame) * spinPerFrame, axis: [0, 1, 0]))
            try runner.run(try system.simulate(deltaTime: deltaTime, transforms: [rotation]))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity)
            .filter { pointer[$0].velocity.w > 0 }
            .map { (SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z), SIMD3(pointer[$0].velocity.x, pointer[$0].velocity.y, pointer[$0].velocity.z)) }
    }

    func angle(_ position: SIMD3<Float>) -> Float {
        atan2(position.z, position.x)
    }

    @Test func birthsSpreadAlongTheSweptArc() throws {
        // Frame 0 starts at angle 0; frame 1 rotates to 0.6. The births of frame 1 should spread over (0, 0.6], not sit
        // at 0.6 (rotation sign: angles grow toward -z for a +y rotation).
        let particles = try spin(frames: 2)
        let secondFrame = particles.map { abs(angle($0.position)) }.filter { $0 > 1e-3 }
        #expect(secondFrame.count >= 15)
        let spread = (secondFrame.max() ?? 0) - (secondFrame.min() ?? 0)
        #expect(spread > 0.4, "births span \(spread) radians of the 0.6 swept")
        // Still on the unit circle.
        #expect(particles.allSatisfy { abs(simd_length(SIMD2($0.position.x, $0.position.z)) - 1) < 1e-3 })
    }

    @Test func spinIsInheritedAsTangentialVelocity() throws {
        let particles = try spin(frames: 2, inheritVelocity: 1)
        // ω = 0.6 rad per 1/60 s = 36 rad/s about y; at radius 1 that is 36 units/s tangential.
        let born = particles.filter { abs(angle($0.position)) > 1e-3 }
        #expect(!born.isEmpty)
        let speeds = born.map { simd_length($0.velocity) }
        #expect(speeds.allSatisfy { abs($0 - 36) < 1.5 }, "speeds \(speeds.min() ?? 0)...\(speeds.max() ?? 0)")
        // Horizontal, and all circulating the same way as the emitter (a +y rotation turns x toward -z).
        #expect(born.allSatisfy { abs($0.velocity.y) < 1e-3 })
        #expect(born.allSatisfy { simd_cross($0.position, $0.velocity).y > 0 })
    }
}
