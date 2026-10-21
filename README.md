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
  Particles can also start from a list of points or from the pixels of an image, and take their colors.
- **Collisions** with planes, spheres, boxes, and capsules. Colliders can move and spin, and fast particles do not pass
  through thin colliders. Particles can collide as small spheres, so large particles rest on surfaces. They can also
  collide with the scene's depth buffer, so they hit any geometry you draw, with no colliders.
- **Force fields:** wind, attractors, vortices, curl-noise turbulence, and paths that carry particles along a curve.
- **Flocking.** Particles steer by their neighbors, like birds, with a spatial grid built on the GPU each frame.
- **Sub-emitters and transitions.** Particles can make new particles when they are born, die, or collide. They can also
  turn into a different kind of particle after a time or on a hit.
- **Triggers and events.** Emit when you send an event, when particles hit a collider, or when something enters a
  volume. The GPU can also report each hit or death to your app, with its position and speed, for sounds and decals.
- **Your own Metal code.** Add Metal functions that run when particles are born, move, collide, or die. They can change
  each particle's color and size and keep up to four values of their own between frames.
- **Rendering:**
  - Textured sprites, animated sprite sheets, emoji, velocity stretching, and back-to-front sorting.
  - Small 3D meshes, such as coins or debris, that tumble as they fly.
  - Trails behind each particle, and ribbons that join an emitter's particles into one stream.
  - Lighting, and particles that light other particles and your scene.
  - Soft particles that fade into scene geometry.
- **Color:** gradients over life, by speed, by position, or a random mix of two. Particles can also take their color
  from an image as they move.
- **Scale.** Emitters can emit less when they are far away, and skip work when they are out of view.
- **Interactive.** Move colliders, force fields, and emitters every frame, or bind them to a point such as the mouse, a
  hand, or an object in your scene.
- **Debugging.** Show particles as wireframes or in false colors by emitter, age, speed, or overlap. See how many
  particles are born and die each second.
- **Effect files.** Save and load effects as packages: JSON with your Metal code, plus image and distance field files next to it. Sample presets to start from.
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
let built = ParticleSystem("Torch", cameraEye: [0, 1, 3], cameraTarget: [0, 0.6, 0]) {
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
```

### Modules

Each emitter is stored as module stacks per stage (`EmitterDescription.modules`): spawn, update, and render. Write them as a list, as above: each module goes to its stage, and required ones you leave out (shape, rate, lifetime, collision, color and size over life, sprite) get defaults. Modules can be turned off, reordered, added, and removed, and effect files save them.

For behavior the built-in modules lack, add a stitched user module. It is a `[[stitchable]]` Metal function, and the stage's user modules run in stack order:

```swift
var description = built.layers[0]
description.modules.update.append(ModuleSlot(.stitched(StitchedUpdateModule(module: StitchedModule(source: """
    [[stitchable]] constant float4 *swirl(thread ParticleState &p, float dt, float time, constant float4 *parameters) {
        p.velocity += cross(float3(0, 1, 0), p.position) * parameters[0].x * dt;
        return parameters + 1;
    }
    """, name: "swirl", parameters: [[2, 0, 0, 0]])))))
```

See [Documentation/Modules.md](Documentation/Modules.md) for the design.

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
```

For soft particles, which fade where they meet your geometry, render your scene's depth and pass it as
`render(projection:view:sceneDepth:)`.

### Demo app and tools

To try the presets and edit effects live, open the demo app in `Demos/MetalSprocketsParticlesDemo`. Pick a preset in the
toolbar, change any setting in the inspector, and save the result as an effect file to load in your own app.

There are also two command-line tools:

- `particles-render` renders presets and effect files to images and videos, with debug views if you want them.
- `particles-bench` measures frame times, for particle counts or for every sample preset against a frame budget. `--save-baseline` and `--compare` check for slowdowns (see `Benchmarks/`).

## 100% vibe coded

An AI agent wrote all of the code in this repository. A person gave the directions and did the reviews. For more information, read [Methodology](Documentation/Methodology.md).

## License

MIT. See [LICENSE](LICENSE).
