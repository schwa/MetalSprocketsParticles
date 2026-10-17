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
- `2026-10-17T19:34:40Z`: Main consumer: MetalSprocketsSceneGraph integration, where colliders come from scene-node geometry at runtime. Mesh/SDF colliders need to accept that geometry (and its transforms) per frame.
- `2026-10-17T21:05:19Z`: Mesh input should come from SwiftMesh (github.com/schwa/SwiftMesh), the mesh type used across the MetalSprockets ecosystem (MetalSprocketsAddOns depends on it). Mesh/SDF colliders should accept a SwiftMesh mesh plus transform, not raw arrays.
- `2026-10-17T21:05:19Z`: Related: #38 (SwiftMesh input for EmitterMesh); share the conversion.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:rendering
depends: 33
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T21:37:21Z
closed: 2026-10-17T21:37:21Z
+++

Alpha-blended particles draw in buffer order, which is wrong for non-additive blending.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit sortingMode (none, projectedDepth, distance, oldestFirst, youngestFirst). RealityKit sortOrder (default increasingDepth).
- `2026-10-17T14:11:14Z`: Related: #19 (additive blending needs no sorting).
- `2026-10-17T19:36:36Z`: Depends on #33: sorting must work across emitters sharing one buffer; build it once after that lands.
- `2026-10-17T20:30:12Z`: See ~/Projects/Current/MetalSprockets/MetalSprocketsGaussianSplats/ for good GPU sorting algorithms.
- `2026-10-17T21:37:21Z`: Added ParticleEmitter.sortMode (.none default, .backToFront). Sorting is a GPU 8-bit LSD radix sort on 16-bit view-depth keys over each emitter's live window, ported from MetalSprocketsGaussianSplats; the vertex shader reads through the sorted records. Pass view: to simulate. Across emitters: sorted emitters draw after unsorted ones, farthest emitter first; particles of different emitters are not interleaved (separate draws per blend mode/texture). Cost: +0.08 ms GPU at 100K, +0.76 ms at 1M. Enabled for Smoke, Campfire smoke, Snow, Waterfall mist, Confetti.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:emission
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T20:16:20Z
closed: 2026-10-17T20:16:20Z
+++

Particles spawn only inside a sphere. Missing: box, cone, disc, cylinder, torus, and mesh-surface/volume/vertex emission shapes, and birth direction modes. Timing and bursts are tracked in #21; multiple emitters per system moved to #33.

- `2026-10-17T14:02:37Z`: Doc review: RealityKit EmitterShape (point, plane, box, sphere, cylinder, cone, torus) + emitterShapeSize, radialAmount, torusInnerRadius, BirthLocation (surface/volume/vertices), BirthDirection, burst()/burstCount. SceneKit emitterShape is any SCNGeometry with birthLocation (surface/volume/vertex) and birthDirection, emittingDirection, spreadingAngle.
- `2026-10-17T14:11:13Z`: Related: #21 (timing/bursts split out), #22 (emitter transform).
- `2026-10-17T20:16:20Z`: Added EmitterShape (point, sphere, box, plane, disc, cylinder, cone, torus, mesh), ParticleBirthLocation (volume, surface, vertices), ParticleBirthDirection (velocity, normal), and sweepAngle. EmitterMesh samples triangles by area. Mesh volume emission falls back to the surface (no inside test). radius stays as a sphere accessor.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:emission
depends: 33
created: 2026-10-17T13:27:25Z
updated: 2026-10-17T21:55:52Z
closed: 2026-10-17T21:55:52Z
+++

Particles cannot spawn other particles on death or collision (sparks, splashes).

- `2026-10-17T14:02:37Z`: Doc review: SceneKit systemSpawnedOnCollision/OnDying/OnLiving. RealityKit spawnedEmitter with spawnOccasion (onBirth/onDeath/onUpdate), spawnVelocityFactor, spawnSpreadFactor, spawnInheritsParentColor.
- `2026-10-17T14:11:14Z`: Related: #23 (death on collision triggers onCollision sub-emitters).
- `2026-10-17T17:16:57Z`: Related: #34 (event triggers). Sub-emitters are the particle-driven case of triggers; design them together.
- `2026-10-17T19:36:36Z`: Depends on #33: sub-emitters are likely extra emitters in the same system, triggered by particle events. Design with #34.
- `2026-10-17T21:55:52Z`: Added ParticleEmitter.subEmitters ([SubEmitter]: occasion onBirth/onDeath/onCollision/whileAlive(interval:), countPerEvent, velocityFactor, child settings). Each parent particle owns countPerEvent child slots; the parent kernel writes children directly on the event, so it is deterministic and needs no atomics or CPU counts. Fireworks preset now launches rockets with trails that burst on death. Not done: inheriting parent color (color comes from curves at render time), nested sub-emitters, inspector editing (noted on #39).

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
status: closed
priority: high
kind: bug
labels: effort:s, area:rendering
created: 2026-10-17T13:47:19Z
updated: 2026-10-17T19:48:07Z
closed: 2026-10-17T19:48:07Z
+++

particles-render output is paler and more washed out than the demo app. OffscreenRenderer renders to bgra8Unorm_srgb, so the shader's colors are probably being treated as linear in one path and sRGB in the other.

- `2026-10-17T17:12:37Z`: Raised to high: golden images and pixel tests render through OffscreenRenderer's sRGB target, so if that path's color handling differs from the app, tests validate the wrong output.
- `2026-10-17T19:48:07Z`: Cause: the demo's RenderView used MTKView's default .bgra8Unorm while OffscreenRenderer uses .bgra8Unorm_srgb. Particle colors are linear, so the sRGB path is correct. Added ParticleSystem.colorPixelFormat (.bgra8Unorm_srgb) and the demo now renders to it. Regression test compares the app's format with OffscreenRenderer's.

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
status: closed
priority: medium
kind: feature
labels: effort:m, area:emission
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T16:51:12Z
closed: 2026-10-17T16:51:12Z
+++

The emitter has a position but no rotation, scale, or parent transform, and there is no choice of local vs world simulation space. SceneKit has isLocal; RealityKit has particlesInheritTransform and fieldSimulationSpace. Moving emitters (trails, rockets) need this.

- `2026-10-17T16:51:12Z`: Added ParticleSystem.transform and simulationSpace (.world / .local), ParticleEmitter.inheritVelocity, and spawn interpolation along the emitter's path so fast emitters leave continuous trails. In local space, gravity/colliders/fields are emitter-local and wireframes draw through the transform. Rotation is not turned into inherited velocity.

---

## 23: Particles cannot die on collision

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:collision
created: 2026-10-17T14:01:52Z
updated: 2026-10-17T20:03:20Z
closed: 2026-10-17T20:03:20Z
+++

Colliding particles always bounce. SceneKit has particleDiesOnCollision and collision events. Needed for rain, sparks hitting walls, and as a trigger for sub-emitters (#9).

- `2026-10-17T14:11:14Z`: Related: #9.
- `2026-10-17T20:03:20Z`: Added ParticleEmitter.diesOnCollision: on any collider contact the particle's age jumps to its lifetime. Collision events (SceneKit-style) are left to #34 triggers; spawning on collision to #9.

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

- `2026-10-17T17:18:07Z`: Related: #30 now loads presets through a picker; saved effect files from this issue should appear in the same picker.

---

## 26: No UI to adjust emitter settings

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:tooling
created: 2026-10-17T14:15:58Z
updated: 2026-10-17T17:01:28Z
closed: 2026-10-17T17:01:28Z
+++

Changing any emitter setting means editing code and rebuilding. The demo app needs a simple inspector (sliders, color pickers, collider list) for live tweaking. Keep it in the demo app for now; it may later move to its own reusable target. Related: #25 (presets/effect files).

- `2026-10-17T17:01:28Z`: Added an inspector to the demo app (EmitterInspectorView) with playback, emission, motion, appearance, and collision sections, backed by an @Observable ParticlesDemoModel. Bindings use key-path projections through writable computed properties, not closure Binding adapters. Kept in the demo package for now. Layout not visually checked (no app launch); iOS simulator build blocked by MetalSprockets needing Metal 4.

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
status: open
priority: low
kind: task
labels: effort:m, area:rendering
created: 2026-10-17T15:00:32Z
updated: 2026-10-17T17:10:11Z
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

- `2026-10-17T17:10:11Z`: Triage note: depends on #29's measurements (step 1 of the spike is the same profiling). Opaque points would pair with blend mode .opaque (#19).

---

## 29: Measure and optimise particle system performance

+++
status: closed
priority: medium
kind: task
labels: effort:l, area:simulation, area:rendering
created: 2026-10-17T15:01:18Z
updated: 2026-10-17T20:59:15Z
closed: 2026-10-17T20:59:15Z
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

- `2026-10-17T17:10:11Z`: Triage note: #16 (runtime shader compile) is fixed; shaders are now precompiled by MetalCompilerPlugin, so drop that CPU candidate. Instancing at capacity still applies: the ring buffer (#21) draws capacity instances even when most are dead.
- `2026-10-17T20:59:15Z`: Added particles-bench (simulate and render GPU time per pass, CPU per frame, 10K/100K/1M and edge scenarios) and README budgets/results. Fixes: analytic-derivative curl noise (1M simulate 2.0 -> 0.23 ms) and a per-emitter live window so unused capacity is not simulated or drawn (1M cap/100K alive render 0.77 -> 0.21 ms). Rendering is now fill-bound; discarding quad corners did not help and was reverted. Not measured on a base M chip. No just recipe: the justfile skill requires an explicit request.

---

## 30: Demo has no emitter presets, so most features stay hidden

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:tooling
created: 2026-10-17T17:08:40Z
updated: 2026-10-17T20:42:49Z
closed: 2026-10-17T20:42:49Z
+++

The demo app and particles-render only ever use the fountain emitter. Textures and sprite sheets (#5), rotation (#17), rotated boxes and capsules (#3), moving emitters, local space and inherited velocity (#22), velocity stretch (#18), and most force fields (#8) never appear outside golden tests.

Add emitter presets, not separate scenes: a preset is a saved emitter configuration (ParticleEmitter plus the system-level settings it needs, such as texture, simulation space, and emitter motion). A picker in the demo inspector loads a preset into the live system, and the inspector then edits it. particles-render gets a matching --preset option.

Presets come from two sources:
- Hard-coded in Swift now. Make them good-looking: for example fireworks, sparks, smoke, snow, rain, magic trail, comet.
- Saved effect files later, via #25, listed in the same picker.

Related: #25 (saved effect files), #31 (inspector coverage), #32 (emitter DSL would make Swift presets short).

- `2026-10-17T17:08:40Z`: Related: #31 (inspector coverage); scene presets should load into the same inspector.
- `2026-10-17T18:15:36Z`: Decision: colliders are part of a preset. Loading a preset replaces the colliders along with the emitter settings. Keep this when #33 moves colliders into a shared per-system world: a preset still carries its colliders.
- `2026-10-17T19:34:40Z`: Clarification: preset colliders are a default, not the only source. Apps supply colliders at runtime too (today via simulate(deltaTime:colliders:)); runtime colliders replace or add to the preset's.
- `2026-10-17T20:42:49Z`: Added ParticlePreset (layers with settings, sprite, motion, simulation space, capacity; colliders with optional animation; force fields; suggested camera), ParticleSystem.load(_:), and 12 presets: Fountain, Campfire, Fireworks, Sparks, Smoke, Snow, Rain, Magic Trail, Comet, Galaxy, Waterfall, Confetti. Each was tuned against particles-render output and has a golden. Demo inspector has a preset picker (moves the camera to the preset's view) and Revert Changes. particles-render has --preset and --list-presets. Galaxy forms rings rather than true spiral arms; arms need emitters that rotate over time.

---

## 31: Inspector does not expose all emitter features

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:tooling
created: 2026-10-17T17:08:40Z
updated: 2026-10-17T20:25:10Z
closed: 2026-10-17T20:25:10Z
+++

The demo inspector (#26) covers only part of ParticleEmitter and ParticleSystem. Missing controls include: warmup; multi-stop color/size curves and the opacity curve; wind and attractor force fields and turbulence/vortex parameters beyond strength; fixed-plane orientation; saturation, brightness, alpha, friction, angle, and spin variation; angle and spin; texture choice and image sequence settings; emitter transform motion, simulation space, and inherit velocity; collider editing. Every feature that makes sense to tweak live should have a control.

- `2026-10-17T17:08:40Z`: Related: #30 (preset scenes).
- `2026-10-17T20:25:10Z`: Inspector now covers: multiple emitters (select, add, duplicate, remove, rename, emitting, burst); shape, birth location/direction, sweep, position; emission incl. warmup; velocity/gravity vectors, drag, emitter motion, simulation space, inherit velocity; texture choice (generated sprites) and sprite sheet settings; blend, orientation incl. flat, stretch; multi-stop color/opacity/size curves; angle and spin; all variations; bounce, friction, die on collision; editable colliders and force fields of every kind. All bindings are key-path projections through writable computed properties. Not visually checked (no app launch). Curve stops are identified by index because library keyframes have no ids.

---

## 32: Emitters can only be built by mutating a ParticleEmitter struct

+++
status: open
priority: low
kind: feature
labels: effort:l, area:tooling
created: 2026-10-17T17:10:23Z
+++

Defining an effect means creating a ParticleEmitter and setting many properties one by one, then wiring texture, transform, and colliders on ParticleSystem separately. There is no concise, composable way to describe an effect or reuse parts of one. Stretch goal: a small Swift DSL, possibly result-builder or SwiftUI-modifier style (e.g. Emitter { ... }.birthRate(5_000).colorOverLife(...).force(.turbulence(...))), so effects compose like SwiftUI views and presets (#30, #25) become short declarations. Related: #30 (preset scenes), #25 (presets/effect files).

---

## 33: A particle system has only one emitter

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:emission
created: 2026-10-17T17:16:57Z
updated: 2026-10-17T19:59:49Z
closed: 2026-10-17T19:59:49Z
+++

Each ParticleSystem owns exactly one ParticleEmitter. Effects that combine parts (fire + smoke + embers, a fountain with spray and mist) need several systems, each with its own buffer, compute pass, draw call, and copy of the colliders and force fields. Overlapping systems draw in code order, so blending between them is wrong. A system should host many emitters that share one particle buffer, one simulation pass, and one set of scene colliders and force fields, with per-emitter settings (shape, rate, curves, texture, blend mode) and per-emitter transforms. Split out of #7, which now covers emitter shapes only. Related: #4 (sorting across emitters), #9 (sub-emitters), #29 (performance).

- `2026-10-17T18:15:36Z`: Constraint from #30: presets carry colliders. A shared collider world must still be loadable from (and saved to) a preset.
- `2026-10-17T19:34:40Z`: Colliders have two sources: presets (authoring, demo) and the app at runtime. Planned runtime source is MetalSprocketsSceneGraph scene-node geometry. The shared collider world should be fed per frame from the app, merged with any preset colliders.
- `2026-10-17T19:59:49Z`: ParticleSystem now hosts any number of emitters (ParticleSystem.Emitter: settings, texture, transform, simulation space, burst, restart) in one shared buffer, one compute pass, and per-emitter draws. Colliders and force fields moved to the system as a shared world-space world, fed per frame by the app (simulate(colliders:)). Local-space emitters collide with world colliders. Single-emitter API kept as conveniences; emitter 0 reproduces old results exactly (all goldens unchanged). Preset collider loading is left to #30.

---

## 34: Emission cannot be triggered by events

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:emission
depends: 33
created: 2026-10-17T17:16:57Z
updated: 2026-10-17T19:36:36Z
+++

Emitters only emit on their own clock (birth rate, duration, idle) or when code calls burst(). There is no way to make emission happen in response to something: a trigger volume that particles or scene objects enter, a collider being hit, a timer or sequence, or a named event from the app. Effects like sparks where a blade touches a wall, a splash when something enters water, or a firework that bursts at the top of its arc need triggers that start, stop, or burst an emitter, ideally evaluated on the GPU for particle-driven events. Related: #33 (multiple emitters), #9 (sub-emitters: spawn on particle birth/death/collision), #23 (die on collision).

- `2026-10-17T19:36:36Z`: Depends on #33. Design with #9.
- `2026-10-17T21:55:52Z`: Design note from #9: sub-emitters use fixed child slots per parent particle written directly by the parent kernel (no atomics, deterministic). Particle-driven triggers can reuse the event detection in updateParticles (birth/death/collision/whileAlive); app and volume triggers are the new part.

---

## 35: More emitter shapes: volume, plane, circle, etc.

+++
status: closed
priority: medium
kind: feature
created: 2026-10-17T20:11:25Z
updated: 2026-10-17T21:06:50Z
closed: 2026-10-17T21:06:50Z
+++

Add emitter types that spawn particles from shapes: volumes (box, sphere), planes, circles/rings, and similar.

- `2026-10-17T21:06:50Z`: Duplicate of #7 (done): box and sphere volumes, plane, disc (fill or rim), cylinder, cone, torus, and mesh shapes, with volume/surface birth location and sweep angle.

---

## 36: Doctor Strange portal example

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:tooling
created: 2026-10-17T20:11:25Z
updated: 2026-10-17T21:24:57Z
closed: 2026-10-17T21:24:57Z
+++

Add an example of a Doctor Strange-style portal: sparks thrown off a spinning ring, like a Catherine wheel.

- `2026-10-17T21:06:50Z`: Triage: fits as a preset (#30). Missing pieces: emitter motion that spins over time (EmitterMotion only has a fixed yaw; Galaxy needs the same for real spiral arms), and sparks thrown tangentially; today the closest is a rotating torus/disc rim with inheritVelocity. Related: #30.
- `2026-10-17T21:24:57Z`: Added the Portal preset: an upright spinning ring of fire, sparks thrown tangentially off the rim that fall and bounce on the ground, and a counter-rotating inner shimmer. New: ParticleBirthDirection.tangent and EmitterMotion pitch/spin (both in the inspector). Tried spinning the Galaxy arm emitters for spiral arms; long-lived stars still smear into rings, so Galaxy is unchanged.

---

## 37: Random draw order depends on the Metal compiler

+++
status: closed
priority: high
kind: bug
labels: effort:xs, area:simulation
created: 2026-10-17T20:16:20Z
closed: 2026-10-17T20:16:20Z
+++

Shader code built vectors from several random draws in one expression, for example float3(next(), next(), next()). C++ leaves argument evaluation order unspecified, so the compiler may draw the values in a different order whenever surrounding code changes. Within one build results were deterministic, but an unrelated shader edit could reshuffle every particle and break all golden images. Found while adding emitter shapes (#7): the same kernel drew the position and the velocity in different orders.

- `2026-10-17T20:16:20Z`: Fixed in the #7 commit: Random gains next2/next3/next4 with explicit sequential draws, used everywhere. Goldens regenerated once; they now no longer depend on compiler choices.

---

## 38: EmitterMesh cannot be built from a SwiftMesh mesh

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:emission
created: 2026-10-17T21:05:19Z
updated: 2026-10-17T21:14:02Z
closed: 2026-10-17T21:14:02Z
+++

EmitterMesh (#7) only takes raw positions and triangle-list indices. Meshes in the MetalSprockets ecosystem are SwiftMesh meshes (MetalSprocketsAddOns uses it), so emitting from a model means converting by hand. Add a SwiftMesh dependency and an EmitterMesh initializer that takes a SwiftMesh mesh, handling its index format and non-triangle topology. Related: #2 (mesh colliders should take SwiftMesh too).

- `2026-10-17T21:14:02Z`: Added SwiftMesh dependency (0.0.10, as MetalSprocketsAddOns) and EmitterMesh(device:mesh:), which triangulates polygon faces (holes included) with Mesh.triangulate(). Tests cover a quad face, vertex emission, and a cube primitive.

---

## 39: Inspector is long and hard to scan

+++
status: open
priority: medium
kind: enhancement
labels: effort:s, area:tooling
created: 2026-10-17T21:07:28Z
+++

The demo inspector (#31) lists every control as a full-size row in a long sequence of sections, so it is hard to find a setting and needs a lot of scrolling. Reorganize it: group related controls into clear sections, collapse rarely used ones behind disclosure groups (variation, sprite sheet, curves, per-collider and per-field details), use smaller control sizes (.controlSize(.small)), and keep the most-used controls (preset, playback, emitter picker, birth rate, color) near the top. Related: #31.

- `2026-10-17T21:55:52Z`: Also add sub-emitter editing (#9): list a selected emitter's subEmitters with occasion, countPerEvent, velocityFactor, and the child settings (reuse the emitter sections).

---

## 40: Demo has no real textured or flipbook particles

+++
status: new
priority: low
kind: enhancement
labels: effort:s, area:demo
created: 2026-10-17T21:10:10Z
+++

Textures and flipbooks (#5) work, but the demo only has the 2x2 color test sheet. No preset uses an image sequence.

Idea: render emojis with Core Text into sprites and sprite sheets, so we need no image assets. For example:
- Single emoji sprites (🔥, ❤️, ⭐, 💧) as ParticleSprite cases.
- Emoji flipbooks, e.g. a sheet of 🌑🌒🌓🌔🌕 moon phases or 🕐…🕛 clock faces, played with an ImageSequence.
- One or two presets that use them (e.g. hearts, moon-phase sparkle).

Note: emoji glyphs are color, so the particle color tint must multiply (or be white) to keep them readable.

---
