import CoreGraphics
import MetalSprockets
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import simd
import Testing

/// The 2D overlay demo's effects, without a window. Overlay physics (positioned bursts, view edges, the plane) are
/// tested in the library.
@Suite(.requiresMetal4)
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

    /// Spread and speed variation are absolute speeds, so in points they must be in proportion to the launch speed;
    /// values like 0.7 meant for meters left the confetti in a blob (#140). The spreading itself is tested in the
    /// library (OverlayTests.overlayConfettiSpreads).
    /// In 2D, new emitters start from the 2D defaults (points), and the scene saves as 2D (#141).
    @MainActor
    @Test func twoDModeAddsTwoDEmittersAndSaves() {
        let model = ParticlesDemoModel()
        model.is2D = true
        model.addEmitter()
        #expect(model.emitters.last?.settings == ParticleEmitter.default2D)
        #expect(model.currentEffect.is2D)
        model.is2D = false
        model.addEmitter()
        #expect(model.emitters.last?.settings != ParticleEmitter.default2D)
        #expect(!model.currentEffect.is2D)
    }

    @Test func spreadsAreInPointsPerSecond() {
        for layer in OverlayEffects.system.layers {
            let speed = simd_length(layer.settings.velocity)
            #expect(layer.settings.velocitySpread > speed * 0.3, "\(layer.name)")
            #expect(layer.settings.speedVariation > speed * 0.2, "\(layer.name)")
        }
    }
}
