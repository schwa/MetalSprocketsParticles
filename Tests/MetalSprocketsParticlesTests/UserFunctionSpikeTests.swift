import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

// SPIKE #85: a user update function compiled at runtime in its own library, linked into the simulation kernel.
@Suite(.serialized)
struct UserFunctionSpikeTests {
    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;
    struct ParticleState {
        float3 position;
        float3 velocity;
        float age;
        float lifetime;
        uint id;
    };
    """

    @Test func userFunctionFromAnotherLibraryRuns() throws {
        let runner = try Runner()
        let source = Self.prelude + """
        [[visible]] void liftOff(thread ParticleState &p, float deltaTime, float time, constant float4 *parameters) {
            p.velocity = parameters[0].xyz;
        }
        """
        let userLibrary = try runner.device.makeLibrary(source: source, options: nil)
        let function = try VisibleFunction(library: userLibrary, name: "liftOff")

        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystem(device: runner.device, capacity: 16, emitter: emitter)
        system.userUpdate = function
        system.userParameters = [[0, 5, 0, 0]]
        system.burst(16)
        for _ in 0..<30 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let particles = system.buffer.contents().bindMemory(to: Particle.self, capacity: 16)
        // Without the function gravity would pull them down; with it they rise at 5 units/s.
        #expect((0..<16).allSatisfy { abs(particles[$0].velocity.y - 5) < 1e-4 && particles[$0].position.y > 2 })
    }
}
