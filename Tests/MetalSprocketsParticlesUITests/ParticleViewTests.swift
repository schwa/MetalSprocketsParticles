import CoreGraphics
@testable import MetalSprocketsParticles
@testable import MetalSprocketsParticlesUI
import simd
import Testing

/// ParticleView's per-frame work, without a window.
struct ParticleViewTests {
    let size = CGSize(width: 800, height: 450)

    func frame(_ state: ParticleViewState, _ preset: ParticlePreset, system: ParticleSystem? = nil, time: Float = 0) throws -> ParticleViewFrame {
        try state.frame(preset: preset, system: system, camera: (preset.cameraEye, preset.cameraTarget), drawableSize: size, time: time)
    }

    @Test func loadsThePresetOnceAndReloadsWhenItChanges() throws {
        let state = ParticleViewState(seed: 0)
        let first = try frame(state, .campfire).system
        #expect(first.emitters.count == ParticlePreset.campfire.layers.count)
        #expect(try frame(state, .campfire).system === first)
        let second = try frame(state, .fountain).system
        #expect(second !== first)
        #expect(second.emitters.count == ParticlePreset.fountain.layers.count)
    }

    @Test func usesTheCallersSystem() throws {
        let state = ParticleViewState(seed: 0)
        let system = try ParticleSystem(emitters: [], capacity: 1)
        try system.load(.campfire)
        #expect(try frame(state, .campfire, system: system).system === system)
        #expect(state.ownedSystem == nil)
    }

    @Test func sceneDepthOnlyWhenThePresetDrawsColliders() throws {
        let state = ParticleViewState(seed: 0)
        #expect(try frame(state, .campfire).sceneDepth == nil)
        let fog = try #require(try frame(state, .fog).sceneDepth)
        #expect(fog.width == 800 && fog.height == 450)
    }

    @Test func thePointerDrivesBindingsAndFallsBackToItsPath() throws {
        let state = ParticleViewState(seed: 0)
        let preset = ParticlePreset.pointerStir
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
