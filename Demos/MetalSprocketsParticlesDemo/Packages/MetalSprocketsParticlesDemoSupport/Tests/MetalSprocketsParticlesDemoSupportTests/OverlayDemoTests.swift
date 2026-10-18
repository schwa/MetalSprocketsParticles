import CoreGraphics
import MetalSprockets
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import Testing

/// The 2D overlay demo's effects, without a window. Overlay physics (positioned bursts, view edges, the plane) are
/// tested in the library.
struct OverlayDemoTests {
    @Test func effectsAreFlatAndBurstFromTheButton() throws {
        let system = OverlayEffects.system
        #expect(system.layers.count == 2)
        // A key path here makes #expect think the call can throw.
        // swiftlint:disable:next prefer_key_path
        #expect(system.layers.allSatisfy { $0.settings.constrainsToPlane })
        #expect(system.layers.allSatisfy { $0.settings.birthRate == 0 })

        let runner = try Runner()
        let runtime = try ParticleSystemRuntime(device: runner.device, emitters: [], capacity: 1)
        try runtime.load(system)
        runtime.emitters[OverlayEffects.confetti].burst(300, at: [300, 172, 0])
        let colliders = Collider.edges(of: CGSize(width: 600, height: 400))
        // The live count is read a few frames late, so step past that.
        for _ in 0..<10 {
            try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0, colliders: colliders))
        }
        #expect(runtime.aliveParticleCount == 300)
    }
}
