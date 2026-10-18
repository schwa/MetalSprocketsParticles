import CoreGraphics
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
@testable import MetalSprocketsParticlesUI
import simd
import Testing

/// ParticleView's per-frame work, without a window.
struct ParticleViewTests {
    let size = CGSize(width: 800, height: 450)

    func frame(_ state: ParticleViewState, _ system: ParticleSystem, runtime: ParticleSystemRuntime? = nil, time: Float = 0) throws -> ParticleViewFrame {
        try state.frame(system: system, runtime: runtime, camera: .system, size: (size, size), time: time)
    }

    @Test func loadsTheSystemOnceAndReloadsWhenItChanges() throws {
        let state = ParticleViewState(seed: 0)
        let first = try frame(state, .campfire).runtime
        #expect(first.emitters.count == ParticleSystem.campfire.layers.count)
        #expect(try frame(state, .campfire).runtime === first)
        let second = try frame(state, .fountain).runtime
        #expect(second !== first)
        #expect(second.emitters.count == ParticleSystem.fountain.layers.count)
    }

    @Test func usesTheCallersRuntime() throws {
        let state = ParticleViewState(seed: 0)
        let runtime = try ParticleSystemRuntime(emitters: [], capacity: 1)
        try runtime.load(.campfire)
        #expect(try frame(state, .campfire, runtime: runtime).runtime === runtime)
        #expect(state.ownedRuntime == nil)
    }

    @Test func sceneDepthOnlyWhenTheSystemDrawsColliders() throws {
        let state = ParticleViewState(seed: 0)
        #expect(try frame(state, .campfire).sceneDepth == nil)
        let fog = try #require(try frame(state, .fog).sceneDepth)
        #expect(fog.width == 800 && fog.height == 450)
    }

    @Test func overlayCameraMapsPointsToTheView() throws {
        let view = CGSize(width: 400, height: 200)
        let matrices = ParticleViewCamera.overlay.matrices(for: .campfire, size: view)
        let clip = matrices.projection * matrices.cameraToWorld.inverse * SIMD4<Float>(100, 50, 0, 1)
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        // (100, 50) in points from the top left is a quarter across and a quarter down.
        #expect(abs(ndc.x - -0.5) < 1e-4 && abs(ndc.y - 0.5) < 1e-4)
        #expect((0...1).contains(ndc.z))
        // Camera-facing sprites stay upright: the camera's up is screen up, which is world -y.
        #expect(simd_distance(matrices.cameraToWorld.columns.1.xyz, [0, -1, 0]) < 1e-5)
        // A mouse location a quarter across and down is that point in the world.
        let point = try #require(PointerProjection.worldPosition(
            of: CGPoint(x: 0.25, y: 0.25), in: CGSize(width: 1, height: 1),
            projection: matrices.projection, cameraToWorld: matrices.cameraToWorld, planePoint: matrices.focus
        ))
        #expect(simd_distance(point, [100, 50, 0]) < 1e-2)
    }

    @Test func thePointerDrivesBindingsAndFallsBackToItsPath() throws {
        let state = ParticleViewState(seed: 0)
        let preset = ParticleSystem.pointerStir
        let scripted = try frame(state, preset, time: 1).colliders
        #expect(scripted == preset.colliders(at: 1, pointer: nil))
        // The middle of the view projects to the camera target.
        state.pointerLocation = CGPoint(x: 0.5, y: 0.5)
        let live = try frame(state, preset, time: 1).colliders
        #expect(simd_distance(live[0].center, preset.cameraTarget) < 1e-3)
        #expect(simd_distance(scripted[0].center, preset.cameraTarget) > 0.1)
    }
}

private extension Collider {
    var center: SIMD3<Float> {
        switch shape {
        case let .sphere(center, _), let .box(center, _, _): center
        case let .capsule(start, end, _): (start + end) / 2
        case let .plane(normal, distance): normal * distance
        }
    }
}
