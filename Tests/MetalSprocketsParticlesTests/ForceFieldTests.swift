import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ForceFieldTests {
    /// Still particles spawned at `origin` with no gravity, drag, or colliders; returns them after `steps` steps.
    func simulate(origin: SIMD3<Float> = .zero, radius: Float = 0, count: Int = 16, steps: Int, fields: [ForceField]) throws -> [Particle] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.position = origin
        emitter.radius = radius
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.lifetime = 100...100
        emitter.birthRate = 0
        let system = try ParticleSystem(device: runner.device, capacity: count, emitter: emitter, seed: 9)
        system.forceFields = fields
        system.burst(count)
        for _ in 0..<steps {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: system.capacity))
    }

    func velocity(_ particle: Particle) -> SIMD3<Float> {
        SIMD3(particle.velocity.x, particle.velocity.y, particle.velocity.z)
    }

    @Test func noFieldsNoMotion() throws {
        let particles = try simulate(steps: 30, fields: [])
        #expect(particles.allSatisfy { velocity($0) == .zero })
    }

    @Test func windApproachesWindVelocity() throws {
        // dv/dt = (5 - v) * 2 → v(1 s) ≈ 5 (1 - e^-2) ≈ 4.32; explicit Euler lands slightly above.
        let particles = try simulate(steps: 60, fields: [.wind(velocity: [5, 0, 0], strength: 2)])
        for particle in particles {
            #expect(particle.velocity.x > 4.1 && particle.velocity.x < 4.6)
            #expect(particle.velocity.y == 0 && particle.velocity.z == 0)
        }
    }

    @Test func attractorPullsAndNegativeRepels() throws {
        let pulled = try simulate(origin: [2, 0, 0], steps: 10, fields: [.attractor(center: .zero, strength: 3)])
        let pushed = try simulate(origin: [2, 0, 0], steps: 10, fields: [.attractor(center: .zero, strength: -3)])
        #expect(pulled.allSatisfy { $0.velocity.x < 0 })
        #expect(pushed.allSatisfy { $0.velocity.x > 0 })
    }

    @Test func attractorRadiusLimitsRange() throws {
        let particles = try simulate(origin: [2, 0, 0], steps: 10, fields: [.attractor(center: .zero, strength: 3, radius: 1)])
        #expect(particles.allSatisfy { velocity($0) == .zero })
    }

    @Test func vortexSwirlsAroundAxis() throws {
        // At +x around +y, counterclockwise looking down +y is the -z direction: cross(y, x) = -z.
        let particles = try simulate(origin: [1, 0, 0], steps: 5, fields: [.vortex(center: .zero, strength: 2)])
        for particle in particles {
            #expect(particle.velocity.z < 0)
            #expect(particle.velocity.y == 0)
        }
    }

    @Test func turbulenceMovesParticlesDifferently() throws {
        let particles = try simulate(radius: 2, count: 64, steps: 30, fields: [.turbulence(strength: 3, scale: 1.5)])
        let speeds = particles.map { simd_length(velocity($0)) }
        #expect(speeds.allSatisfy { $0 > 0 })
        // Different places in the noise field push different ways.
        #expect(Set(particles.map { $0.velocity.x.sign }).count == 2)
    }

    @Test func zeroStrengthTurbulenceDoesNothing() throws {
        let particles = try simulate(radius: 2, steps: 10, fields: [.turbulence(strength: 0)])
        #expect(particles.allSatisfy { velocity($0) == .zero })
    }
}
