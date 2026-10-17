# MetalSprocketsParticles

A GPU particle system for [MetalSprockets](https://github.com/schwa/MetalSprockets). Simulation and rendering run on the GPU. A system holds any number of emitters, which share colliders and force fields.

## Run

```sh
xcb run MetalSprocketsParticles/particles-render -- --list-presets
xcb run MetalSprocketsParticles/particles-render -- --preset campfire -o campfire.png
xcb run MetalSprocketsParticles/particles-bench -c release
xcb test MetalSprocketsParticles/MetalSprocketsParticles
```

The demo app is in `Demos/MetalSprocketsParticlesDemo`.

## Performance

Budget: at 100,000 live particles, simulation plus rendering should stay under 0.5 ms of GPU time per frame on a base M-series Mac. The results below are from an M5 Max (0.23 ms); the budget has not been measured on a base chip yet.

`particles-bench` measures the simulate and render passes as separate submissions. Each scenario runs 150 frames so the ring fills, then reports the median of 60 frames. The scene is a 1920×1080 target, particles a few pixels wide, two colliders, and one turbulence field.

Results on an Apple M5 Max (40-core GPU), release build:

| Scenario | Simulate GPU | Render GPU | CPU per frame |
|---|---|---|---|
| 10K | 0.015 ms | 0.030 ms | 0.41 ms |
| 100K | 0.027 ms | 0.203 ms | 0.44 ms |
| 1M | 0.232 ms | 2.263 ms | 0.53 ms |
| 1M capacity, 100K alive | 0.029 ms | 0.206 ms | 0.45 ms |
| 1M, no turbulence | 0.217 ms | 2.203 ms | 0.52 ms |
| 1M, sub-pixel particles | 0.240 ms | 0.547 ms | 0.52 ms |
| 1M, particles 4× wider | 0.231 ms | 7.341 ms | 0.55 ms |

CPU time is wall time minus GPU time for the two submissions. It is mostly fixed submission overhead, not per-particle work.

Before optimization, 1M particles took 2.0 ms to simulate (1.8 ms of it turbulence), and a 1M-capacity system with 100K alive cost 0.46 ms to simulate and 0.77 ms to render.

### What changed

- **Turbulence**: curl noise uses gradient noise with analytic derivatives, so it takes 3 noise samples per particle instead of 18. Simulation at 1M dropped from 2.0 ms to 0.23 ms.
- **Live window**: each emitter simulates and draws only the ring slots that can hold live particles. Unused capacity costs nothing, so a 1M-capacity system with 100K alive costs the same as a 100K system.

### Where the time goes now

Rendering is bound by fill rate, that is, how many pixels the particles cover. Sub-pixel particles render 1M in 0.55 ms; that is the vertex cost. Particles 4× wider take 7.3 ms. Discarding the empty corners of each quad did not help on this GPU.

Possible next steps, not done yet:

- Render particles to a lower-resolution target and composite it.
- Move per-particle render work (curve lookups, sprite frame, color variation) from the vertex shader to the simulation pass. Today all four vertices of a quad repeat it.
- The compute point rasterizer spike (#28), for many small opaque particles.
