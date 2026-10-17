# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: Colliders are not drawn

+++
status: closed
priority: high
kind: none
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T13:54:28Z
closed: 2026-10-17T13:54:28Z
+++

Planes, spheres and boxes affect particles but are invisible. Particles are also not depth-tested against scene geometry.

- `2026-10-17T13:54:28Z`: Colliders drawn as flat-colored line wireframes (renderColliders).

---

## 2: No collision with arbitrary meshes

+++
status: new
priority: high
kind: none
created: 2026-10-17T13:27:25Z
+++

Particles only collide with analytic shapes (plane, sphere, AABB). Real scenes need collision with mesh geometry, e.g. via a baked SDF volume or the scene depth buffer.

---

## 3: No SDF or oriented-box colliders

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Boxes are axis-aligned only. There is no rotated box, capsule, or SDF collider.

---

## 4: Transparent particles are not sorted

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Alpha-blended particles draw in buffer order, which is wrong for non-additive blending.

---

## 5: No textured or flipbook sprites

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Particles are always a soft round dot. No texture, sprite sheet animation, or rotation.

---

## 6: Over-life properties are linear only

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Color and size only lerp between start and end. RealityKit/SceneKit-class systems need curves and gradients.

---

## 7: Only one continuous emitter shape

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Emission is a continuous spawn from a sphere. Missing: bursts, emission rate control, box/cone/disc/mesh-surface shapes, multiple emitters per system.

---

## 8: No force fields

+++
status: new
priority: medium
kind: none
created: 2026-10-17T13:27:25Z
+++

Only constant gravity and drag. Missing: vortex, attractors, curl noise turbulence, wind.

---

## 9: No sub-emitters

+++
status: new
priority: low
kind: none
created: 2026-10-17T13:27:25Z
+++

Particles cannot spawn other particles on death or collision (sparks, splashes).

---

## 10: No particle lighting or soft particles

+++
status: new
priority: low
kind: none
created: 2026-10-17T13:27:25Z
+++

Particles are unlit and clip hard against geometry.

---

## 11: No benchmark against RealityKit and SceneKit

+++
status: new
priority: low
kind: none
created: 2026-10-17T13:27:25Z
+++

The goal is to beat their particle systems, but there are no comparison scenes or performance numbers.

---

## 12: Particle simulation is not repeatable

+++
status: new
priority: high
kind: bug
created: 2026-10-17T13:35:53Z
+++

Initial spawn delays use Float.random on the CPU, and the GPU RNG is seeded from wall-clock time. The same emitter settings produce different results on each run, so output cannot be compared across runs or used in golden image tests. A seed should control all randomness.

---

## 13: No golden image tests

+++
status: new
priority: high
kind: task
depends: 12
created: 2026-10-17T13:35:53Z
updated: 2026-10-17T13:49:11Z
+++

Rendering is only checked by running the demo app and looking at it. There are no automated tests that render particles offscreen with OffscreenRenderer and compare against reference images with GoldenImage. Depends on repeatable simulation.

---

## 14: No headless CLI for rendering particles

+++
status: closed
priority: medium
kind: feature
created: 2026-10-17T13:35:53Z
updated: 2026-10-17T13:47:19Z
closed: 2026-10-17T13:47:19Z
+++

There is no way to render a particle scene to an image or video from the command line without launching the demo app.

- `2026-10-17T13:47:19Z`: Added particles-render executable (OffscreenRenderer + ArgumentParser).

---

## 15: Particle colors differ between the app and the CLI

+++
status: new
priority: low
kind: bug
created: 2026-10-17T13:47:19Z
+++

particles-render output is paler and more washed out than the demo app. OffscreenRenderer renders to bgra8Unorm_srgb, so the shader's colors are probably being treated as linear in one path and sRGB in the other.

---

## 16: Shaders are compiled from source at runtime

+++
status: new
priority: medium
kind: task
created: 2026-10-17T13:54:28Z
+++

Particles.metal ships as a copied resource and is compiled with ShaderLibrary(source:) on every launch. This costs startup time, hides shader compile errors until runtime, gives no Xcode Metal debugger support, and the Swift and Metal struct layouts are duplicated by hand. MetalSprocketsAddOns uses a separate shaders target built by MetalCompilerPlugin (~/Projects/Current/MetalCompilerPlugin), with shared C headers for the structs.

---
