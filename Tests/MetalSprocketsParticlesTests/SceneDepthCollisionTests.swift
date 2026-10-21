import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct SceneDepthCollisionTests {
    /// Drops particles onto a sphere of radius 0.5 at the origin that the emitter does not collide with directly
    /// (categoryMask 0); the sphere is only in the scene depth. Returns the particles' final positions.
    func drop(collidesWithSceneDepth: Bool, frames: Int = 90) throws -> [SIMD3<Float>] {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .disc(radius: 0.1) }
        emitter.edit(ShapeModule.self) { $0.position = [0, 1.2, 0] }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = [0, -9.8, 0] }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter.edit(CollisionModule.self) { $0.restitution = 0 }
        emitter.edit(CollisionModule.self) { $0.friction = 1 }
        emitter.categoryMask = 0
        emitter.edit(CollisionModule.self) { $0.collidesWithSceneDepth = collidesWithSceneDepth }
        var system = ParticleSystem("Depth", layers: [EmitterDescription("Drops", modules: emitter, capacity: 32)])
        system.colliders = [.sphere(center: .zero, radius: 0.5)]
        system.drawsColliders = true
        system.cameraEye = [0, 1, 3]
        system.cameraTarget = [0, 0.3, 0]
        let size = CGSize(width: 256, height: 256)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        player.runtime.emitters[0].burst(32)
        for _ in 0..<frames {
            _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        let pointer = player.runtime.buffer.contents().bindMemory(to: Particle.self, capacity: player.runtime.capacity)
        return (0..<32).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    @Test func particlesRestOnGeometryOnlyInTheDepth() throws {
        let landed = try drop(collidesWithSceneDepth: true)
        // On the sphere's surface (within a few pixels), in its upper half; some slide down the curve.
        #expect(landed.allSatisfy { abs(simd_length($0) - 0.5) < 0.05 && $0.y > 0 })
    }

    @Test func withoutTheSettingTheyFallThrough() throws {
        let fallen = try drop(collidesWithSceneDepth: false)
        #expect(fallen.allSatisfy { $0.y < -1 })
    }

    @Test func depthHitsAreReportedAsColliderMinusOne() {
        let record = ParticleEventRecord(position: .zero, velocity: .zero, kind: .collision, emitterIndex: 0, colliderIndex: PARTICLE_EVENT_SCENE_DEPTH_COLLIDER, sequence: 1)
        #expect(ParticleEvent(record).kind == .collision(colliderIndex: -1))
    }
}
