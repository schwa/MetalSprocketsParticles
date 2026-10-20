import Foundation
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesUI
import MetalSprocketsUI
import simd
import SwiftUI
import Testing

// The code samples in README.md, kept here so they keep compiling. Update both together.

enum ReadmeExamples {
    static func loadEffects(from url: URL) throws -> [ParticleSystem] {
        // An effect file saved from the demo app or with ParticleSystem.write(to:).
        let torch = try ParticleSystem(contentsOf: url)

        // A sample preset, from the MetalSprocketsParticlesSamples library.
        let campfire = ParticleSystem.campfire

        return [torch, campfire]
    }

    static func buildEffect() -> ParticleSystem {
        ParticleSystem("Torch", cameraEye: [0, 1, 3], cameraTarget: [0, 0.6, 0]) {
            EmitterDescription("Flame", sprite: .smoke) {
                ShapeModule(shape: .disc(radius: 0.3))
                RateModule(birthRate: 400)
                LifetimeModule(range: 0.6...1.2)
                VelocityModule(velocity: [0, 1.5, 0], spread: 0.3)
                SizeOverLifeModule(curve: .linear(from: 0.15, to: 0.4))
                ColorOverLifeModule(color: .linear(from: [1, 0.8, 0.3, 1], to: [1, 0.1, 0, 0]))
                SpriteModule(blendMode: .additive)
            }
            Collider.plane(normal: [0, 1, 0], distance: 0)
            ForceField.turbulence(strength: 1.5, scale: 1, speed: 0.5)
        }
    }

    struct TorchView: View {
        // Make the system once, not in `body`: a system built in `body` gets new emitter ids on every update, which
        // restarts the effect.
        @State private var torch = ParticleSystem.campfire

        var body: some View {
            ParticleView(torch)
        }
    }

    /// Particles in your own MetalSprockets scene.
    struct SceneView: View {
        let runtime: ParticleSystemRuntime
        @State private var camera = simd_float4x4(lookingFrom: [0, 2, 5], at: [0, 1, 0])

        init(system: ParticleSystem) throws {
            runtime = try ParticleSystemRuntime()
            try runtime.load(system)
        }

        var body: some View {
            RenderView(colorPixelFormat: ParticleSystemRuntime.colorPixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
                let view = camera.inverse
                let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
                let time = context.frameUniforms.time
                // Move a ball through the effect; particles bounce off it.
                let ball = Collider.sphere(center: [sin(time) * 1.5, 0.5, 0], radius: 0.4)
                // Step the simulation. The view lets sorted emitters draw back to front.
                try runtime.simulate(deltaTime: context.frameUniforms.deltaTime, colliders: [.plane(normal: [0, 1, 0], distance: 0), ball], view: view)
                try RenderPass {
                    // Draw your own opaque geometry first, then the particles.
                    try runtime.renderColliderSolids(projection: projection, view: view)
                    try runtime.render(projection: projection, view: view)
                }
            }
        }
    }
}

@Suite(.requiresMetal4)
struct ReadmeExampleTests {
    @Test func builtEffectLoads() throws {
        let system = try ParticleSystemRuntime()
        try system.load(ReadmeExamples.buildEffect())
        #expect(system.emitters.count == 1)
    }
}
