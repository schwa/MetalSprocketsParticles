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
status: open
priority: medium
kind: feature
labels: effort:xl, area:collision
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:19:41Z
+++

Particles only collide with analytic shapes (plane, sphere, AABB). Real scenes need collision with mesh geometry, e.g. via a baked SDF volume or the scene depth buffer.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit has colliderNodes (collide with node geometry). RealityKit ParticleEmitterComponent has no collision API at all, so this is a clear place to beat it.
- `2026-10-17T14:11:14Z`: Related: #3 (SDF colliders could share the mesh SDF path).
- `2026-10-17T15:54:23Z`: SDF volume colliders were split out of #3 and belong here: a baked 3D distance texture is the same collision path mesh colliders need. Scope now: Collider case for a 3D SDF texture + bounds/transform, kernel sampling with gradient normals, and baking from a mesh.

---

## 3: No SDF or oriented-box colliders

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:collision
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T15:54:23Z
closed: 2026-10-17T15:54:23Z
+++

Boxes are axis-aligned only. There is no rotated box, capsule, or SDF collider.

- `2026-10-17T14:11:14Z`: Related: #2.
- `2026-10-17T15:54:23Z`: Added oriented boxes (Collider.box rotation:, defaults to identity) and capsules (Collider.capsule), with wireframes, tests, and a golden. SDF volume colliders moved to #2 since they share the baked-SDF path with mesh collision. Collider rotation is not turned into velocity: spinning boxes do not fling particles.

---

## 4: Transparent particles are not sorted

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:rendering
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:13:05Z
+++

Alpha-blended particles draw in buffer order, which is wrong for non-additive blending.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit sortingMode (none, projectedDepth, distance, oldestFirst, youngestFirst). RealityKit sortOrder (default increasingDepth).
- `2026-10-17T14:11:14Z`: Related: #19 (additive blending needs no sorting).

---

## 5: No textured or flipbook sprites

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:rendering
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T16:05:18Z
closed: 2026-10-17T16:05:18Z
+++

Particles are always a soft round dot. No texture, sprite sheet animation, or rotation.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit particleImage + imageSequence rows/columns/initialFrame/frameRate/animationMode. RealityKit image (premultiplied) + ImageSequence. SceneKit also supports a cube map image with fresnelExponent.
- `2026-10-17T16:05:18Z`: Added ParticleSystem.texture (premultiplied alpha; nil keeps the procedural dot) and ParticleEmitter.imageSequence (rows, columns, frameCount, frameRate/initialFrame with variation, repeat/clamp/autoReverse). Pixel-exact tests for each mode plus textured-spinning and sprite-sheet goldens.

---

## 6: Over-life properties are linear only

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T16:12:16Z
closed: 2026-10-17T16:12:16Z
+++

Color and size only lerp between start and end. RealityKit/SceneKit-class systems need curves and gradients.

- `2026-10-17T14:02:37Z`: Doc review: RealityKit has colorEvolutionPower, sizeMultiplierAtEndOfLifespan(+Power), opacityCurve presets, and a start/end or evolving ParticleColor. SceneKit uses propertyControllers with CAAnimation-driven curves for any property.
- `2026-10-17T16:12:16Z`: Added ParticleCurve (keyframed, linear between keys, .constant/.linear/.power helpers). ParticleEmitter has colorOverLife, sizeOverLife, opacityOverLife; colorStart/End and sizeStart/End now edit the first/last keyframes. Curves bake to 64-sample GPU tables read in the vertex shader. Existing goldens unchanged.

---

## 7: Only one continuous emitter shape

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:emission
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:13:05Z
+++

Particles spawn only inside a sphere. Missing: box, cone, disc, cylinder, torus, and mesh-surface/volume/vertex emission shapes, birth direction modes, and multiple emitters per system. Timing and bursts are tracked in #21.

- `2026-10-17T14:02:37Z`: Doc review: RealityKit EmitterShape (point, plane, box, sphere, cylinder, cone, torus) + emitterShapeSize, radialAmount, torusInnerRadius, BirthLocation (surface/volume/vertices), BirthDirection, burst()/burstCount. SceneKit emitterShape is any SCNGeometry with birthLocation (surface/volume/vertex) and birthDirection, emittingDirection, spreadingAngle.
- `2026-10-17T14:11:13Z`: Related: #21 (timing/bursts split out), #22 (emitter transform).

---

## 8: No force fields

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T16:19:12Z
closed: 2026-10-17T16:19:12Z
+++

Only constant gravity and drag. Missing: vortex, attractors, curl noise turbulence, wind.

- `2026-10-17T14:02:37Z`: Doc review: RealityKit has attractionCenter/Strength, vortexDirection/Strength, noiseStrength/Scale/AnimationSpeed. SceneKit uses scene SCNPhysicsField objects (isAffectedByPhysicsFields) plus particleMass and particleCharge for electric/magnetic fields.
- `2026-10-17T16:19:12Z`: Added ParticleEmitter.forceFields with wind, attractor (negative repels, optional radius), vortex (axis, optional radius), and curl-noise turbulence (scale, animated by the emitter clock so it stays deterministic). Tests per field and a force-fields golden.

---

## 9: No sub-emitters

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:emission
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:19:41Z
+++

Particles cannot spawn other particles on death or collision (sparks, splashes).

- `2026-10-17T14:02:37Z`: Doc review: SceneKit systemSpawnedOnCollision/OnDying/OnLiving. RealityKit spawnedEmitter with spawnOccasion (onBirth/onDeath/onUpdate), spawnVelocityFactor, spawnSpreadFactor, spawnInheritsParentColor.
- `2026-10-17T14:11:14Z`: Related: #23 (death on collision triggers onCollision sub-emitters).

---

## 10: No particle lighting or soft particles

+++
status: open
priority: low
kind: feature
labels: effort:l, area:rendering
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:13:05Z
+++

Particles are unlit and clip hard against geometry.

- `2026-10-17T14:02:37Z`: Doc review: both have isLightingEnabled. SceneKit also has isBlackPassEnabled. Neither documents soft particles, so soft particles would beat both.

---

## 11: No benchmark against RealityKit and SceneKit

+++
status: closed
priority: low
kind: task
labels: effort:l, area:tooling
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T14:19:41Z
closed: 2026-10-17T14:19:41Z
+++

The goal is to beat their particle systems, but there are no comparison scenes or performance numbers.

- `2026-10-17T14:19:41Z`: Won't do: not benchmarking against RealityKit/SceneKit.

---

## 12: Particle simulation is not repeatable

+++
status: closed
priority: high
kind: bug
labels: effort:s, area:simulation
created: 2026-10-17T13:35:53Z
updated: 2026-10-17T14:51:33Z
closed: 2026-10-17T14:51:33Z
+++

Initial spawn delays use Float.random on the CPU, and the GPU RNG is seeded from wall-clock time. The same emitter settings produce different results on each run, so output cannot be compared across runs or used in golden image tests. A seed should control all randomness.

- `2026-10-17T14:51:33Z`: Fixed: seed parameter drives a SplitMix64 CPU RNG for spawn delays and the GPU hash (id, seed, step counter). Time no longer feeds the RNG. Determinism tests added; particles-render --seed gives byte-identical PNGs.

---

## 13: No golden image tests

+++
status: closed
priority: high
kind: task
labels: effort:m, area:tooling
depends: 12
created: 2026-10-17T13:35:53Z
updated: 2026-10-17T14:59:11Z
closed: 2026-10-17T14:59:11Z
+++

Rendering is only checked by running the demo app and looking at it. There are no automated tests that render particles offscreen with OffscreenRenderer and compare against reference images with GoldenImage. Depends on repeatable simulation.

- `2026-10-17T14:11:14Z`: Related: #15 (color differences show up in golden images).
- `2026-10-17T14:59:11Z`: Added GoldenImageTests: three fountain renders (early, settled, no wireframes) at 640x360 compared against bundled goldens at 30 dB PSNR, plus a check that a different seed fails. Mismatched renders are written to /tmp/<name>.png for promotion.

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
status: open
priority: low
kind: bug
labels: effort:s, area:rendering
created: 2026-10-17T13:47:19Z
updated: 2026-10-17T14:13:05Z
+++

particles-render output is paler and more washed out than the demo app. OffscreenRenderer renders to bgra8Unorm_srgb, so the shader's colors are probably being treated as linear in one path and sRGB in the other.

---

## 16: Shaders are compiled from source at runtime

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:tooling
created: 2026-10-17T13:54:28Z
updated: 2026-10-17T15:12:23Z
closed: 2026-10-17T15:12:23Z
+++

Particles.metal ships as a copied resource and is compiled with ShaderLibrary(source:) on every launch. This costs startup time, hides shader compile errors until runtime, gives no Xcode Metal debugger support, and the Swift and Metal struct layouts are duplicated by hand. MetalSprocketsAddOns uses a separate shaders target built by MetalCompilerPlugin (~/Projects/Current/MetalCompilerPlugin), with shared C headers for the structs.

- `2026-10-17T15:12:23Z`: Moved shaders to a MetalSprocketsParticlesShaders target compiled by MetalCompilerPlugin. Shared structs live in include/ParticleTypes.h and are imported into Swift; the Swift copies are gone. Library loads with ShaderLibrary(bundle: .metalSprocketsParticlesShaders()).

---

## 17: Particles have no rotation or spin

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:rendering
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T15:33:23Z
closed: 2026-10-17T15:33:23Z
+++

Billboards are always axis-aligned to the camera. SCNParticleSystem has particleAngle/particleAngularVelocity (+variation); RealityKit ParticleEmitter has angle/angularSpeed (+variation).

- `2026-10-17T15:33:23Z`: Added per-particle angle and angular velocity (angle/angleVariation/angularSpeed/angularSpeedVariation on ParticleEmitter). The vertex shader rotates the billboard quad, not the UVs. No visible change with the current round sprite; becomes visible with textures (#5).

---

## 18: Only camera-facing billboards; no velocity stretch

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:rendering
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T16:26:04Z
closed: 2026-10-17T16:26:04Z
+++

Particles always face the camera. SceneKit orientationMode and RealityKit billboardMode offer Y-aligned, axis-locked, and free orientation. Both have stretchFactor to stretch particles along velocity (sparks, rain).

- `2026-10-17T16:26:04Z`: Added ParticleEmitter.orientation: billboard (default), yAligned, velocityAligned(stretch:), fixed(normal:). Stretch scales the long axis by 1 + stretch × speed and lives on velocityAligned. Pixel-extent tests per mode and a velocity-stretched-sparks golden.

---

## 19: Blend mode is fixed

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:rendering
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T15:40:46Z
closed: 2026-10-17T15:40:46Z
+++

Particles always use premultiplied alpha blending. SceneKit blendMode and RealityKit blendMode offer additive, alpha, and others. Additive is needed for fire, sparks, and glow.

- `2026-10-17T14:11:14Z`: Related: #4.
- `2026-10-17T15:40:46Z`: Added ParticleEmitter.blendMode: alpha (default), additive, screen, opaque (alpha-tested). Shared ParticleBlendMode enum in the shader header. Goldens per mode plus a test that changing mode on a live renderer picks a new pipeline.

---

## 20: Per-particle properties are not randomized at birth

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:emission
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T16:38:00Z
closed: 2026-10-17T16:38:00Z
+++

Only position, velocity, and lifetime vary per particle. Both SceneKit and RealityKit pair almost every property with a *Variation range: size, color, angle, angular speed, mass, bounce, friction, birth rate, image sequence frame and rate.

- `2026-10-17T16:38:00Z`: Added sizeVariation, speedVariation, colorVariation (HSBA offsets on the curve color), restitutionVariation, frictionVariation, and birthRateVariation (per emission cycle, seeded). Per-particle bounce/friction are offsets so live emitter edits still apply. Mass skipped: no force uses it yet. Existing goldens unchanged.

---

## 21: No emission timing control

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:emission
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T15:27:32Z
closed: 2026-10-17T15:27:32Z
+++

The emitter always emits continuously at full capacity. Missing: birth rate independent of capacity, emission duration and idle periods, looping, warmup (pre-simulate before first render), play/pause/stop/restart, isEmitting toggle, and a simulation speed factor. Both SceneKit and RealityKit have these.

- `2026-10-17T14:11:13Z`: Related: #7 (emitter shapes).
- `2026-10-17T15:27:32Z`: Added birthRate (independent of capacity), emissionDuration/idleDuration/loops, warmupDuration, burst(), SimulationState play/pause/stop, restart(), isEmitting, and speedFactor. Particles spawn into a ring buffer with randomness keyed by spawn serial, so results stay deterministic.

---

## 22: No emitter transform or simulation space

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:emission
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T14:13:05Z
+++

The emitter has a position but no rotation, scale, or parent transform, and there is no choice of local vs world simulation space. SceneKit has isLocal; RealityKit has particlesInheritTransform and fieldSimulationSpace. Moving emitters (trails, rockets) need this.

---

## 23: Particles cannot die on collision

+++
status: open
priority: low
kind: feature
labels: effort:s, area:collision
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T14:13:05Z
+++

Colliding particles always bounce. SceneKit has particleDiesOnCollision and collision events. Needed for rain, sparks hitting walls, and as a trigger for sub-emitters (#9).

- `2026-10-17T14:11:14Z`: Related: #9.

---

## 24: No way to inject custom per-particle behavior

+++
status: open
priority: medium
kind: feature
labels: effort:xl, area:simulation
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T14:13:05Z
+++

SceneKit lets callers attach event handlers (birth, death, collision) and per-frame modifier blocks at several simulation stages. A GPU system needs an equivalent, e.g. user-supplied Metal functions for spawn, update, or render, so effects can go beyond the built-in parameters.

---

## 25: No presets or saved effect files

+++
status: open
priority: low
kind: feature
labels: effort:m, area:tooling
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T14:13:05Z
+++

RealityKit ships ParticleEmitterComponent.Presets (fireworks, impact, magic, rain, snow, sparks). SceneKit loads .scnp files authored in Xcode's particle editor. We have one hard-coded fountain and no serializable effect format.

---

## 26: No UI to adjust emitter settings

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:tooling
created: 2026-10-17T14:15:58Z
+++

Changing any emitter setting means editing code and rebuilding. The demo app needs a simple inspector (sliders, color pickers, collider list) for live tweaking. Keep it in the demo app for now; it may later move to its own reusable target. Related: #25 (presets/effect files).

---

## 27: Demo colliders are static

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:collision
created: 2026-10-17T14:17:50Z
updated: 2026-10-17T15:48:48Z
closed: 2026-10-17T15:48:48Z
+++

The demo's sphere and boxes never move, so it does not show particles reacting to moving geometry. Animate the colliders over time in the demo view. Moving colliders should also transfer their velocity to particles they hit; currently collision response assumes a stationary collider.

- `2026-10-17T15:48:48Z`: Demo colliders now animate (ParticleEmitter.fountainColliders(time:)). Collider velocity is derived from frame-to-frame motion and collision response is computed relative to the collider, so moving colliders push and carry particles. particles-render gained --animate-colliders.

---

## 28: Spike: evaluate the AddOns point cloud renderer for very high particle counts

+++
status: new
priority: low
kind: task
labels: effort:m, area:rendering
created: 2026-10-17T15:00:32Z
+++

MetalSprocketsAddOns has `PointCloudRasterizePass` / `PointCloudResolvePipeline`, a compute point rasterizer (Schütz et al. 2021). Find out if it is useful as an optional render mode for many small opaque particles (sparks, dust, rain).

Possible gains:
- No quad overdraw at high particle counts.
- No sort needed (#4), because points are opaque.
- A `describe` visible function can read `Particle` directly from the simulation buffer.
- World-unit sizes match the current sizing.

Known problems:
- No alpha. The result is the nearest point or an average. The soft falloff, premultiplied alpha, alpha fade-out and additive glow are lost.
- It is fast only for points of a few pixels. Large points use a per-thread loop. Default sizes are probably 10–40 px.
- Needs Apple GPU family 8+, a depth attachment, an extra compute pass and a per-pixel buffer (8 or 28 bytes per pixel, per frame in flight).
- Adds a dependency on MetalSprocketsAddOns.

Spike tasks:
1. Profile the current billboard renderer at high counts (1M+). Is it slow?
2. If it is, prototype the point cloud path behind a render-mode switch. Use `describe` and send dead particles behind the camera.
3. Compare frame time and visuals at the same counts and sizes.

Outcome: a keep/drop decision with numbers.

---

## 29: Measure and optimise particle system performance

+++
status: new
priority: medium
kind: task
labels: effort:l, area:simulation, area:rendering
created: 2026-10-17T15:01:18Z
+++

Goal: the particle system (simulation + rendering) should be a very small part of a typical frame for a reasonable number of particles.

Steps:
1. Measure.
   - Define "reasonable" counts (for example 10K, 100K, 1M) and target budgets (for example under 0.5 ms GPU at 100K on a base M-series Mac).
   - Add a repeatable benchmark: GPU time per pass (simulate, collide, render), split from CPU encode time.
   - Record a baseline. Capture a GPU trace for each count.
2. Optimise. Fix the largest costs first. Candidates (not yet confirmed):
   - Simulation kernel: memory layout and size of `Particle`, threadgroup size, collider loop cost.
   - Rendering: overdraw and fill rate with large or overlapping billboards; instance count is `capacity` even when most particles are dead.
   - CPU: per-frame allocations and uniform setup; runtime shader compilation (#16) at startup.
3. Improve.
   - Keep the benchmark as a regression check (in CI or a `just` recipe).
   - Write the budgets and the results in the README.

Related: #4 (sorting adds cost), #28 (point cloud renderer spike), #16 (runtime shader compile).

---
