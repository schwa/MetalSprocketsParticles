# MetalSprocketsParticles

MetalSprocketsParticles is a particle system for [MetalSprockets](https://github.com/schwa/MetalSprockets). It runs the simulation and the rendering on the GPU. Use it to make fire, smoke, rain, sparks, and other effects.

The package has 29 built-in presets. To see each preset, look at the [demo videos](Documentation/Demos/README.md).

## Usage

Add the package to your `Package.swift`. Then make a particle system from a preset:

```swift
import MetalSprocketsParticles

let system = try ParticleSystem(emitters: [], capacity: 1)
try system.load(.campfire)
```

In each frame, call `system.simulate(deltaTime:)` before your render pass. Then call `system.render(projection:view:)` in the render pass.

To render a preset to an image or a video from the command line, use `particles-render`:

```sh
swift run -c release particles-render --list-presets
swift run -c release particles-render --preset campfire -o campfire.png
swift run -c release particles-render --preset campfire --video campfire.mov
```

The demo app is in `Demos/MetalSprocketsParticlesDemo`.

## 100% vibe coded

An AI agent wrote all of the code in this repository. A person gave the directions and did the reviews. For more information, read [METHODOLOGY.md](Documentation/METHODOLOGY.md).

## License

MIT. See [LICENSE](LICENSE).
