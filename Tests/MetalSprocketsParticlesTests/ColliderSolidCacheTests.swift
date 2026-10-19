import Foundation
@testable import MetalSprocketsParticles
import Testing

/// Solid collider meshes are tessellated once per change, not for every pass of every frame (#130: Fog and Sand on
/// Shapes spent about 10 ms a frame on the CPU doing it twice per frame).
struct ColliderSolidCacheTests {
    @Test func solidsAreMadeOncePerColliderChange() throws {
        let system = try ParticleSystemRuntime(capacity: 1, emitter: ParticleEmitter())
        system.colliders = [.sphere(center: .zero, radius: 1)]
        let first = system.colliderSolidVertices(planeExtent: 6)
        let cached = try #require(system.solidVertexCache)
        // Same colliders: the cached array comes back (same storage), not a new tessellation.
        let second = system.colliderSolidVertices(planeExtent: 6)
        #expect(first == second)
        second.withUnsafeBufferPointer { a in
            cached.vertices.withUnsafeBufferPointer { b in
                #expect(a.baseAddress == b.baseAddress)
            }
        }
        // Moving a collider rebuilds.
        system.colliders = [.sphere(center: [1, 0, 0], radius: 1)]
        let moved = system.colliderSolidVertices(planeExtent: 6)
        #expect(moved != first)
        #expect(system.solidVertexCache?.colliders == system.colliders)
    }
}
