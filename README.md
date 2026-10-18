# MetalSprocketsParticles

MetalSprocketsParticles is a particle system for [MetalSprockets](https://github.com/schwa/MetalSprockets). It runs the simulation and the rendering on the GPU. Use it to make fire, smoke, rain, sparks, and other effects.

The package has 31 built-in presets. To see each preset, look at the [demo videos](Documentation/Demos/README.md).

## Features

- **Made for MetalSprockets.** Simulation and drawing are MetalSprockets elements. Put `simulate` and `render` in your
  own render graph, next to your own passes, with no extra Metal setup.
- **Fast.** The GPU simulates and draws everything. One million particles simulate in about 0.25 ms on an M5 Max.
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
- **Effect files.** Save and load effects as JSON, including your Metal code. 31 built-in presets to start from.
- **Video export.** Render any effect to a movie, offscreen.

## Usage

Add the package to your `Package.swift`. Then make a particle system from a preset:

```swift
import MetalSprocketsParticles

let system = try ParticleSystem(emitters: [], capacity: 1)
try system.load(.campfire)
```

In each frame, call `system.simulate(deltaTime:)` before your render pass. Then call `system.render(projection:view:)` in the render pass.

To try the presets and edit effects live, open the demo app in `Demos/MetalSprocketsParticlesDemo`. Pick a preset in the
toolbar, change any setting in the inspector, and save the result as an effect file to load in your own app.

There is also a command-line tool, `particles-render`, that renders presets and effect files to images and videos.

## 100% vibe coded

An AI agent wrote all of the code in this repository. A person gave the directions and did the reviews. For more information, read [METHODOLOGY.md](Documentation/METHODOLOGY.md).

## License

MIT. See [LICENSE](LICENSE).
