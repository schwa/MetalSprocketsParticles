import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// One still white particle at the origin, seen from 3 units away; checks the brightness of the center pixel.
@Suite(.serialized, .requiresMetal4)
struct LightingTests {
    let size = CGSize(width: 64, height: 64)
    let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
    var projection: simd_float4x4 {
        .perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 100)
    }

    func centerBrightness(_ configure: (inout ParticleEmitter) -> Void = { _ in }, system setUp: (ParticleSystemRuntime) -> Void = { _ in }, sceneDepth: Float? = nil) throws -> Float {
        let renderer = try OffscreenRenderer(size: size)
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.sizeOverLife = .constant(0.5)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        configure(&emitter)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter)
        setUp(system)
        system.burst(1)
        let depthTexture = try sceneDepth.map { try makeDepthTexture(device: renderer.device, depth: $0) }
        let rendering = try renderer.render(Group {
            try system.simulate(deltaTime: 1.0 / 60.0, view: view)
            try RenderPass {
                try system.render(projection: projection, view: view, sceneDepth: depthTexture)
            }
        })
        return try centerPixel(rendering.cgImage)
    }

    /// A scene depth texture holding the depth-buffer value of a surface `distance` in front of the camera.
    func makeDepthTexture(device: MTLDevice, depth distance: Float) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: Int(size.width), height: Int(size.height), mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let clip = projection * SIMD4<Float>(0, 0, -distance, 1)
        let values = [Float](repeating: clip.z / clip.w, count: Int(size.width * size.height))
        texture.replace(region: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0, withBytes: values, bytesPerRow: Int(size.width) * 4)
        return texture
    }

    func centerPixel(_ image: CGImage) throws -> Float {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2), width: CGFloat(image.width), height: CGFloat(image.height)))
        return Float(pixel[0]) / 255
    }

    @Test func unlitIsUnchangedAndLitUsesAmbient() throws {
        let unlit = try centerBrightness()
        let lit = try centerBrightness { $0.isLit = true }
        #expect(unlit > 0.95)
        // Ambient 0.25 linear is about 0.54 in sRGB.
        #expect(lit > 0.45 && lit < 0.65)
    }

    @Test func lightFacingTheCameraBrightensAndLightFromBehindDoesNot() throws {
        let front = try centerBrightness({ $0.isLit = true }, system: { $0.lights = [.directional(direction: [0, 0, -1])] })
        let behind = try centerBrightness({ $0.isLit = true }, system: { $0.lights = [.directional(direction: [0, 0, 1])] })
        let ambientOnly = try centerBrightness { $0.isLit = true }
        // Lit at the corners, whose normals lean away from the camera, so the center is bright but not white.
        #expect(front > ambientOnly + 0.25)
        #expect(abs(behind - ambientOnly) < 0.02)
    }

    /// A custom shading function runs per vertex and gets its parameters (#172). Center pixel is the red channel.
    @Test func customShadingFunctionRuns() throws {
        let half = ParticleFunction(source: """
        [[visible]] float4 halfRed(ShadingInput input, ShadingScene scene, constant ShadingLight *lights, const device ShadingLight *particleLights, constant float4 *parameters) {
            return float4(input.color.rgb * parameters[0].x, input.color.a);
        }
        """, name: "halfRed", parameters: [[0.2, 0, 0, 0]])
        try half.validateShading(device: try #require(MTLCreateSystemDefaultDevice()))
        let shaded = try centerBrightness { $0.shadingFunction = half }
        // 0.2 linear is about 0.48 in sRGB.
        #expect(shaded > 0.4 && shaded < 0.56)
        #expect(try ShadingModule.template.validateShading(device: try #require(MTLCreateSystemDefaultDevice())) == ())
    }

    @Test func pointLightRangeFallsOff() throws {
        let near = try centerBrightness({ $0.isLit = true }, system: {
            $0.ambientLight = .zero
            $0.lights = [.point(position: [0, 0, 1], range: 10)]
        })
        let outOfRange = try centerBrightness({ $0.isLit = true }, system: {
            $0.ambientLight = .zero
            $0.lights = [.point(position: [0, 0, 1], range: 0.5)]
        })
        #expect(near > 0.5)
        #expect(outOfRange < 0.02)
    }

    /// Center brightness with `colliders` drawn as solids into a scene depth (via `renderScene`).
    func centerBrightnessWithSolids(_ colliders: [Collider], softness: Float) throws -> Float {
        let renderer = try OffscreenRenderer(size: size)
        var emitter = ParticleEmitter()
        emitter.radius = 0
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.sizeOverLife = .constant(0.5)
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.softness = softness
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: emitter)
        system.colliders = colliders
        system.burst(1)
        let sceneDepth = try SceneDepth(device: renderer.device, width: Int(size.width), height: Int(size.height))
        let rendering = try renderer.render(Group {
            try system.simulate(deltaTime: 1.0 / 60.0, view: view)
            try system.renderScene(projection: projection, view: view, sceneDepth: sceneDepth)
        })
        return try centerPixel(rendering.cgImage)
    }

    @Test func colliderSolidsFeedSoftParticles() throws {
        // A wall just behind the particle (3.05 from the camera) softens it; with softness off it stays bright and
        // covers the wall. A wall in front hides it.
        let behind = Collider.plane(normal: [0, 0, 1], distance: -0.05)
        let inFront = Collider.plane(normal: [0, 0, 1], distance: 0.5)
        let soft = try centerBrightnessWithSolids([behind], softness: 0.5)
        let hard = try centerBrightnessWithSolids([behind], softness: 0)
        let hidden = try centerBrightnessWithSolids([inFront], softness: 0.5)
        #expect(hard > 0.95)
        #expect(soft < hard - 0.3)
        #expect(hidden < 0.3)
    }

    @Test func softParticlesFadeNearTheSceneDepth() throws {
        // The particle is 3 units away. A surface at 3.05 is within 0.5 of softness; one at 10 is not.
        let hard = try centerBrightness({ $0.softness = 0.5 }, sceneDepth: 3.05)
        let farSurface = try centerBrightness({ $0.softness = 0.5 }, sceneDepth: 10)
        let softnessOff = try centerBrightness({ $0.softness = 0 }, sceneDepth: 3.05)
        #expect(hard < 0.5)
        #expect(farSurface > 0.95)
        #expect(softnessOff > 0.95)
    }
}
