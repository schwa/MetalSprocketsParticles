import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct ParticleLODTests {
    let view = simd_float4x4(lookingFrom: [0, 0, 5], at: .zero).inverse
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 100)

    func camera() -> CullingCamera {
        CullingCamera(position: [0, 0, 5], viewProjection: projection * view)
    }

    @Test func frustumTest() {
        let viewProjection = projection * view
        typealias Emitter = ParticleSystemRuntime.Emitter
        #expect(Emitter.sphereIntersectsFrustum(center: .zero, radius: 0.1, viewProjection: viewProjection))
        // Behind the camera.
        #expect(!Emitter.sphereIntersectsFrustum(center: [0, 0, 10], radius: 1, viewProjection: viewProjection))
        // Far off to the side, and just touching the edge.
        #expect(!Emitter.sphereIntersectsFrustum(center: [20, 0, 0], radius: 1, viewProjection: viewProjection))
        #expect(Emitter.sphereIntersectsFrustum(center: [20, 0, 0], radius: 19, viewProjection: viewProjection))
    }

    func emitter(at position: SIMD3<Float>, _ configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.position = position
        emitter.birthRate = 600
        configure(&emitter)
        return emitter
    }

    /// Particles spawned by one emitter in one 1/30 s step.
    func spawnCount(_ settings: ParticleEmitter, camera: CullingCamera?) throws -> Int {
        let system = try ParticleSystemRuntime(capacity: 1_000, emitter: settings)
        system.cullingCamera = camera
        let plan = try system.planFrame(deltaTime: 1.0 / 30.0)
        return plan.dispatches.reduce(0) { $0 + Int($1.uniforms.spawn.count) }
    }

    @Test func emissionFallsOffWithDistance() throws {
        func lod(_ settings: inout ParticleEmitter) {
            settings.lodNearDistance = 10
            settings.lodFarDistance = 30
            settings.lodFarRateScale = 0.25
        }
        #expect(try spawnCount(emitter(at: .zero, lod), camera: camera()) == 20)
        #expect(try spawnCount(emitter(at: [0, 0, -45], lod), camera: camera()) == 5)
        // Halfway: 1 - 0.75 / 2.
        #expect(try spawnCount(emitter(at: [0, 0, -15], lod), camera: camera()) == 12)
        // No camera yet: full rate.
        #expect(try spawnCount(emitter(at: [0, 0, -45], lod), camera: nil) == 20)
    }

    @Test func culledEmittersSimulateUnlessToldNotTo() throws {
        let offscreen: SIMD3<Float> = [50, 0, 0]
        let keepsGoing = emitter(at: offscreen) { $0.cullingRadius = 1 }
        let freezes = emitter(at: offscreen) {
            $0.cullingRadius = 1
            $0.simulatesWhenCulled = false
        }
        let system = try ParticleSystemRuntime(emitters: [keepsGoing, freezes], capacity: 100)
        system.cullingCamera = camera()
        let plan = try system.planFrame(deltaTime: 1.0 / 60.0)
        // swiftlint:disable:next prefer_key_path
        #expect(system.emitters.allSatisfy { $0.isCulled })
        #expect(plan.dispatches.count == 1)
        #expect(plan.dispatches[0].uniforms.spawn.sliceStart == UInt32(system.emitters[0].range.lowerBound))
    }

    @Test func culledEmittersAreNotDrawn() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        func render(cullingRadius: Float) throws -> Int {
            var settings = emitter(at: [50, 0, 0]) {
                $0.cullingRadius = cullingRadius
                $0.birthRate = 0
                $0.velocity = .zero
                $0.velocitySpread = 0
                $0.gravity = .zero
                $0.sizeOverLife = .constant(1)
                $0.colorOverLife = .constant([1, 1, 1, 1])
            }
            settings.lifetime = 10...10
            let system = try ParticleSystemRuntime(device: renderer.device, capacity: 16, emitter: settings)
            // Particles in the middle of the view, from an emitter whose culling sphere is far off to the side.
            system.burst(16, at: [-50, 0, 0])
            var image: CGImage?
            for _ in 0..<2 {
                image = try renderer.render(Group {
                    try system.simulate(deltaTime: 1.0 / 60.0)
                    try RenderPass { try system.render(projection: projection, view: view) }
                }).cgImage
            }
            return try #require(image).rgbaPixels().filter { $0.x > 50 }.count
        }
        #expect(try render(cullingRadius: 0) > 0)
        #expect(try render(cullingRadius: 1) == 0)
    }
}
