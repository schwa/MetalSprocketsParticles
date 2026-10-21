import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// Shading pipelines when several runtimes share one renderer (#219).
@Suite(.serialized, .requiresMetal4)
struct ShadingPipelineTests {
    let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 100)

    func frame(_ renderer: OffscreenRenderer, _ configure: (inout ParticleEmitter) -> Void) throws {
        var settings = ParticleEmitter()
        settings.birthRate = 0
        configure(&settings)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 4, emitter: settings)
        system.burst(4)
        _ = try renderer.render(Group {
            try system.simulate(deltaTime: 1.0 / 60.0, view: view)
            try RenderPass { try system.render(projection: projection, view: view) }
        })
    }

    @Test func perPixelAfterPerVertexOnOneRenderer() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
        try frame(renderer) { $0.isLit = true }
        try frame(renderer) {
            $0.isLit = true
            $0.shadesPerPixel = true
        }
    }

    /// The demo's case: one runtime, Per Pixel turned on for a lit emitter.
    @Test func togglingPerPixelOnOneRuntime() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
        var settings = ParticleEmitter()
        settings.birthRate = 0
        settings.isLit = true
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 4, emitter: settings)
        system.burst(4)
        func render() throws {
            _ = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0, view: view)
                try RenderPass { try system.render(projection: projection, view: view) }
            })
        }
        try render()
        system.emitters[0].settings.shadesPerPixel = true
        try render()
    }

    @Test func perPixelTwiceOnOneRenderer() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
        let perPixel: (inout ParticleEmitter) -> Void = {
            $0.isLit = true
            $0.shadesPerPixel = true
        }
        try frame(renderer, perPixel)
        try frame(renderer, perPixel)
    }
}
