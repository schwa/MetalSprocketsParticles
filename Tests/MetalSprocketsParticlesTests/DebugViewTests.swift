import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct DebugViewTests {
    func still(at position: SIMD3<Float>, size: Float = 0.6) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = position
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.sizeOverLife = .constant(size)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        return emitter
    }

    func render(_ emitters: [ParticleEmitter], burst: Int = 1, view debugView: ParticleDebugView) throws -> [SIMD4<UInt8>] {
        let renderer = try OffscreenRenderer(size: CGSize(width: 128, height: 64))
        let system = try ParticleSystemRuntime(device: renderer.device, emitters: emitters, capacity: burst)
        system.debugView = debugView
        system.emitters.forEach { $0.burst(burst) }
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 2, near: 0.1, far: 10)
        return try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.rgbaPixels()
    }

    @Test func emittersGetDistinctColors() throws {
        let pixels = try render([still(at: [-1, 0, 0]), still(at: [1, 0, 0])], view: .emitter)
        let left = pixels[32 * 128 + 45]
        let right = pixels[32 * 128 + 83]
        #expect(left != right)
        // White particles are no longer white.
        #expect(!(left.x > 240 && left.y > 240 && left.z > 240))
    }

    @Test func wireframesDrawOnlyEdges() throws {
        func lit(_ view: ParticleDebugView) throws -> Int {
            try render([still(at: .zero, size: 1)], view: view).filter { $0.x > 40 || $0.y > 40 }.count
        }
        let filled = try lit(.none)
        let lines = try lit(.wireframe)
        #expect(lines > 0)
        #expect(lines < filled / 2)
    }

    @Test func overdrawAddsUp() throws {
        // Ten particles on one spot add up to about ten times the light of one. The target is sRGB, so decode first.
        func light(_ count: Int) throws -> Float {
            let encoded = Float(try render([still(at: .zero)], burst: count, view: .overdraw)[32 * 128 + 64].x) / 255
            return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
        }
        let many = try light(10)
        let one = try light(1)
        #expect(many > one * 8 && many < one * 12)
    }

    @Test func ageRunsFromBlue() throws {
        // Just born: the cold end of the ramp.
        let center = try render([still(at: .zero)], view: .age)[32 * 128 + 64]
        #expect(center.z > center.x)
    }

    @Test func noneLeavesColorsAlone() throws {
        let normal = try render([still(at: .zero)], view: .none)
        var emitter = still(at: .zero)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        #expect(try render([emitter], view: .none) == normal)
    }
}
