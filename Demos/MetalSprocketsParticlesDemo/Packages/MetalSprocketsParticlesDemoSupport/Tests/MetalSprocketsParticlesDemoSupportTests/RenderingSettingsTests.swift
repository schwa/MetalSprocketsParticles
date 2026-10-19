import CoreGraphics
import Metal
import MetalSprockets
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import MetalSprocketsParticlesSamples
import simd
import Testing

/// The Rendering tab's settings (the viewport itself needs a window, so formats are checked offscreen).
@Suite(.requiresMetal4)
struct RenderingSettingsTests {
    @Test func defaultFormatMatchesGoldenImages() {
        #expect(ViewportColorFormat.srgb8.pixelFormat == ParticleSystemRuntime.colorPixelFormat)
        #expect(ViewportColorFormat.allCases.filter(\.supportsExtendedDynamicRange) == [.float16])
    }

    /// Every format the tab offers renders sprites, soft particles, solid colliders, meshes, and ribbons.
    @Test(arguments: ViewportColorFormat.allCases)
    func everyFormatRenders(_ format: ViewportColorFormat) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let size = CGSize(width: 160, height: 90)
        let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format.pixelFormat, width: 160, height: 90, mipmapped: false)
        color.usage = [.renderTarget, .shaderRead]
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 160, height: 90, mipmapped: false)
        depth.usage = [.renderTarget]
        depth.storageMode = .private
        let colorTexture = try #require(device.makeTexture(descriptor: color))
        let renderer = try OffscreenRenderer(size: size, colorTexture: colorTexture, depthTexture: try #require(device.makeTexture(descriptor: depth)))
        for name in ["Fog", "Coin Shower", "Light Ribbons"] {
            let system = try #require(ParticleSystem.all.first { $0.name == name })
            let player = try ParticlePlayer(system: system, device: device)
            for _ in 0..<10 {
                _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
            }
            #expect(player.runtime.aliveParticleCount > 0, "\(name) in \(format.name)")
        }
    }

    @MainActor
    @Test func reverseZReachesThePlayer() throws {
        let model = ParticlesDemoModel()
        model.reverseZ = true
        let player = try #require(try model.player(projection: matrix_identity_float4x4, cameraToWorld: matrix_identity_float4x4))
        #expect(player.runtime.reverseZ)
    }
}
