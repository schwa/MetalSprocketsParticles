# MetalSprocketsParticles

![Fireworks](Documentation/previews/fireworks.webp)

MetalSprocketsParticles is a particle system for [MetalSprockets](https://github.com/schwa/MetalSprockets). It runs the simulation and the rendering on the GPU. Use it to make fire, smoke, rain, sparks, and other effects.

It comes with sample presets. To see them, look at the [demos](Documentation/Demos.md).

## Features

- **Made for MetalSprockets.** Simulation and drawing are MetalSprockets elements. Put `simulate` and `render` in your
  own render graph, next to your own passes, with no extra Metal setup.
- **Fast.** The GPU simulates and draws everything, so effects scale to a million particles.
- **Many emitters in one system.** Each emitter has its own shape, sprite, curves, blend mode, and settings.
- **Emitter shapes:** point, sphere, box, plane, disc, cylinder, cone, torus, and meshes. Meshes can deform every frame.
- **Collisions** with planes, spheres, boxes, and capsules. Colliders can move and spin, and fast particles do not pass
  through thin colliders.
- **Force fields:** wind, attractors, vortices, and turbulence.
- **Sub-emitters and transitions.** Particles can make new particles when they are born, die, or collide. They can also
  turn into a different kind of particle after a time or on a hit.
- **Triggers.** Emit when you send an event, when particles hit a collider, or when something enters a volume.
- **Your own Metal code.** Add Metal functions that run when particles are born, move, collide, or die.
- **Rendering:** textured sprites, animated sprite sheets, emoji, velocity stretching, lighting, soft particles that
  fade into scene geometry, and back-to-front sorting.
- **Interactive.** Move colliders, force fields, and emitters every frame, or bind them to a point such as the mouse, a
  hand, or an object in your scene.
- **Effect files.** Save and load effects as JSON, including your Metal code. Sample presets to start from.
- **Video export.** Render any effect to a movie, offscreen.

## Usage

Add the package to your `Package.swift`. It has three libraries:

- `MetalSprocketsParticles`: the particle system.
- `MetalSprocketsParticlesUI`: `ParticleView`, a SwiftUI view that needs no other setup.
- `MetalSprocketsParticlesSamples`: sample presets, such as `.campfire`. Optional.

### Get an effect

An effect is a `ParticleSystem`: emitters, colliders, force fields, lights, and a camera. Load one from a file, use a
sample, or build one in code:

```swift
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples

// An effect file saved from the demo app or with ParticleSystem.write(to:).
let torch = try ParticleSystem(contentsOf: url)

// A sample preset.
let campfire = ParticleSystem.campfire

// An effect built in code.
var flame = ParticleEmitter()
flame.shape = .disc(radius: 0.3)
flame.birthRate = 400
flame.lifetime = 0.6...1.2
flame.velocity = [0, 1.5, 0]
flame.velocitySpread = 0.3
flame.blendMode = .additive
flame.sizeOverLife = .linear(from: 0.15, to: 0.4)
flame.colorOverLife = .linear(from: [1, 0.8, 0.3, 1], to: [1, 0.1, 0, 0])

let built = ParticleSystem("Torch", cameraEye: [0, 1, 3], cameraTarget: [0, 0.6, 0]) {
    EmitterDescription("Flame", settings: flame, sprite: .smoke)
    Collider.plane(normal: [0, 1, 0], distance: 0)
    ForceField.turbulence(strength: 1.5, scale: 1, speed: 0.5)
}
```

### Show it with ParticleView

`ParticleView` runs the simulation, draws the effect with its camera, and lets the mouse move pointer-bound items:

```swift
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesUI

struct TorchView: View {
    // Make the system once, not in `body`: a system built in `body` gets new emitter ids on every update, which
    // restarts the effect.
    @State private var torch = ParticleSystem.campfire

    var body: some View {
        ParticleView(torch)
    }
}
```

### Add it to a MetalSprockets scene

To mix particles with your own geometry, load the system into a `ParticleSystemRuntime`, which owns the GPU state.
In each frame, call `simulate` before your render pass, and `render` inside it after your opaque geometry:

```swift
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import SwiftUI

struct SceneView: View {
    let runtime: ParticleSystemRuntime
    @State private var camera = simd_float4x4(lookingFrom: [0, 2, 5], at: [0, 1, 0])

    init(system: ParticleSystem) throws {
        runtime = try ParticleSystemRuntime(emitters: [], capacity: 1)
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
```

For soft particles, which fade where they meet your geometry, render your scene's depth and pass it as
`render(projection:view:sceneDepth:)`.

### Demo app and tools

To try the presets and edit effects live, open the demo app in `Demos/MetalSprocketsParticlesDemo`. Pick a preset in the
toolbar, change any setting in the inspector, and save the result as an effect file to load in your own app.

There is also a command-line tool, `particles-render`, that renders presets and effect files to images and videos.

## 100% vibe coded

An AI agent wrote all of the code in this repository. A person gave the directions and did the reviews. For more information, read [Methodology](Documentation/Methodology.md).

## License

MIT. See [LICENSE](LICENSE).
