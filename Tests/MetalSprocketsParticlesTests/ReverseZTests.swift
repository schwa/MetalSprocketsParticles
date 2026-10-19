import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import Testing

/// `ParticleSystemRuntime.reverseZ` (#144): the same pictures and physics with depth running from 1 near to 0 far.
@Suite(.serialized, .requiresMetal4)
struct ReverseZTests {
    @Test func reversedProjectionsSendNearToOneAndFarToZero() {
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 100)
        let reversed = ParticleSystemRuntime.reversingDepth(projection)
        func depth(_ matrix: simd_float4x4, at distance: Float) -> Float {
            let clip = matrix * SIMD4<Float>(0, 0, -distance, 1)
            return clip.z / clip.w
        }
        #expect(abs(depth(projection, at: 0.1)) < 1e-4)
        #expect(abs(depth(reversed, at: 0.1) - 1) < 1e-4)
        #expect(abs(depth(reversed, at: 100)) < 1e-4)
        #expect(depth(reversed, at: 10) > depth(reversed, at: 20))
    }

    /// Mean difference per channel (0...255) between a preset rendered in forward and reverse Z.
    func difference(preset: String, frames: Int = 60) throws -> Double {
        let system = try #require(ParticleSystem.all.first { $0.name == preset })
        let size = CGSize(width: 320, height: 180)
        let renderer = try OffscreenRenderer(size: size)
        func render(reverseZ: Bool) throws -> [SIMD4<UInt8>] {
            let player = try ParticlePlayer(system: system, device: renderer.device)
            player.runtime.reverseZ = reverseZ
            var image: CGImage?
            for _ in 0..<frames {
                image = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size)).cgImage
            }
            return try #require(image).rgbaPixels()
        }
        let forward = try render(reverseZ: false)
        let reverse = try render(reverseZ: true)
        let total = zip(forward, reverse).reduce(0) { sum, pair in
            sum + Int(abs(Int(pair.0.x) - Int(pair.1.x))) + Int(abs(Int(pair.0.y) - Int(pair.1.y))) + Int(abs(Int(pair.0.z) - Int(pair.1.z)))
        }
        return Double(total) / Double(forward.count * 3)
    }

    /// Guards the two tests below against passing because reverseZ does nothing: with reverse Z on but a forward
    /// projection, depth tests and the far-plane checks disagree and the picture breaks.
    @Test func reverseZReallyChangesDepthTesting() throws {
        let system = try #require(ParticleSystem.all.first { $0.name == "Fog" })
        let size = CGSize(width: 320, height: 180)
        let renderer = try OffscreenRenderer(size: size)
        func render(reverseZ: Bool) throws -> [SIMD4<UInt8>] {
            let player = try ParticlePlayer(system: system, device: renderer.device)
            player.runtime.reverseZ = reverseZ
            let forwardProjection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
            let view = simd_float4x4(lookingFrom: system.cameraEye, at: system.cameraTarget).inverse
            var image: CGImage?
            for _ in 0..<30 {
                image = try renderer.render(try player.frame(
                    deltaTime: 1.0 / 60.0, projection: forwardProjection, view: view, sceneDepth: player.sceneDepth(size: size)
                )).cgImage
            }
            return try #require(image).rgbaPixels()
        }
        let right = try render(reverseZ: false)
        let mismatched = try render(reverseZ: true)
        let differing = zip(right, mismatched).filter { abs(Int($0.0.x) - Int($0.1.x)) > 20 }.count
        #expect(differing > right.count / 20)
    }

    @Test func softParticlesAndSolidCollidersLookTheSame() throws {
        // Fog: solid colliders in the scene depth pass and the main pass, and soft particles against them.
        #expect(try difference(preset: "Fog") < 1)
    }

    @Test func meshParticlesLookTheSame() throws {
        // Coin Shower: mesh particles depth-tested against each other and the floor.
        #expect(try difference(preset: "Coin Shower") < 1)
    }

    @Test func depthCollisionWorksInReverseZ() throws {
        var emitter = ParticleEmitter()
        emitter.shape = .disc(radius: 0.1)
        emitter.position = [0, 1.2, 0]
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0
        emitter.friction = 1
        emitter.categoryMask = 0
        emitter.collidesWithSceneDepth = true
        var system = ParticleSystem("Depth", layers: [EmitterDescription("Drops", settings: emitter, capacity: 16)])
        system.colliders = [.sphere(center: .zero, radius: 0.5)]
        system.drawsColliders = true
        system.cameraEye = [0, 1, 3]
        system.cameraTarget = [0, 0.3, 0]
        let size = CGSize(width: 256, height: 256)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        player.runtime.reverseZ = true
        player.runtime.emitters[0].burst(16)
        for _ in 0..<90 {
            _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        let pointer = player.runtime.buffer.contents().bindMemory(to: Particle.self, capacity: player.runtime.capacity)
        let landed = (0..<16).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
        #expect(landed.allSatisfy { abs(simd_length($0) - 0.5) < 0.05 && $0.y > 0 })
    }
}
