import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesShaders
import simd
import Testing

/// ParticlePlayer: the per-frame loop over a runtime.
@Suite(.serialized)
struct ParticlePlayerTests {
    let size = CGSize(width: 320, height: 180)
    let deltaTime: Float = 1.0 / 60.0

    func render(_ player: ParticlePlayer, renderer: OffscreenRenderer, frames: Int) throws -> OffscreenRenderer.Rendering? {
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<frames {
            rendering = try renderer.render(try player.frame(deltaTime: deltaTime, size: size))
        }
        return rendering
    }

    func particles(_ runtime: ParticleSystemRuntime) -> [Particle] {
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: runtime.capacity)
        return (0..<runtime.capacity).map { pointer[$0] }
    }

    @Test func clockAdvancesOnlyWhilePlaying() throws {
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: .fountain, device: renderer.device)
        _ = try render(player, renderer: renderer, frames: 30)
        #expect(abs(player.time - 0.5) < 1e-4)
        player.runtime.state = .paused
        _ = try render(player, renderer: renderer, frames: 10)
        #expect(abs(player.time - 0.5) < 1e-4)
        player.runtime.state = .playing
        player.runtime.speedFactor = 2
        _ = try render(player, renderer: renderer, frames: 30)
        #expect(abs(player.time - 1.5) < 1e-3)
        player.restart()
        #expect(player.time == 0)
    }

    @Test func stoppingResetsTheClock() throws {
        // Stop then play restarts the emitters; the player's clock (animated colliders, scripted pointer, tracked
        // objects) must start over with them.
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: .fountain, device: renderer.device)
        _ = try render(player, renderer: renderer, frames: 30)
        player.runtime.state = .stopped
        _ = try render(player, renderer: renderer, frames: 1)
        player.runtime.state = .playing
        #expect(player.time == 0)
    }

    @Test func matchesTheHandWrittenLoop() throws {
        // The loop the CLI, video export, and goldens used to write out by hand.
        let system = ParticleSystem.paddleWheel
        let renderer = try OffscreenRenderer(size: size)
        let manual = try ParticleSystemRuntime(device: renderer.device, emitters: [], capacity: 1)
        try manual.load(system)
        let view = simd_float4x4(lookingFrom: system.cameraEye, at: system.cameraTarget).inverse
        for frame in 0..<60 {
            let time = Float(frame) * deltaTime
            manual.forceFields = system.forceFields(at: time)
            manual.trackedObjects = system.trackedObjectPositions(at: time)
            _ = try renderer.render(try manual.simulate(deltaTime: deltaTime, colliders: system.colliders(at: time, pointer: nil), transforms: system.transforms(at: time, pointer: nil), view: view))
        }
        let player = try ParticlePlayer(system: system, device: renderer.device)
        _ = try render(player, renderer: renderer, frames: 60)
        let expected = particles(manual)
        let actual = particles(player.runtime)
        #expect(expected.count == actual.count)
        #expect(zip(expected, actual).allSatisfy { simd_distance($0.position, $1.position) < 1e-4 })
    }

    @Test func updateKeepsParticlesUnlessTheLayoutChanges() throws {
        let renderer = try OffscreenRenderer(size: size)
        var system = ParticleSystem.fountain
        let player = try ParticlePlayer(system: system, device: renderer.device)
        _ = try render(player, renderer: renderer, frames: 30)
        let runtimeBefore = player.runtime.buffer
        system.layers[0].settings.gravity = [0, -1, 0]
        try player.update(system)
        #expect(player.runtime.buffer === runtimeBefore)
        #expect(player.runtime.emitters[0].settings.gravity == [0, -1, 0])
        system.layers.append(system.layers[0].copy(named: "Second"))
        try player.update(system)
        #expect(player.runtime.emitters.count == 2)
        #expect(player.runtime.buffer !== runtimeBefore)
    }

    @Test func sceneDepthOnlyWhenTheSystemDrawsColliders() throws {
        let renderer = try OffscreenRenderer(size: size)
        #expect(try ParticlePlayer(system: .campfire, device: renderer.device).sceneDepth(size: size) == nil)
        let fog = try ParticlePlayer(system: .fog, device: renderer.device)
        let depth = try #require(try fog.sceneDepth(size: CGSize(width: 640, height: 360)))
        #expect(depth.width == 640 && depth.height == 360)
        #expect(try fog.sceneDepth(size: CGSize(width: 640, height: 360)) === depth)
    }

    @Test func thePointerDrivesBindings() throws {
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: .pointerStir, device: renderer.device)
        player.pointer = [0.7, 1.2, 0]
        _ = try render(player, renderer: renderer, frames: 1)
        #expect(player.runtime.colliders == ParticleSystem.pointerStir.colliders(at: 0, pointer: [0.7, 1.2, 0]))
        #expect(player.runtime.forceFields == ParticleSystem.pointerStir.forceFields(at: 0, pointer: [0.7, 1.2, 0]))
    }
}
