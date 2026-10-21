import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.requiresMetal4)
struct SpinMotionTests {
    @Test func pitchStandsARingUpright() {
        let transform = EmitterMotion(pitch: .pi / 2).transform(time: 0)
        // The ring's axis, local +Y, now faces +Z.
        let axis = transform * SIMD4<Float>(0, 1, 0, 0)
        #expect(simd_distance(SIMD3(axis.x, axis.y, axis.z), [0, 0, 1]) < 1e-5)
    }

    @Test func spinTurnsAroundTheLocalAxisOverTime() {
        let motion = EmitterMotion(pitch: .pi / 2, spin: .pi)
        let start = motion.transform(time: 0) * SIMD4<Float>(1, 0, 0, 0)
        let half = motion.transform(time: 1) * SIMD4<Float>(1, 0, 0, 0)
        // Half a turn later, local +X points the other way; the axis does not move.
        #expect(simd_distance(SIMD3(half.x, half.y, half.z), -SIMD3(start.x, start.y, start.z)) < 1e-5)
        let axis = motion.transform(time: 1) * SIMD4<Float>(0, 1, 0, 0)
        #expect(simd_distance(SIMD3(axis.x, axis.y, axis.z), [0, 0, 1]) < 1e-5)
    }
}

@Suite(.serialized, .requiresMetal4)
struct TangentDirectionTests {
    @Test func tangentVelocityRunsAroundTheAxis() throws {
        let runner = try Runner()
        let emitter = EmitterModules.standard(position: [0, 0.5, 0], shape: .disc(radius: 1), velocity: [0, 2, 0], spread: 0, gravity: .zero, lifetime: 10...10, birthRate: 0) {
            $0.edit(ShapeModule.self) {
                $0.birthLocation = .surface
                $0.birthDirection = .tangent
            }
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 256, modules: emitter, seed: 1)
        system.burst(256)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        for index in 0..<system.capacity {
            let particle = pointer[index]
            let radial = SIMD3(particle.position.x, 0, particle.position.z)
            let velocity = SIMD3(particle.velocity.x, particle.velocity.y, particle.velocity.z)
            // Full speed, perpendicular to the radius and the axis, counterclockwise about +Y (right-hand rule).
            #expect(abs(simd_length(velocity) - 2) < 1e-4)
            #expect(abs(simd_dot(velocity, radial)) < 1e-4)
            #expect(abs(velocity.y) < 1e-5)
            #expect(simd_cross(radial, velocity).y > 0)
        }
    }
}
