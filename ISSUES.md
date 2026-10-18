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
labels: effort:xl, area:collision, deferred
created: 2026-10-17T13:27:25Z
updated: 2026-10-18T13:33:59Z
+++

Particles only collide with analytic shapes (plane, sphere, AABB). Real scenes need collision with mesh geometry, e.g. via a baked SDF volume or the scene depth buffer.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit has colliderNodes (collide with node geometry). RealityKit ParticleEmitterComponent has no collision API at all, so this is a clear place to beat it.
- `2026-10-17T14:11:14Z`: Related: #3 (SDF colliders could share the mesh SDF path).
- `2026-10-17T15:54:23Z`: SDF volume colliders were split out of #3 and belong here: a baked 3D distance texture is the same collision path mesh colliders need. Scope now: Collider case for a 3D SDF texture + bounds/transform, kernel sampling with gradient normals, and baking from a mesh.
- `2026-10-17T19:34:40Z`: Main consumer: MetalSprocketsSceneGraph integration, where colliders come from scene-node geometry at runtime. Mesh/SDF colliders need to accept that geometry (and its transforms) per frame.
- `2026-10-17T21:05:19Z`: Mesh input should come from SwiftMesh (github.com/schwa/SwiftMesh), the mesh type used across the MetalSprockets ecosystem (MetalSprocketsAddOns depends on it). Mesh/SDF colliders should accept a SwiftMesh mesh plus transform, not raw arrays.
- `2026-10-17T21:05:19Z`: Related: #38 (SwiftMesh input for EmitterMesh); share the conversion.
- `2026-10-18T13:33:59Z`: Decision (user): skip for now.

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
status: closed
priority: low
kind: feature
labels: effort:l, area:rendering
created: 2026-10-17T13:27:25Z
updated: 2026-10-18T13:16:49Z
closed: 2026-10-18T13:16:49Z
+++

Particles are unlit and clip hard against geometry.

- `2026-10-17T14:02:37Z`: Doc review: both have isLightingEnabled. SceneKit also has isBlackPassEnabled. Neither documents soft particles, so soft particles would beat both.
- `2026-10-18T13:16:49Z`: Lighting: ParticleSystem.lights ([ParticleLight]: directional, point with range) + ambientLight; ParticleEmitter.isLit (off by default). Quads are lit per corner with sphere-like normals. Soft particles: ParticleEmitter.softness + render(projection:view:sceneDepth:) fades particles within softness world units of the scene depth (the app's depth texture, read not attached). Presets and effect files carry lights/ambient (older files still load). Demo: Lit toggle; softness has no demo because the demo has no scene geometry/depth. Goldens unchanged; LightingTests check pixels.

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
labels: effort:xl, area:simulation, tracking
created: 2026-10-17T14:01:52Z
updated: 2026-10-18T17:06:39Z
+++

SceneKit lets callers attach event handlers (birth, death, collision) and per-frame modifier blocks at several simulation stages. A GPU system needs an equivalent, e.g. user-supplied Metal functions for spawn, update, or render, so effects can go beyond the built-in parameters.

- `2026-10-18T13:33:59Z`: Decision (user): functions. Custom per-particle behavior is user-supplied Metal functions called from the simulation kernel (e.g. visible functions or function constants/stitching via MetalSprockets), not Swift closures or a fixed set of built-in modifier stages. Next: split into a design spike for the function signature and linking, then implementation.
- `2026-10-18T17:06:39Z`: Split into #85 (spike, do first), #86 (update hook), #87 (spawn hook), #88 (effect files), and #89 (event hooks). A render-stage hook is left out until needed.

---

## 25: No presets or saved effect files

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:tooling
created: 2026-10-17T14:01:52Z
updated: 2026-10-18T12:47:29Z
closed: 2026-10-18T12:47:29Z
+++

RealityKit ships ParticleEmitterComponent.Presets (fireworks, impact, magic, rain, snow, sparks). SceneKit loads .scnp files authored in Xcode's particle editor. We have one hard-coded fountain and no serializable effect format.

- `2026-10-17T17:18:07Z`: Related: #30 now loads presets through a picker; saved effect files from this issue should appear in the same picker.
- `2026-10-18T12:47:29Z`: Built-in presets already exist (23). Added a saved effect format: ParticlePreset and everything it contains are Codable (JSON); ParticleEmitter decoding keeps defaults for missing keys so old files still load. ParticlePreset(contentsOf:), write(to:), jsonData(), and Transferable (.json). particles-render --effect file.json / --save-effect file.json. Demo: Open Effect / Save Effect (fileImporter/fileExporter); opened effects appear in the preset picker (#30's note). Meshes are not saved: filed #65. Demo sandbox now allows read-write user-selected files.

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
status: closed
priority: low
kind: task
labels: effort:m, area:rendering
created: 2026-10-17T15:00:32Z
updated: 2026-10-18T13:24:08Z
closed: 2026-10-18T13:24:08Z
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
- `2026-10-18T13:24:08Z`: Spike answered: drop. particles-bench at 1080p (render GPU; machine load 3-4, so absolute numbers noisy, ratios hold): 100K 0.2 ms; 1M few-pixel (default 0.01) 2.3-3.6 ms; 1M sub-pixel 0.94 ms; 1M 4x size 15.1 ms; 1M sorted 2.9 ms render + 1.2 ms simulate. Render cost scales with on-screen area (fill/blend bound); ~0.9 ms is the quad-setup floor at 1M. The point rasterizer would only help the small-opaque-point range (0.9 to ~2.3 ms), which is already ~15-20% of a 60 fps frame, and is weakest for large points, the only slow case (15 ms). It also drops alpha, soft falloff, fade-out, and additive glow that nearly every preset uses, and needs Apple GPU family 8+, a depth attachment, an extra pass, per-pixel buffers, and an AddOns dependency. Prototype (step 2) skipped because step 1 showed no slow case it would fix. If sub-pixel counts ever matter, Metal's point primitive (keeps blending) is the cheaper option.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:tooling
created: 2026-10-17T17:10:23Z
updated: 2026-10-18T14:24:33Z
closed: 2026-10-18T14:24:33Z
+++

Defining an effect means creating a ParticleEmitter and setting many properties one by one, then wiring texture, transform, and colliders on ParticleSystem separately. There is no concise, composable way to describe an effect or reuse parts of one. Stretch goal: a small Swift DSL, possibly result-builder or SwiftUI-modifier style (e.g. Emitter { ... }.birthRate(5_000).colorOverLife(...).force(.turbulence(...))), so effects compose like SwiftUI views and presets (#30, #25) become short declarations. Related: #30 (preset scenes), #25 (presets/effect files).

- `2026-10-18T12:48:08Z`: Reviewed against the current API. The wiring half is solved: EmitterDescription + ParticlePreset + ParticleSystem.apply (#50) describe an effect in one value, and effects are JSON files (#25). Punting the rest: the DSL shape is an API decision. Options: (A) public configure init, ParticleEmitter { $0.birthRate = 5_000 }, i.e. publish the private emitter {} helper Presets.swift already uses; tiny. (B) SwiftUI-style modifiers, ParticleEmitter().birthRate(5_000).colorOverLife(...): ~40 near-duplicate methods, or one generic .set(\.birthRate, 5_000) that is barely shorter than A. (C) result builder for presets, ParticlePreset("Sparks") { EmitterDescription(...); Collider.plane(...); ForceField.turbulence(...) }: composes like SwiftUI, bigger commitment. Recommend A now, C if presets should read like SwiftUI; skip B. Which do you want?
- `2026-10-18T13:33:59Z`: Decision (user): option C, a result builder for presets, e.g. ParticlePreset("Sparks") { EmitterDescription(...); Collider.plane(...); ForceField.turbulence(...) }.
- `2026-10-18T14:24:33Z`: Option C: ParticlePresetBuilder result builder and ParticlePreset(_ name:, animatesColliders:, ambientLight:, cameraEye:, cameraTarget:) { ... } taking EmitterDescription layers, Collider, ForceField, ParticleLight, and TrackedObject in any order, with if/else, for, if-let, and availability. Each kind keeps its written order. Sparks and Dunk converted as examples (goldens unchanged); the other presets keep the memberwise initializer. Tests: builder equals the memberwise init (ids aside), control flow. Emitter settings are still built by configuring a ParticleEmitter (the presets' emitter {} helper); option A was not chosen.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:emission
depends: 33
created: 2026-10-17T17:16:57Z
updated: 2026-10-17T22:04:12Z
closed: 2026-10-17T22:04:12Z
+++

Emitters only emit on their own clock (birth rate, duration, idle) or when code calls burst(). There is no way to make emission happen in response to something: a trigger volume that particles or scene objects enter, a collider being hit, a timer or sequence, or a named event from the app. Effects like sparks where a blade touches a wall, a splash when something enters water, or a firework that bursts at the top of its arc need triggers that start, stop, or burst an emitter, ideally evaluated on the GPU for particle-driven events. Related: #33 (multiple emitters), #9 (sub-emitters: spawn on particle birth/death/collision), #23 (die on collision).

- `2026-10-17T19:36:36Z`: Depends on #33. Design with #9.
- `2026-10-17T21:55:52Z`: Design note from #9: sub-emitters use fixed child slots per parent particle written directly by the parent kernel (no atomics, deterministic). Particle-driven triggers can reuse the event detection in updateParticles (birth/death/collision/whileAlive); app and volume triggers are the new part.
- `2026-10-17T22:04:12Z`: Added ParticleEmitter.triggers ([EmissionTrigger]: condition + action). Conditions: event(name) via send(event:), after/every seconds of simulation time, objectEnters(name, volume) using trackedObjects, particlesEnter(volume, count) and colliderHit(index, count) counted on the GPU with monotonic atomic counters read back at the next simulate. Actions: burst, start, stop, restart. Particle-driven per-particle spawning is #9 (sub-emitters). Inspector editing noted on #39. Bench unchanged.

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
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:tooling
created: 2026-10-17T21:07:28Z
updated: 2026-10-17T22:08:42Z
closed: 2026-10-17T22:08:42Z
+++

The demo inspector (#31) lists every control as a full-size row in a long sequence of sections, so it is hard to find a setting and needs a lot of scrolling. Reorganize it: group related controls into clear sections, collapse rarely used ones behind disclosure groups (variation, sprite sheet, curves, per-collider and per-field details), use smaller control sizes (.controlSize(.small)), and keep the most-used controls (preset, playback, emitter picker, birth rate, color) near the top. Related: #31.

- `2026-10-17T21:55:52Z`: Also add sub-emitter editing (#9): list a selected emitter's subEmitters with occasion, countPerEvent, velocityFactor, and the child settings (reuse the emitter sections).
- `2026-10-17T22:04:12Z`: Also add trigger editing (#34): list an emitter's triggers (condition + action) with add/remove, and a field to send named events.
- `2026-10-17T22:08:42Z`: Reorganized the inspector: Scene (preset, playback, speed, restart/revert) and Emitter (picker + actions menu, name, emitting, burst) at the top; per-emitter sections show the most-used controls and tuck the rest into disclosure groups (Timing, Placement, Emitter Motion, Curves, Rotation, Sprite Sheet, Variation); new Sub-Emitters (#9) and Triggers (#34) sections with Send Event; World section with collapsible collider and force-field lists; .controlSize(.small) throughout. Key-path bindings only. Not visually checked (no app launch).

---

## 40: Demo has no real textured or flipbook particles

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:demo
created: 2026-10-17T21:10:10Z
updated: 2026-10-18T00:41:18Z
closed: 2026-10-18T00:41:18Z
+++

Textures and flipbooks (#5) work, but the demo only has the 2x2 color test sheet. No preset uses an image sequence.

Idea: render emojis with Core Text into sprites and sprite sheets, so we need no image assets. For example:
- Single emoji sprites (🔥, ❤️, ⭐, 💧) as ParticleSprite cases.
- Emoji flipbooks, e.g. a sheet of 🌑🌒🌓🌔🌕 moon phases or 🕐…🕛 clock faces, played with an ImageSequence.
- One or two presets that use them (e.g. hearts, moon-phase sparkle).

Note: emoji glyphs are color, so the particle color tint must multiply (or be white) to keep them readable.

- `2026-10-18T00:32:29Z`: Related demo gaps filed alongside this: see the area:demo issues for triggers, sorting, teapot mesh, orientation, local space, rain collision splashes, and smaller features.
- `2026-10-18T00:38:45Z`: Triaged: medium (part of the demo-gap batch #41–#47), effort:s, area:demo.
- `2026-10-18T00:41:18Z`: Added Core Text emoji sprites (heart, fire, droplet, glowing star) and emoji flipbook sheets (moon phases 2x4, clock faces 3x4) to ParticleSprite, plus defaultImageSequence. New presets Hearts and Moon Phases (flipbook with per-particle starting phase) with goldens.

---

## 41: No preset shows emission triggers

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:demo
created: 2026-10-18T00:32:28Z
updated: 2026-10-18T00:51:47Z
closed: 2026-10-18T00:51:47Z
+++

Triggers (#34) are not used by any preset, so they are invisible in the demo. Add a preset built around them, for example a ball (tracked object or animated collider) dropping into a water volume that bursts a splash on entry (objectEnters / particlesEnter), plus sparks that burst on every collider hit (colliderHit). Ideally the demo also offers a Send Event button target. Related: #34, #40.

- `2026-10-18T00:51:47Z`: Added the Bumper preset: balls drop on a sphere bumper (colliderHit -> spark burst), bounce into a goal volume (particlesEnter -> star burst), a ground ring pulses every 2 s (every), and the event 'boom' (Send Event in the demo) fires confetti. Golden added. objectEnters isn't shown since presets can't carry tracked objects; the app sets those.

---

## 42: No preset shows back-to-front sorting

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:45:41Z
closed: 2026-10-18T00:45:41Z
+++

Sorting (#4) is enabled for Smoke and Snow, but their alpha is so low that the difference cannot be seen. Add a preset with dense, fairly opaque, overlapping alpha particles (for example thick colored smoke or bubbles) where sorting clearly matters, and make it easy to compare sorted and unsorted in the demo. Related: #4, #40.

- `2026-10-18T00:45:41Z`: Added the Color Smoke preset: dense, nearly opaque, multicolored smoke puffs sorted back to front. Compare with Sort: None in the inspector, or particles-render --preset 'Color Smoke' --no-sort (new flag).

---

## 43: No preset emits from a mesh (teapot)

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:55:31Z
closed: 2026-10-18T00:55:31Z
+++

Mesh emission (#7) and SwiftMesh input (#38) are not shown anywhere. Add a preset that emits from the SwiftMesh teapot (SwiftMesh bundles Resources/teapot.obj), for example a teapot outlined in glowing particles or dissolving into sand that falls away. Presets would need a way to carry a mesh (ParticlePreset.Layer has no mesh today). Related: #7, #38, #40.

- `2026-10-18T00:55:31Z`: Added ParticlePreset.Layer.mesh (SwiftMesh Mesh), loaded into EmitterMesh by ParticleSystem.load and by the demo model. New Teapot preset: SwiftMesh's Utah teapot, side on, outlined in glowing particles and dissolving into sand that piles on the ground. Golden added.

---

## 44: No preset uses flat or Y-aligned particle orientation

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:46:48Z
closed: 2026-10-18T00:46:48Z
+++

The flat (fixed plane) and Y-aligned orientation modes (#18) are unused. Add demos that need them: ripples spreading flat on a water surface, and upright flames or grass that turn only around Y. Related: #18, #40.

- `2026-10-18T00:46:48Z`: Added Pond (flat ring ripples, fixed orientation, plus velocity-aligned drops) and Ring of Fire (emoji flames, Y-aligned, seen from above) presets with goldens.

---

## 45: No preset shows local simulation space

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:47:50Z
closed: 2026-10-18T00:47:50Z
+++

Local simulation space (#22) is unused: every preset simulates in world space. Add a demo where it matters, for example a moving emitter whose particles orbit and travel with it, ideally next to the same effect in world space leaving a trail. Related: #22, #40.

- `2026-10-18T00:47:50Z`: Added the Swarms preset: two identical circling firefly swarms, gold in local space (travels as a tight cloud) and blue in world space (leaves a trail). Golden added.

---

## 46: Rain splashes do not come from raindrop collisions

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:48:38Z
closed: 2026-10-18T00:48:38Z
+++

The Rain preset spawns splashes from a separate emitter spread over the ground plane, so splashes do not line up with where drops land and miss the tilted slab. Use an onCollision sub-emitter (#9) on the raindrops instead, so each drop that hits the ground or slab makes its own splash. Related: #9, #23.

- `2026-10-18T00:48:39Z`: Rain splashes are now an onCollision sub-emitter (3 per drop) on the raindrops instead of a separate ground-plane emitter, so they appear where drops land, including on the tilted slab. Golden updated.

---

## 47: Some emitter features have no demo

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T00:32:29Z
updated: 2026-10-18T00:49:55Z
closed: 2026-10-18T00:49:55Z
+++

A few smaller features are unused by every preset: cone and cylinder emitter shapes (#7), screen and opaque blend modes (#19), and the emit/idle/loop emission cycle (#21). Work them into existing or new presets, for example a cone-shaped thruster exhaust, a pulsing geyser on an emit/idle loop, and opaque alpha-tested debris. Related: #40.

- `2026-10-18T00:49:55Z`: Added the Geyser preset: emit/idle loop (1.5 s on, 2.5 s off), cylinder-shaped water column, opaque tumbling rock debris, and screen-blended steam from a cone. Golden added.

---

## 48: Force fields, trigger volumes, and emitter shapes are not drawn

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:rendering
created: 2026-10-18T00:32:50Z
updated: 2026-10-18T00:58:46Z
closed: 2026-10-18T00:58:46Z
+++

renderColliders draws collider wireframes, but nothing else in the world is visible: force fields (attractor and vortex centers, axes, and radii; wind direction), trigger volumes (#34), and emitter shapes and transforms (where a disc, cone, torus, or mesh emitter sits and how it is oriented, including pitch/spin from #36). Tuning a scene means guessing where these are. Add debug wireframes for them, toggled like the collider wireframes (demo Wireframes toggle and particles-render --wireframes). Related: #1 (collider wireframes).

- `2026-10-18T00:58:46Z`: Added ParticleSystem.renderWireframes(projection:view:options:) drawing colliders (blue), force fields (magenta: wind arrows, attractor cross+radius, vortex rings with spin arrows; turbulence draws nothing), trigger volumes (green), and emitter shapes at their current transforms (yellow; mesh shows a center cross). particles-render --wireframes and the demo Wireframes toggle use it. Golden debug-wireframes added. Highlighting the outline selection (#49) is not done.

---

## 49: Demo editor needs an outline sidebar and a detail inspector

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:tooling
created: 2026-10-18T00:36:16Z
updated: 2026-10-18T00:44:00Z
closed: 2026-10-18T00:44:00Z
+++

All editing lives in one long right-hand inspector (#39), even after reorganizing it. A real effect editor needs two sidebars: an outline on the left listing the scene's objects (presets/effect, emitters with their sub-emitters and triggers nested underneath, colliders, force fields, trigger volumes), and the inspector on the right showing details for whatever is selected in the outline. Selecting an item could also highlight it in the viewport (see #48 for wireframes). Use NavigationSplitView or an equivalent leading sidebar plus the existing trailing inspector. Related: #39, #48.

- `2026-10-18T00:44:00Z`: NavigationSplitView: outline sidebar (Scene, Emitters with nested sub-emitters and triggers, Colliders, Force Fields; Add menu, context menus, Delete key) and a trailing inspector that shows details for the selection. Not visually checked (no app launch). Viewport highlighting of the selection is left to #48.

---

## 50: Emitter description is duplicated across Layer, DemoEmitter, and ParticleSystem.Emitter

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:tooling, kind:refactor
created: 2026-10-18T01:36:03Z
updated: 2026-10-18T01:53:09Z
closed: 2026-10-18T01:53:09Z
+++

An emitter's full description (settings, sprite, motion, simulation space, mesh, capacity, emitting) exists three times: ParticlePreset.Layer, the demo's DemoEmitter, and the runtime ParticleSystem.Emitter. Converting between them is hand-written in ParticleSystem.load(_:), ParticlesDemoModel.sync, DemoEmitter.init(layer), and duplicateSelectedEmitter (which copies fields one by one, so a missed field is silently dropped). Sprite->texture and Mesh->EmitterMesh resolution is done twice with two caches. Adding the mesh in #43 meant touching all of them.\n\nDirection: one library value type describing an emitter (used by presets and the demo), and one place in ParticleSystem that resolves it into runtime state (textures, GPU meshes, capacity) with caching. Dependency category: in-process (Metal device only for resource resolution). Tests: one boundary test 'description in, runtime emitter out' replaces the scattered demo/preset loading checks. Source: architecture review.

- `2026-10-18T01:53:09Z`: Added EmitterDescription (library; Identifiable, Equatable: name, settings, sprite, motion, simulation space, capacity, mesh, emitting) and ParticleSystem.apply(_:rebuild:), the one place descriptions become runtime emitters: rebuilds when ids/capacities change, otherwise updates in place; textures cached per sprite on the system, GPU meshes remade only when the mesh changes. ParticlePreset.Layer is now a typealias; load(_:) is apply(rebuild: true). The demo's DemoEmitter, capacity table, texture cache, mesh cache, sync, and field-by-field duplicate are gone (copy(named:)). EmitterDescriptionTests cover in-place edits, rebuilds, caching, and copy.

---

## 51: ParticleSystem mixes frame planning with GPU encoding

+++
status: closed
priority: medium
kind: task
labels: effort:l, area:simulation, kind:refactor
created: 2026-10-18T01:36:03Z
updated: 2026-10-18T02:08:26Z
closed: 2026-10-18T02:08:26Z
+++

ParticleSystem.swift (~700 lines) plus ParticleSystem+Triggers, Spawner, and ParticleSort own: shared-buffer layout and rebuild, sub-emitter slot layout, emission timing, trigger evaluation, uniform building, the simulate encoder, sorting, and rendering. Every feature in #4, #9, and #34 required reading most of the file. Nearly all behavior can only be tested by running a GPU frame and reading particles back.\n\nDirection: split a pure CPU 'frame planner' (given emitters, time, events, counters -> which emitters spawn how many from which slots with which uniforms) from the GPU executor that encodes it. Dependency category: in-process for the planner; Metal stays a local stand-in for the executor. Tests: timing, trigger, and slot-layout tests move to the planner without the GPU; GPU tests shrink to integration and goldens. Source: architecture review.

- `2026-10-18T02:08:26Z`: Split simulate into planFrame (CPU: colliders/transforms, sub-emitter rebuild, triggers, spawn timing, warmup steps, live windows, uniforms, sub-emitter slot data, collider velocities -> FramePlan) and encode (GPU only). FramePlan.swift holds the planner; ParticleSystem.swift shrank by ~200 lines. New FramePlanTests check timing, warmup, clamping/pause, live windows, kill, sub-emitter slots, collider velocity, and the CPU triggers without dispatching; event/timer/object/restart trigger tests moved out of the GPU suite. Goldens unchanged; bench unchanged. Sorting still plans inside encode's caller (needs buffers).

---

## 52: Swift and Metal agree on uniform packing only by convention

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:simulation, kind:refactor
created: 2026-10-18T01:36:03Z
updated: 2026-10-18T01:49:08Z
closed: 2026-10-18T01:49:08Z
+++

ParticleTypes.h structs are filled by hand in Swift (the ~40-field SimulationUniforms setup in ParticleSystem) and by per-type packers (EmitterShape.parameters, ParticleOrientation.parameters, ForceFieldData, TriggerVolumeData). Several fields are packed uint4/float4 lanes with undocumented meanings (triggers.x = volume count, triggers.y = collider flag; imageSequence lanes; shape parameters per kind), and limits like PARTICLE_TRIGGER_MAX_* are shared constants. Nothing but golden images would catch a mismatch.\n\nDirection: give each packed type one Swift encoder next to its decoder contract, name the lanes (or use explicit structs instead of packed vectors), and add round-trip tests: encode in Swift, decode with a tiny test kernel calling the same Metal helper the simulation uses, compare. Dependency category: in-process plus GPU as local stand-in. Source: architecture review.

\- `2026-10-18T01:39:13Z`: Chosen direction: follow the MetalSprockets header style (MetalSprocketsShaders.h, AddOns ColorSource.h, PBR PBRShaderTypes.h) instead of codegen or round-trip kernels for everything.

1. Enums: keep MS_ENUM from MetalSprocketsShaders.h (already imported via the package dependency; MetalCompilerPlugin has include-dependencies on). Store enums as enum-typed fields (ParticleEmitterShapeKind kind;), never as uint4/float4 lanes. Force-field and trigger-volume kinds become MS_ENUMs instead of float4 kind.
2. Replace grab-bag simd_float4/simd_uint4 lanes in SimulationUniforms, SubEmitterData, ForceFieldData, TriggerVolumeData, RenderUniforms with named scalar fields, grouped into sub-structs per concern (e.g. ParticleShapeData { kind, birthLocation, birthDirection, radius, height, size, sweep }, ParticleCollisionData, ParticleImageSequenceData, ParticleVariationData), like PBRTextureSlot.
3. Put decoding/sampling methods on those structs in the header under #if defined(__METAL_VERSION__) (like ColorSourceArgumentBuffer::resolve), so each meaning is written once next to its fields.
4. Shared limits stay #define k... constants; note Swift mirror types in comments.
5. Swift fills fields by name; delete the per-type parameters packers.
6. Shared types used by other Metal packages can be imported from them rather than redefined.

Check: struct layout changes, so all goldens and determinism tests must still pass unchanged. Round-trip test kernels only for helpers with real logic (shape sampling).

- `2026-10-18T01:49:08Z`: Reworked ParticleTypes.h in the MetalSprockets header style: MS_ENUM-typed fields (new ParticleColliderKind, ParticleForceFieldKind, ParticleTriggerVolumeKind replace float4 kinds), named scalar fields and sub-structs (ParticleShapeData, ParticleVariationData, ParticleSpawnData) instead of packed float4/uint4 lanes in SimulationUniforms, SubEmitterData, ColliderData, ForceFieldData, TriggerVolumeData, ParticleSortKeyParams, RenderUniforms. TriggerVolumeData::contains lives in the header. Swift fills fields by name; EmitterShape.parameters and ParticleOrientation.parameters are gone. Particle keeps its packed layout (per-particle memory). All 158 tests incl. goldens and determinism pass unchanged; bench unchanged. No round-trip kernels added: named fields removed the lane conventions they would have tested.

---

## 53: Demo mirrors every library enum with hand-written Kind adapters

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:demo, kind:refactor
created: 2026-10-18T01:36:03Z
updated: 2026-10-18T01:59:47Z
closed: 2026-10-18T01:59:47Z
+++

ParticleEmitter+Inspector.swift (~500 lines) and Inspector+Events.swift (~260 lines) mirror each library enum with associated values (EmitterShape, SubEmitter.Occasion, EmissionTrigger.Condition/Action, TriggerVolume, Collider, ForceField, orientation) as a separate Kind enum plus one writable computed property per associated value, with defaults chosen ad hoc when switching kinds. Each new library case needs 3-5 edits in the demo, and the adapters need their own round-trip tests.\n\nDirection: let the library expose a case kind (CaseIterable) and a default value per kind for these enums, so the demo needs only a generic kind binding plus per-field properties; or a small generic adapter. Dependency category: in-process. Tests: one generic kind round-trip test per enum replaces the per-adapter tests. Source: architecture review.

- `2026-10-18T01:59:47Z`: The library now owns case switching: ParticleKind protocol (CaseIterable, Identifiable, name) adopted by the header MS_ENUM kinds (shape, orientation, collider, force field, spawn occasion, trigger volume, blend, birth location/direction, sequence mode) and Swift kinds (EmissionTrigger.Condition.Kind/Action.Kind, sort mode, motion, simulation space, sprite). EmitterShape, ParticleOrientation, Collider, ForceField, SubEmitter.Occasion, TriggerVolume, and the trigger condition/action each get a writable kind whose setter converts to a sensible value. The demo's seven mirror Kind enums and their adapters are gone; one generic KindPicker replaces every picker. ParticleKindTests round-trips every kind generically.

---

## 54: Emitters can't opt out of specific force fields or colliders

+++
status: closed
priority: high
kind: feature
labels: effort:m, area:simulation, needs-decision
created: 2026-10-18T01:43:22Z
updated: 2026-10-18T13:04:47Z
closed: 2026-10-18T13:04:47Z
+++

Every force field and collider affects every emitter's particles. Often only some should interact, e.g. smoke should feel wind but not a vortex, or sparks should bounce off the floor but rain should pass through a roof.

Proposal: bitmask categories, like SpriteKit/SceneKit physics:
- Each force field and collider gets a categoryBitMask (UInt32, default all bits).
- Each emitter gets affectedByMask / collisionMask (default all bits).
- A field/collider applies when (emitter mask & category) != 0.
- Pass the per-emitter mask in the simulate uniforms; test it in the shader loop over fields/colliders.

Defaults keep today's behavior. Add tests for masked vs unmasked particles and expose the masks in the demo inspector.

- `2026-10-18T12:40:25Z`: Triaged: High (raised by user), feature, effort:m, area:simulation.
- `2026-10-18T12:42:01Z`: Looked at implementing the proposed category masks. Punting: it needs an API decision, because Collider and ForceField are enums with associated values and have nowhere to store a per-instance categoryBitMask. Options: (A) make each a struct (shape enum + categoryBitMask) with static .sphere(...)-style constructors so creation code still compiles, but ~75 pattern-match sites change, including #53's writable kind and the demo adapters; closest to the proposal, effort ~l. (B) Parallel category arrays on ParticleSystem and ParticlePreset matched by index: little churn, but clunky and easy to desync. (C) Emitter-side masks by collider/field index (bit i = item i): no type changes, but breaks on reorder and is not real categories. Recommend A. Which do you want?
- `2026-10-18T13:04:48Z`: Implemented option A. Collider and ForceField are structs: shape/effect (the old enums, now Collider.Shape and ForceField.Effect) plus categoryBitMask (default all bits); static constructors keep old call sites. ParticleEmitter gains collisionMask and fieldMask (default all bits). Filtering happens on the CPU in the frame planner: each dispatch binds only the colliders/fields that match its emitter, so the shader has no mask cost (an in-shader check measured ~0.4 ms slower at 1M and was dropped); colliders carry triggerIndex so collider-hit triggers keep matching system indices. Demo: category toggles (bits 1-8) on colliders, fields, and emitters. Saved files: masks saved only when not all bits; older collider and force-field JSON still loads. Goldens unchanged.

---

## 55: Consider Canvas3D for debug wireframes

+++
status: open
priority: low
kind: task
labels: effort:m, area:rendering, needs-info
created: 2026-10-18T01:45:02Z
updated: 2026-10-18T13:22:12Z
+++

Debug wireframes (DebugWireframes.swift, ColliderWireframe.swift) use a hand-rolled WireframeBuilder and a custom line-list RenderPipeline (wireframeVertex/wireframeFragment), one flat color per kind.

Evaluate replacing this with Canvas3D. Possible wins: less custom shader/pipeline code, shared look with other MetalSprockets tools, and features we lack (line width, depth fade, labels).

Check first: dependency weight for the library target (maybe keep wireframes in an optional target), and that it fits inside a RenderPass the same way renderWireframes does now. Keep the particles-render --wireframes flag and the demo toggle working.

- `2026-10-18T12:40:25Z`: Triaged: Low, task, effort:m, area:rendering.
- `2026-10-18T13:22:11Z`: Looked for Canvas3D to evaluate it: no Swift source mentions it under ~/Shared/Projects or ~/Projects (MetalSprockets, AddOns, all .build checkouts), in DerivedData, or in a GitHub code search of schwa's repos. Punting: can't judge dependency weight or RenderPass fit without its API. Where does Canvas3D live (package/repo/branch)? Meanwhile the current wireframes are small (WireframeBuilder + one flat-color line pipeline, ~300 lines) and work in particles-render --wireframes and the demo.

---

## 56: Crash when removing a collider while the simulation is running

+++
status: closed
priority: high
kind: bug
labels: area:demo, effort:xs
created: 2026-10-18T02:07:29Z
updated: 2026-10-18T12:35:29Z
closed: 2026-10-18T12:35:29Z
+++

Removing a collider while the particle system is running crashes the app (seen in the demo).

Not yet investigated. Guess: the collider buffer or count used by an in-flight simulate pass goes stale when the array shrinks.

To do: get the crash log/backtrace, write a test that removes a collider mid-run, fix.

\- `2026-10-18T02:08:03Z`: Backtrace: EXC_BREAKPOINT in SwiftUICore BindingOperations.ForceUnwrapping.get, during NSHostingView.layout. Not a GPU/simulation bug; my earlier guess was wrong.

Likely cause: EmitterInspectorView.swift:44 uses 'if let collider = Binding($model.colliders[id: id])'. Binding(optional) force-unwraps on every read. After removal, ColliderEditorView's child bindings update before the parent body re-runs, so the unwrap hits nil. Same pattern at line 51 for force fields, so removing a force field probably crashes too.

Fix: drop Binding(optional). Use a custom Binding whose get falls back to a cached/default value and whose set ignores missing ids, or pass the id down and look it up in the model.

- `2026-10-18T12:35:29Z`: Fixed: the inspector bound colliders and force fields with Binding(optional), which force-unwraps on every read; after a removal SwiftUI read it once more and trapped. Sub-emitter and trigger editors had the same class of bug (array index binding out of range after removal). All four now bind through non-optional model properties (selectedCollider, selectedForceField, selectedSubEmitter, selectedTrigger) that read a placeholder and drop writes when the item is gone. Regression test exemption: the trap is inside SwiftUI's binding and kills the test process, so no red-first test; OutlineTests.selectedItemsSurviveRemoval checks the model contract instead. Not verified in the running app.

---

## 57: Curve stop rows can crash when a stop is removed

+++
status: closed
priority: high
kind: bug
labels: effort:s, area:demo
created: 2026-10-18T12:36:56Z
updated: 2026-10-18T12:41:17Z
closed: 2026-10-18T12:41:17Z
+++

ColorCurveEditorView and FloatCurveEditorView (InspectorControls.swift) use ForEach(curve.keyframes.indices, id: \.self) and bind .keyframes[index] in rows that also contain their own Remove button. After removing a stop (especially the last), SwiftUI can read a stale row binding one past the end of the array and trap: the same class of bug as #56. Fix with stable ids for stops, or route reads/writes through an accessor that returns a placeholder and drops writes for missing indices. Source: SwiftUI review.

- `2026-10-18T12:41:17Z`: Curve rows now bind through ParticleCurve[stop:] (demo extension): reads past the end return the last keyframe, writes past the end are dropped. No red-first test: the old array subscript traps, which kills the test process. OutlineTests.curveStopAccessSurvivesRemoval covers the accessor contract. Not checked in the running app.

---

## 58: Rename demo views missing the View suffix

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:demo
created: 2026-10-18T12:36:56Z
updated: 2026-10-18T12:37:41Z
closed: 2026-10-18T12:37:41Z
+++

House rule: SwiftUI view types end in View. KindPicker -> KindPickerView (InspectorControls.swift), EmitterOutlineRow -> EmitterOutlineRowView (OutlineView.swift). Source: SwiftUI review.

- `2026-10-18T12:37:41Z`: Closed by request without changes.

---

## 59: Extract ParticlesView.viewport into its own view

+++
status: closed
priority: low
kind: task
labels: effort:s, area:demo
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T13:19:39Z
closed: 2026-10-18T13:19:39Z
+++

ParticlesView has a large computed 'private var viewport: some View' (render closure, camera, overlay, onChange, ContentUnavailableView branch). House rule: extract into a struct (e.g. ParticleViewportView) taking the model, a camera binding, and the frame timing binding. Source: SwiftUI review.

- `2026-10-18T13:19:39Z`: Extracted ParticleViewportView (render closure, orbit camera, frame timing overlay, preset camera reset, unavailable state). It owns cameraMatrix and frameTiming as @State, since only it uses them; ParticlesView keeps the split view, inspector, and toolbar. Pure refactor; demo tests and app build pass. Not checked in the running app.

---

## 60: Add previews for demo leaf views

+++
status: open
priority: low
kind: task
labels: effort:s, area:demo, deferred
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T12:37:34Z
+++

Leaf views without #Preview: KindPicker, ColliderEditorView, ForceFieldEditorView, TriggerEditorView, SubEmitterEditorView, OutlineView. Each needs only a line or two of fixture state. ParticlesView needs Metal and can stay without one. Source: SwiftUI review.

---

## 61: Demo model is threaded through ~10 views by hand

+++
status: closed
priority: low
kind: task
labels: effort:s, area:demo
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T13:21:26Z
closed: 2026-10-18T13:21:26Z
+++

ParticlesDemoModel is passed explicitly into OutlineView, EmitterOutlineRow, EmitterInspectorView, SceneSectionView, EmitterSectionView, SendEventSectionView, WorldSectionView, RemoveSectionView, TriggersSectionView, etc. House rule suggests @Environment(ParticlesDemoModel.self) (with a local @Bindable) for shared app models. Optional: explicit passing is also clear. Source: SwiftUI review.

- `2026-10-18T13:21:26Z`: ParticlesView puts the model in the environment (.environment(model)); the 10 views read it with @Environment(ParticlesDemoModel.self) and a local @Bindable where they need bindings. All model: model arguments are gone (EmitterOutlineRow no longer needs the model at all). The inspector preview supplies the model through .environment. Pure refactor; demo tests and app build pass. Not checked in the running app.

---

## 62: RemoveSectionView is a near zero-value wrapper

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:demo
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T13:17:00Z
closed: 2026-10-18T13:17:00Z
+++

RemoveSectionView (EmitterInspectorView.swift) is one destructive button in a Section, no state, four call sites. House rule flags thin wrappers as removal candidates; four call sites may justify it. Decide whether to inline. Source: SwiftUI review.

- `2026-10-18T13:17:01Z`: Kept as is. The house rule flags thin wrappers with 1-2 call sites; RemoveSectionView has 4 (sub-emitter, trigger, collider, force field), all the same destructive Section + button bound to model.removeSelection(). That is real reuse, and inlining would repeat the same three lines four times. No code change.

---

## 63: selectedEmitter falls back to emitters[0]

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:demo
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T13:17:57Z
closed: 2026-10-18T13:17:57Z
+++

ParticlesDemoModel.selectedEmitter returns emitters.first { ... } ?? emitters[0], which traps if emitters is ever empty. Safe today only because the model keeps at least one emitter (removeSelectedEmitter refuses the last, presets all have layers). Make the invariant explicit or return a placeholder like selectedCollider (#56). Source: SwiftUI review.

- `2026-10-18T13:17:57Z`: Reachable: opening an effect file with no layers left emitters empty and selectedEmitter trapped on emitters[0]. It now falls back to the first emitter, then a placeholder whose writes are dropped (unknown id). No red-first test: the old code traps and kills the test process; OutlineTests.effectWithNoEmittersIsSafe covers the empty-effect path.

---

## 64: EmitterOutlineRow.emitterLabel is a computed view property

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:demo
created: 2026-10-18T12:36:57Z
updated: 2026-10-18T13:18:43Z
closed: 2026-10-18T13:18:43Z
+++

EmitterOutlineRow uses 'private var emitterLabel: some View' (label + tag + context menu), used twice. House rule allows tiny tightly-bound fragments; consider whether it should be a struct. Low value. Source: SwiftUI review.

- `2026-10-18T13:18:43Z`: Extracted into EmitterOutlineLabelView (label, selection tag, context menu). It has behavior, so per the house rule it is a struct, not a computed property. Pure refactor: no new test; build and 33 demo tests pass. Not checked in the running app (outline selection still relies on the tag inside the struct, which SwiftUI reads through custom views).

---

## 65: Saved effects drop emitter meshes

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:tooling
created: 2026-10-18T12:47:29Z
updated: 2026-10-18T13:11:38Z
closed: 2026-10-18T13:11:38Z
+++

Effect files (#25) save EmitterDescription without its mesh, because SwiftMesh's Mesh is not Codable. The Teapot preset saved to JSON and reopened emits from nothing (a center point). Options: make Mesh Codable in SwiftMesh, store triangulated positions + indices in the file, or reference a mesh by name/resource (e.g. 'teapot') that the loader resolves.

- `2026-10-18T13:11:38Z`: Meshes are saved as triangulated positions (meshPositions) and triangle indices (meshTriangles) inside EmitterDescription's Codable, and load back via Mesh(positions:faces:). Emission only uses triangles, so a saved Teapot renders byte-identical to the built-in preset. Out-of-range indices are a decoding error. Files are large for big meshes (Teapot effect: 1.4 MB pretty-printed JSON, mesh stored per layer).

---

## 66: No preset shows category masks

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T13:34:41Z
updated: 2026-10-18T13:52:13Z
closed: 2026-10-18T13:52:13Z
+++

Category masks (#54) are unused by every preset. Add a demo where they matter, e.g. rain that falls through an awning while sparks bounce off it, or smoke that feels wind while embers ignore it. Related: #54.

- `2026-10-18T13:52:13Z`: New Awning preset: rain (category 1) falls through a tilted awning (category 2) and slants in a category-1 wind; sparks from a grinder collide with both and ignore the wind, so they land on the awning and slide off its low edge. The awning is 30 cm thick: at 8 cm sparks tunneled through it between steps (#72). Golden added.

---

## 67: No preset shows particle lighting

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T13:34:41Z
updated: 2026-10-18T13:54:07Z
closed: 2026-10-18T13:54:07Z
+++

Lighting (#10: ParticleSystem.lights, ambientLight, ParticleEmitter.isLit) is unused by every preset. Add lit smoke or dust beside a moving point light (lantern, campfire glow), ideally with a directional light too. Related: #10.

- `2026-10-18T13:54:07Z`: New Lantern preset: lit smoke and dust motes (isLit) with a warm point light (lantern, range 2.5) near their base and cool directional moonlight from the side over low ambient; smoke is warm near the lantern and blue-grey above. The lantern's glow is a small sorted additive emitter so it draws in front of the sorted smoke. Lights are static (presets have no light animation). Golden added.

---

## 68: Soft particles cannot be demoed: no scene depth

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:demo
created: 2026-10-18T13:34:41Z
updated: 2026-10-18T16:04:08Z
closed: 2026-10-18T16:04:08Z
+++

Soft particles (#10) need a scene depth texture, but the demo and particles-render draw no scene geometry or depth. Add one: e.g. render a ground plane/box into a depth texture (or a pre-filled depth like LightingTests) and pass it as render(..., sceneDepth:), then a preset or demo toggle with softness on smoke meeting the ground. Related: #10.

- `2026-10-18T14:00:06Z`: Investigated. Punting: bigger than m and partly blocked on MetalSprockets API. Soft particles only show against opaque, depth-tested geometry, and the demo/CLI draw none (wireframes only); particles are not depth-tested, so nothing clips hard and fading near invisible surfaces would barely show. Needed: (1) draw colliders as shaded solids (SwiftMesh quad/box/sphere/capsule), (2) depth-test particles against them (test, no write), (3) a readable copy of the depth for the fragment shader (a pass can't read its own depth attachment). Blockers: MetalSprockets DepthState is package-internal (only a raw depthStencilDescriptor environment value is public; I haven't verified what depth state particles draw with now), and RenderView does not expose its depth texture to content, so the demo needs its own view-sized depth texture and a collider depth pre-pass per frame. Question: OK to (a) add a public depth-state modifier and depth-texture access to MetalSprockets, or (b) do it all inside this project with its own depth texture and pre-pass?
- `2026-10-18T14:27:44Z`: Correction: MetalSprockets does have a public depth-test modifier, Element.depthCompare(function:enabled:) (where 'enabled' means depth writes; filed MetalSprockets #531 on the naming). Only its full DepthState modifier is package-internal. So depth-testing particles needs no upstream change. The real upstream gap is reading the frame's depth: RenderViewContext does not expose the depth attachment and the MTKView depth texture is memoryless; filed MetalSprockets #530. Updated options: (A) wait for/implement MetalSprockets #530, or (B) in this project, keep our own view-sized depth texture with a collider depth pre-pass.
- `2026-10-18T15:36:09Z`: Unblocked: MetalSprockets main (1ee86220) closes #530 and #531. RenderViewContext.depthTexture exposes the frame depth, readable in a later pass when configured with .metalDepthStencilAttachmentTextureUsage([.renderTarget, .shaderRead]), .metalDepthStencilStorageMode(.private) and .metalDepthStoreAction(.store). depthCompare(function:enabled:) is now depthCompare(function:writes:). Package now tracks MetalSprockets main. Option A is available.
- `2026-10-18T16:04:08Z`: Done with a self-contained scene depth rather than RenderViewContext.depthTexture: ParticleSystem.renderSceneDepth(into: SceneDepth) draws colliders' depth into an r32Float texture the existing soft-particle shader reads, and renderColliderSolids draws them as shaded solids in the main pass. renderScene(projection:view:sceneDepth:wireframes:) composes both and is used by particles-render, video export, preset goldens, and the demo (RenderView now has a depth32Float attachment; Solid Colliders toggle). ParticlePreset.drawsColliders turns it on; new Fog preset shows it. Test colliderSolidsFeedSoftParticles; Fog golden, clip, poster. Not checked in the live app (not launched). RenderViewContext.depthTexture (MetalSprockets #530) is still useful for apps with their own scene geometry; using it directly would need the shader to read a depth2d texture.

---

## 69: Demo has no tracked object for objectEnters triggers

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:demo
created: 2026-10-18T13:34:41Z
updated: 2026-10-18T13:59:01Z
closed: 2026-10-18T13:59:01Z
+++

The objectEnters trigger (#34) needs app-supplied positions in ParticleSystem.trackedObjects, so no preset can show it. Add a tracked object to the demo (animated or draggable sphere drawn as a wireframe) and a preset trigger that fires when it enters a volume. Related: #34.

- `2026-10-18T13:59:01Z`: Presets can now describe tracked objects: ParticlePreset.trackedObjects ([name: EmitterMotion]) and trackedObjectPositions(at:). simulate gains trackedObjects: (like colliders:/transforms:). The demo, particles-render, and the preset golden test feed them each frame; debug wireframes draw tracked objects (green). New Dunk preset: tracked object 'ball' bounces through a pool; an objectEnters trigger bursts a splash each entry, and a local-space emitter on the same motion draws the ball. Saved effects include tracked objects. Golden added; demo test covers motion, saving, and preset switching.

---

## 70: Some emoji sprites are unused

+++
status: closed
priority: medium
kind: feature
labels: effort:xs, area:demo
created: 2026-10-18T13:34:41Z
updated: 2026-10-18T13:49:39Z
closed: 2026-10-18T13:49:39Z
+++

The clock-faces flipbook and the droplet and glowing-star emoji sprites (#40) are not used by any preset. Work them into presets (e.g. droplets in Pond or Geyser, glowing stars in Magic Trail, clock faces in a 'time warp' effect). Related: #40.

- `2026-10-18T13:49:39Z`: Droplet sprite: Pond's falling drops (billboarded so the point stays up; they were near-invisible dots). Clock-face flipbook and glowing star: new Time Warp preset (clocks ticking through the flipbook from random hours, orbiting a glowing-star core in a vortex). Goldens: Pond updated, Time Warp added; both reviewed.

---

## 71: Fast-spinning emitters emit in per-frame bursts

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
created: 2026-10-18T13:39:41Z
updated: 2026-10-18T14:03:49Z
closed: 2026-10-18T14:03:49Z
+++

Births within a step are spread along the emitter's path by interpolating only its position (previousEmitterOrigin). Rotation is not interpolated, so a fast-spinning emitter (e.g. a Catherine wheel, a spinning sword in the scene graph) emits each step's particles at that frame's angle, giving visible spokes/clumps. The emitter's angular velocity also never adds to particle velocity (inheritVelocity is linear only). Fix: pass the previous emitter transform and slerp rotation by birthAge in spawnParticle; add the tangential velocity (omega × r) to inherited velocity. Needed for MetalSprocketsSceneGraph animation.

- `2026-10-18T14:03:49Z`: Births now sweep back along the emitter's rotation over the step (axis-angle from the previous to current transform, shortest way, rigid transforms only), like position already did; velocity is rotated the same way, and inheritVelocity adds omega x offset. Non-rotating emitters keep the exact old expressions (bit-identical). Test fails before the fix: one frame's births spanned 0.0 rad of a 0.6 rad sweep; after, > 0.4 rad, and spin is inherited as ~36 units/s tangential at radius 1. Portal golden updated (its slow spin shifts spark births slightly; reviewed). Limits: over half a turn per step reads as the shorter way round; scaled/sheared transforms skip rotation interpolation.

---

## 72: Colliders ignore rotation speed and can be tunneled through

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:collision
created: 2026-10-18T13:39:41Z
updated: 2026-10-18T14:11:11Z
closed: 2026-10-18T14:11:11Z
+++

Collider velocity comes only from frame-to-frame translation (Collider.velocity(from:deltaTime:)), so a rotating box or capsule (paddle, fan blade) does not fling particles, and spinning boxes are explicitly zero. Collision is also discrete: a fast or thin collider can jump past a particle within one step and the particle passes through. Fix: derive angular velocity from rotation change and use point velocity (v + omega × r) at the contact; add a swept test (or substeps for colliders moving more than their thickness per step). Needed for animated scene-graph colliders.

- `2026-10-18T13:52:13Z`: Seen in practice while building the Awning preset (#66): an 8 cm thick box let falling sparks (~8 cm per step at 60 fps) pass through; the preset uses 30 cm as a workaround.
- `2026-10-18T14:11:11Z`: Rotation speed: Collider.motion(from:deltaTime:) derives angular velocity for boxes (rotation change) and capsules (direction change); contacts use the point velocity v + omega x (p - pivot), so spinning paddles fling particles (exactly v when not rotating). Tunneling: after the penetration tests, particles that ended outside a sphere, box, or capsule are swept from their start (shifted into the collider's current frame by its own motion) to their end; a crossing moves them to the entry point and applies the collision. Covers fast particles and fast-moving thin colliders; capsule sweep is an approximation (closest approach of the path to the axis); rotation during the step is not swept. Tests fail before the fix (paddle: no fling; thin box/capsule: particle ended at y = -2.29; rising thin box passed the particle). Golden rotated-box-and-capsule updated (some fast particles now hit the thin shapes; reviewed); bench unchanged in interleaved runs.

---

## 73: Mesh emitters can't follow morphing or skinned meshes

+++
status: closed
priority: high
kind: feature
labels: effort:m, area:simulation
created: 2026-10-18T13:39:42Z
updated: 2026-10-18T13:46:45Z
closed: 2026-10-18T13:46:45Z
+++

EmitterMesh is built once from a SwiftMesh mesh (CPU triangulation, area-weighted CDF, buffer upload). MetalSprocketsSceneGraph animates meshes with morph targets and skinning, producing a deformed MetalMesh vertex buffer each revision (skinned meshes already in world space). Re-creating EmitterMesh per frame costs CPU triangulation and new buffers. Fix: let EmitterMesh bind an external positions MTLBuffer (offset/stride/format from the deformed mesh's vertex descriptor) with fixed triangle indices, keeping the rest-pose area CDF (or recompute it on the GPU if stretching matters). Then a deforming mesh costs only a buffer binding per frame and later works with GPU deformation. Particles that stick to a moving surface are out of scope here.

- `2026-10-18T13:46:45Z`: EmitterMesh.setDeformedPositions(buffer, offset:, stride:) takes the deformed vertex buffer as is (packed float3 at offset + stride * vertex, e.g. the position attribute of the scene graph's deformed MetalMesh). Triangles are still chosen by rest-pose area, then placed on the deformed triangle via stored indices; vertex birth reads deformed positions too. Per frame it is just buffer bindings; rest path unchanged (goldens identical; interleaved bench shows no change). Caller must not overwrite a buffer while frames using it are in flight. Not done: recomputing areas for heavy stretching, particles sticking to a moving surface.

---

## 74: Integrate with MetalSprocketsSceneGraph

+++
status: open
priority: high
kind: task
labels: effort:m, area:tooling, deferred
created: 2026-10-18T13:39:42Z
updated: 2026-10-18T13:40:42Z
+++

This project is meant to replace MetalSprocketsSceneGraph's particle system (Sources/MetalSprocketsParticles there; scene integration in Particles.swift: node.particleSystems advanced per node with system.advance(by:emitterTransform:) and drawn by ParticleRenderer as depth-tested soft sprites). Check the API fit: per-node emitters vs one ParticleSystem with many emitters (apply/simulate(transforms:)), hidden nodes stopping emission, scene colliders and lights from nodes, depth for soft particles (render(sceneDepth:)), deformed meshes (see the deformed-mesh emitter issue), and draw order with transparent scene geometry. Output: an integration plan or a thin adapter in the scene graph, plus any API gaps filed here.

---

## 75: Emitters can't ramp emission over time or finish

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
created: 2026-10-18T14:44:28Z
updated: 2026-10-18T15:00:11Z
closed: 2026-10-18T15:00:11Z
+++

Emission is either infinite or an on/off square wave (emissionDuration, idleDuration, loops). There is no way to shape the number of particles an emitter generates over time (fade in, run, fade out), and no finite effect ever reports that it is done.

Proposal: ParticleEmitter.emissionOverTime: ParticleCurve<Float>, a multiplier on birthRate keyed in seconds since the emitter started (existing over-life curves are keyed 0...1 of a particle's life; this one uses seconds).
- .constant(1) (default) = today's infinite emitter.
- Example: keys (0 s, 1), (10 s, 1), (12 s, 0) runs full for 10 s, ramps to nothing by 12 s, and the effect lasts 12 s plus particle lifetimes.
- After the last key the last value holds; if it is 0 the emitter is done for good. Fade-ins too, e.g. (0 s, 0) -> (2 s, 1).
- The spawner integrates birthRate x envelope over each step (exact for piecewise-linear), so ramps are smooth and deterministic at any frame rate.
- Emitter.isFinished and ParticleSystem.isFinished: the envelope has ended at 0 and every particle has died. Lets the scene graph (#74) remove finite effects, and video export could optionally run until finished.
- Multiplies with emissionDuration/idleDuration/loops; an optional repeats on the envelope could later replace loops.
- Demo: an envelope editor in the Emission section (curve editor with time in seconds), and a preset that fades in and out.
- Saved effects include it (tolerant decoding keeps the default).

- `2026-10-18T15:00:11Z`: ParticleEmitter.emissionOverTime (ParticleCurve<Float> in seconds since start, default .constant(1)) multiplies birthRate; the spawner integrates it over each step (exact for straight segments; constant curves keep the old arithmetic, so goldens/determinism unchanged). Emitter.isFinished / ParticleSystem.isFinished: emission over (envelope ended at 0, single period over, zero rate, or not emitting), no pending burst or triggers, and every particle including sub-emitter children dead. exportVideo(stopWhenFinished:) returns the length written; particles-render --until-finished. Demo: Emission Over Time curve editor (seconds), HUD shows Finished. New Flare preset (ramps in 0.5 s, burns 3 s, out by 5 s; movie ends at ~8 s). repeats/loops replacement not done.

---

## 76: Built-in presets are Swift code instead of JSON resources

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:tooling
created: 2026-10-18T14:48:39Z
updated: 2026-10-18T15:04:45Z
closed: 2026-10-18T15:04:45Z
+++

All 26 presets live in Presets.swift as Swift code. Effects already round-trip through JSON (#25, meshes since #65), so the built-ins could be JSON files bundled as package resources and loaded at runtime, the same format users save and open.

Wins: presets editable without recompiling, one format for built-ins and user effects, the demo's Save Effect output can become a built-in directly, and Presets.swift (~1,300 lines) goes away.

Plan:
- Export every preset with particles-render --save-effect into Sources/MetalSprocketsParticles/Resources/Presets/<slug>.json (Bundle.module resources).
- ParticlePreset.all loads them (sorted by a stored order, or an index file); keep static accessors like .fireworks if useful, backed by the resources.
- Meshes: the Teapot stores triangulated positions inline (~1.4 MB pretty-printed). Consider compact JSON, or referencing a named mesh (e.g. 'teapot' resolved to SwiftMesh's bundled teapot) instead of embedding it.
- Some presets compute values in code (Galaxy arms by loop, Fireworks colors, shared ground collider); the JSON is the expanded result.
- Goldens must stay identical. Layer ids are stored in JSON; loading must keep them stable or fresh consistently.
- Decide: keep a Swift path for tests (fixtures) or load everything from resources.
- Related: #25, #32 (result builder), #65.

- `2026-10-18T15:04:45Z`: Built-in presets are now JSON resources: Sources/MetalSprocketsParticles/Resources/Presets/<slug>.json (exported with particles-render --save-effect) plus index.json for display order, bundled via Package.swift resources. ParticlePreset.all loads them once; named accessors (.fireworks, .teapot, ...) remain, backed by the resources. Presets.swift (1,176 lines) is deleted. All 27 preset goldens are unchanged (Teapot included, from the triangulated mesh in JSON). Not done: Teapot's mesh stays inline (~1.4 MB pretty JSON; a named-mesh reference or compact JSON would shrink it). The preset result builder (#32) stays as public API, but no built-in uses it now.
- `2026-10-18T15:05:25Z`: Note: teapot.json is stored as compact JSON (434 KB); pretty-printed it was 1.4 MB, over jj's 1 MiB new-file snapshot limit, and was silently left out of the first commit. Fixed by compacting it in the same commit.

---

## 77: Interactive particles: react to the camera and the mouse

+++
status: open
priority: medium
kind: feature
labels: area:demo, needs-design, effort:l
created: 2026-10-18T15:36:26Z
updated: 2026-10-18T15:44:07Z
+++

Particles can't react to the user. Let them respond to the camera and the pointer.

Ideas:
- Mouse: unproject the pointer into the scene (ray, or a point on a plane or depth). Use it as a moving force field (attract, repel, vortex), a moving collider, or an emitter position. Click to burst.
- Camera: particles react to the camera position, e.g. push away from the eye, fade or die near the near plane, or a force field that follows the camera.

Probably a library API (pointer ray or position in, as a tracked object or force field) plus demo wiring and a preset that shows it off. particles-render has no input, so test with scripted pointer paths.

Open questions: which interactions first, and whether the pointer is a ray or a point on a plane.

---

## 78: Demo rotating colliders

+++
status: closed
priority: low
kind: feature
labels: area:presets, effort:m
created: 2026-10-18T15:38:44Z
updated: 2026-10-18T16:55:50Z
closed: 2026-10-18T16:55:50Z
+++

Collider angular velocity and pivot (#72) are only shown in a golden test. Preset colliders can't rotate, and the demo's Animate Colliders toggle only moves them. Add a way for a preset to spin a collider (e.g. collider motion in JSON), and add a preset with a spinning paddle or box that flings particles.

- `2026-10-18T16:55:50Z`: Added ColliderSpin (collider index, axis, rad/s) and ParticlePreset.colliderSpins, applied in colliders(at:) and the demo's frameColliders; boxes and capsules turn about the same pivot the GPU uses for angular velocity. New Paddle Wheel preset: two solid spinning blades fling a stream of sand. Tests: colliderSpinsTurnBoxesAndCapsulesAboutTheirPivot, paddleWheelPresetSpinsItsBlades; golden, clip, poster. Known gap: spins refer to colliders by index, so removing a collider in the demo can shift them.

---

## 79: Demo a deforming mesh emitter

+++
status: closed
priority: low
kind: feature
labels: area:presets, effort:s
created: 2026-10-18T15:38:44Z
updated: 2026-10-18T16:11:13Z
closed: 2026-10-18T16:11:13Z
+++

EmitterMesh.setDeformedPositions (#73) is Swift API only, with no demo. Add a preset or demo mode where a mesh deforms over time (e.g. a waving flag or a breathing sphere) and particles emit from its surface.

- `2026-10-18T16:11:13Z`: Added MeshDeformation (none, wave(amplitude:wavelength:speed:)) on EmitterDescription and ParticleSystem.Emitter, saved in effect JSON. planFrame deforms the rest pose by the emitter's clock and feeds it through setDeformedPositions, cycling 4 buffers so in-flight frames keep theirs. New Flag preset: a 24x14 grid mesh waving next to a solid pole, sparks born on the moving surface. Tests: waveKeepsTheFixedEndAndBendsTheFreeEnd, systemAnimatesAMeshDeformationEachFrame; Flag golden, clip, poster.

---

## 80: Demo one-shot emitters

+++
status: closed
priority: low
kind: feature
labels: area:presets, effort:s
created: 2026-10-18T15:38:44Z
updated: 2026-10-18T16:13:32Z
closed: 2026-10-18T16:13:32Z
+++

No preset sets loops = false. Add a preset or a demo button for a one-shot effect, e.g. an explosion or a puff that plays once and finishes, and show the HUD 'Finished' state.

- `2026-10-18T15:44:08Z`: Related: #82 makes Confetti finite. Do #80 alongside #82: add loops=false support to a preset there or here.
- `2026-10-18T16:13:32Z`: Confetti now uses a one-shot emitter (emissionDuration 0.35, loops false) instead of an emission curve, so Flare shows the curve and Confetti shows the one-shot setting. Still finishes at about 8.4 s (confettiPresetFinishes passes). Golden, clip, poster, and comments updated.

---

## 81: Demo per-particle spin

+++
status: closed
priority: low
kind: feature
labels: area:presets, effort:s
created: 2026-10-18T15:38:44Z
updated: 2026-10-18T15:38:59Z
closed: 2026-10-18T15:38:59Z
+++

Only Magic Trail uses angularSpeed, and only subtly. Add a preset where spinning sprites are clearly visible, e.g. falling leaves or tumbling shards with spin variation.

- `2026-10-18T15:38:59Z`: Invalid: per-particle spin (angularSpeedVariation) is used by 9 presets; Confetti shows it clearly. The audit only checked angularSpeed.

---

## 82: Make Confetti a finite effect with a Restart button in the viewport

+++
status: closed
priority: medium
kind: feature
labels: area:presets, area:demo, effort:s
created: 2026-10-18T15:43:07Z
updated: 2026-10-18T15:53:13Z
closed: 2026-10-18T15:53:13Z
+++

Add a built-in preset that runs for a set time and then finishes. Confetti is a good fit: a party-popper burst that falls, settles on the ground, and fades. The system then reports isFinished.

Use emissionOverTime or loops = false (#80) so emission stops, and limit particle lifetimes so the effect ends.

The demo already has Restart in the inspector, and the HUD shows 'Finished'. Add a Restart button to the viewport, next to the Finished label, so a finite effect is easy to replay.

Related: #75 (Flare is finite too, but long and subtle), #80.

- `2026-10-18T15:53:13Z`: Confetti is now a party-popper burst: 0.35 s of emission (emissionOverTime), 6-8 s lifetimes with a fade-out, then the system reports isFinished (about 8.4 s). No separate viewport Restart button: #83 put Restart in the toolbar, next to the scene picker, so it is always visible. Golden, demo clip, and poster updated; test confettiPresetFinishes added.

---

## 83: Move scene controls to the toolbar

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:s
created: 2026-10-18T15:43:24Z
updated: 2026-10-18T15:45:32Z
closed: 2026-10-18T15:45:32Z
+++

The per-scene controls are in the inspector: the scene picker and play, pause, stop, restart and time. Move them to the window toolbar, in the .principal placement, so they stay visible and the inspector holds only emitter settings.

The viewport Restart button from #82 may then be unnecessary; decide when doing this.

Related: #82.

- `2026-10-18T15:45:33Z`: Preset picker, Play/Pause/Stop, Restart, Revert, and Speed moved to SceneToolbarView in the .principal toolbar item. The inspector's scene section (titled with the preset name) keeps the comment, Open/Save Effect, and Export Video. Not visually checked (demo app not launched); build and demo tests pass.

---

## 84: Add DocC documentation

+++
status: new
priority: medium
kind: documentation
labels: area:docs, effort:l
created: 2026-10-18T15:45:41Z
+++

The package has no DocC catalog, and many public symbols have no doc comments. Add DocC documentation.

Use MetalSprockets as the model for good DocC: its catalog layout, landing page, topic groups, articles, and tutorials (Sources/MetalSprockets/MetalSprockets.docc).

Scope:
- A MetalSprocketsParticles.docc catalog: a landing page, topic curation, and articles. Possible articles: getting started, presets and effect files, emitters and settings, colliders and force fields, sub-emitters and triggers, lighting and soft particles, performance.
- Doc comments on the public API, and fixes to the existing ones.

Rules: write in simple English (the simple-english skill), and follow the writing-comments and swift-documentation skills. The doc build must have no warnings.

---

## 85: Spike: how user Metal functions plug into the simulation

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:simulation, spike
created: 2026-10-18T17:06:25Z
updated: 2026-10-18T17:19:40Z
closed: 2026-10-18T17:19:40Z
+++

Part of #24. Choose how user-supplied Metal functions are linked into the particle kernels: visible function tables, function stitching, or compiling the kernel from source with the user function inserted. Check what MetalSprockets supports. Define the signature: which particle fields, uniforms, and user parameters the function sees, and what it may write. Measure the per-particle cost at 1M particles. Output: a short design note on #24, and sizes for the follow-up issues.

\- `2026-10-18T17:19:40Z`: Spike result (prototype in the working copy, not committed).

Linking: visible function table. The precompiled updateParticles kernel declares visible_function_table<ParticleUpdateFunction> userUpdate and calls userUpdate[0] when uniforms.hasUserUpdate is set. The user function lives in its own MTLLibrary compiled at runtime (device.makeLibrary(source:)) and is linked with MetalSprockets .linkedFunctions + .visibleFunctionTable. Cross-library linking works (test: a user function compiled from source sets velocity and overrides gravity). A built-in [[visible]] no-op fills the table when there is no user function, so the pipeline shape never changes. Rejected: recompiling the whole kernel from source (slow, ships shader source, harder errors) and function stitching (too limited for arbitrary code).

Signature: void f(thread ParticleState &, float deltaTime, float time, constant float4 *parameters). ParticleState is a small public ABI of plain Metal types (position, velocity, age, lifetime, id), declared in a prelude we prepend to user source, so user code needs no project headers and our internal Particle packing can change freely. Parameters are a float4 array set from Swift.

Cost (M5 Max, release, 1M particles, interleaved 3x against the pre-spike build): baseline 0.245-0.249 ms simulate; with the table bound and a user function doing real math 0.245-0.248 ms. No measurable cost.

Follow-ups: #86 update hook: as prototyped, called after forces and before collisions; API is a ParticleUpdateFunction type (source string or MTLFunction plus parameters) on the emitter, not the system, since each dispatch is per emitter. More state (color, size, kill) can be added to ParticleState. Size m (was l). #87 spawn hook: same table pattern, called after built-in spawn; m. #88 effect files: store the source string; compile on load and report compile errors; s. #89 events: same pattern, later.

---

## 86: User Metal function: per-step update hook

+++
status: open
priority: medium
kind: feature
labels: area:simulation, effort:m
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:19:40Z
+++

Part of #24; needs the design from #85. A user-supplied Metal function runs for each live particle every step, after the built-in forces and before collisions. It needs a Swift API to supply the function and its parameter buffer, tests, and a preset that uses it.

---

## 87: User Metal function: spawn hook

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:simulation
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:06:46Z
+++

Part of #24; needs the design from #85. A user-supplied Metal function sets up each newly born particle after the built-in spawn, e.g. custom positions, velocities, or colors.

---

## 88: Effect files with user Metal functions

+++
status: open
priority: medium
kind: feature
labels: effort:s, area:simulation
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:06:46Z
+++

Part of #24; needs the design from #85. Decide whether effect JSON can carry the Metal source or only a reference to a function the app supplies, and what happens when the function is missing (a clear error, or fall back to the built-in behavior).

---

## 89: User Metal functions for birth, death, and collision events

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:simulation
depends: 85
created: 2026-10-18T17:06:39Z
updated: 2026-10-18T17:06:46Z
+++

Part of #24; needs the design from #85. Call user functions when particles are born, die, or collide, built on the existing event counters. Lower priority than the update and spawn hooks.

---

## 90: Keep demo videos and posters in sync with the presets

+++
status: open
priority: medium
kind: task
labels: area:docs, effort:s
created: 2026-10-18T17:07:32Z
updated: 2026-10-18T17:07:41Z
+++

Documentation/Demos should have a video, a poster, and a README section for every built-in preset. Right now Flare has none: it was added after the clips were made, and new presets get their clips by hand.

Do:
- Add Flare's clip and poster (use --until-finished).
- Add a way to regenerate them all, e.g. a script or a particles-render option that writes the mp4, the poster, and the README section for every preset in index.json.
- Add a test that every preset in index.json has a video, a poster, and a README section, and that there are no extras (removed presets).

---

## 91: Change particles on collision: new color, or turn into another particle type

+++
status: new
priority: medium
kind: feature
labels: area:collision,needs-design
created: 2026-10-18T17:20:05Z
+++

Let a collision change a particle instead of only bouncing or dying. Examples: sparks turn red when they hit the ground, snow turns to slush, rain becomes a splash droplet, an ember becomes ash.

Today:
- diesOnCollision plus an onCollision sub-emitter can fake 'turn into another type': the particle dies and children spawn where it hit. But the child is a new particle with its own spawn settings; it does not keep the parent's velocity, age, or size, and there is a frame of lag.
- Nothing can change a living particle's color, size, or curves on collision.

Options to decide:
1. Built-in collision response settings on the emitter: e.g. a color tint or color-over-life switch after the first hit, a size factor, a lifetime change.
2. 'Transfer' to another emitter: on collision the particle moves into another emitter's slice (or is respawned there in the same step) keeping position, velocity, and optionally age. That emitter's sprite, curves, and settings then apply.
3. A user Metal function called on collision (#89) that can edit the particle state; needs color and size in ParticleState (see #85).

1 and 2 work in presets and the demo without code; 3 is the general escape hatch. Related: #46 (rain splashes), #89, #85.

---
