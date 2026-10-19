import CoreGraphics
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
@testable import MetalSprocketsParticlesUI
import simd
import Testing

/// ParticleView's per-frame setup, without a window.
@Suite(.requiresMetal4)
struct ParticleViewTests {
    let size = CGSize(width: 800, height: 450)

    func player(_ state: ParticleViewState, _ system: ParticleSystem, runtime: ParticleSystemRuntime? = nil, camera: ParticleCamera = .system) throws -> ParticlePlayer {
        try state.player(system: system, runtime: runtime, seed: 0, camera: camera, size: size)
    }

    @Test func keepsThePlayerForTheSameSystemAndStartsOverForAnother() throws {
        let state = ParticleViewState()
        let first = try player(state, .campfire)
        #expect(first.runtime.emitters.count == ParticleSystem.campfire.layers.count)
        #expect(try player(state, .campfire) === first)
        let second = try player(state, .fountain)
        #expect(second !== first)
        #expect(second.runtime.emitters.count == ParticleSystem.fountain.layers.count)
    }

    @Test func usesTheCallersRuntime() throws {
        let state = ParticleViewState()
        let runtime = try ParticleSystemRuntime(emitters: [], capacity: 1)
        try runtime.load(.campfire)
        #expect(try player(state, .campfire, runtime: runtime).runtime === runtime)
    }

    @Test func overlayCameraMapsPointsToTheView() {
        let view = CGSize(width: 400, height: 200)
        let matrices = ParticleCamera.overlay.matrices(for: .campfire, size: view)
        let clip = matrices.projection * matrices.cameraToWorld.inverse * SIMD4<Float>(100, 50, 0, 1)
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        // (100, 50) in points from the top left is a quarter across and a quarter down.
        #expect(abs(ndc.x - -0.5) < 1e-4 && abs(ndc.y - 0.5) < 1e-4)
        #expect((0...1).contains(ndc.z))
        // Camera-facing sprites stay upright: the camera's up is screen up, which is world -y.
        #expect(simd_distance(matrices.cameraToWorld.columns.1.xyz, [0, -1, 0]) < 1e-5)
    }

    @Test func theMouseBecomesThePlayersPointer() throws {
        let state = ParticleViewState()
        #expect(try player(state, .pointerStir).pointer == nil)
        // The middle of the view projects to the camera target.
        state.pointerLocation = CGPoint(x: 0.5, y: 0.5)
        let pointer = try #require(try player(state, .pointerStir).pointer)
        #expect(simd_distance(pointer, ParticleSystem.pointerStir.cameraTarget) < 1e-3)
        // With the overlay camera, a quarter across and down is that point in the view.
        state.pointerLocation = CGPoint(x: 0.25, y: 0.25)
        let overlay = try #require(try player(state, .pointerStir, camera: .overlay).pointer)
        #expect(simd_distance(overlay, [200, 112.5, 0]) < 1e-2)
    }
}
