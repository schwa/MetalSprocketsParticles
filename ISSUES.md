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
status: closed
priority: medium
kind: feature
labels: effort:xl, area:collision, has-subtasks
depends: 149, 150, 151, 152
created: 2026-10-17T13:27:25Z
updated: 2026-10-19T20:38:52Z
closed: 2026-10-19T20:38:52Z
+++

Particles only collide with analytic shapes (plane, sphere, AABB). Real scenes need collision with mesh geometry, e.g. via a baked SDF volume or the scene depth buffer.

- `2026-10-17T14:02:37Z`: Doc review: SceneKit has colliderNodes (collide with node geometry). RealityKit ParticleEmitterComponent has no collision API at all, so this is a clear place to beat it.
- `2026-10-17T14:11:14Z`: Related: #3 (SDF colliders could share the mesh SDF path).
- `2026-10-17T15:54:23Z`: SDF volume colliders were split out of #3 and belong here: a baked 3D distance texture is the same collision path mesh colliders need. Scope now: Collider case for a 3D SDF texture + bounds/transform, kernel sampling with gradient normals, and baking from a mesh.
- `2026-10-17T19:34:40Z`: Main consumer: MetalSprocketsSceneGraph integration, where colliders come from scene-node geometry at runtime. Mesh/SDF colliders need to accept that geometry (and its transforms) per frame.
- `2026-10-17T21:05:19Z`: Mesh input should come from SwiftMesh (github.com/schwa/SwiftMesh), the mesh type used across the MetalSprockets ecosystem (MetalSprocketsAddOns depends on it). Mesh/SDF colliders should accept a SwiftMesh mesh plus transform, not raw arrays.
- `2026-10-17T21:05:19Z`: Related: #38 (SwiftMesh input for EmitterMesh); share the conversion.
- `2026-10-18T13:33:59Z`: Decision (user): skip for now.
- `2026-10-19T00:16:31Z`: Related: #120 (screen-space collision with the scene depth buffer covers on-screen geometry cheaply; mesh/SDF colliders cover the rest).
- `2026-10-19T15:23:09Z`: Un-deferred (user). The CPU geometry goes in SwiftMesh: #176 public Mesh bounds, #177 BVH, #178 closest point and distance, #179 winding-number inside test, #180 signed distance and baking an SDF grid. This issue keeps the GPU side: an SDF collider (3D texture, bounds, transform), sampling in the kernel, baking from a SwiftMesh mesh through #180, and per-frame transforms for scene-graph nodes.
- `2026-10-19T15:24:49Z`: Split into subtasks, in order: #149 SDF collider type, #150 collision in the kernel, #151 baking from SwiftMesh meshes (also needs SwiftMesh #180), #152 moving SDF colliders for scene-graph nodes.
- `2026-10-19T20:38:51Z`: Done through #149-#152: Collider.Shape.signedDistanceField (a SwiftMesh SignedDistanceField, saved in effect files), collision in the kernel with sub-stepping for fast particles, baking from SwiftMesh meshes (Collider.signedDistanceField(mesh:resolution:padding:...)), and moving or turning fields with Collider.placed(by:) for scene-graph nodes. Not done: scale in placed(by:) (bake at draw size), and more than eight distance field colliders at once.

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
status: closed
priority: medium
kind: feature
labels: effort:xl, area:simulation, tracking
created: 2026-10-17T14:01:52Z
updated: 2026-10-18T18:46:51Z
closed: 2026-10-18T18:46:51Z
+++

SceneKit lets callers attach event handlers (birth, death, collision) and per-frame modifier blocks at several simulation stages. A GPU system needs an equivalent, e.g. user-supplied Metal functions for spawn, update, or render, so effects can go beyond the built-in parameters.

- `2026-10-18T13:33:59Z`: Decision (user): functions. Custom per-particle behavior is user-supplied Metal functions called from the simulation kernel (e.g. visible functions or function constants/stitching via MetalSprockets), not Swift closures or a fixed set of built-in modifier stages. Next: split into a design spike for the function signature and linking, then implementation.
- `2026-10-18T17:06:39Z`: Split into #85 (spike, do first), #86 (update hook), #87 (spawn hook), #88 (effect files), and #89 (event hooks). A render-stage hook is left out until needed.
- `2026-10-18T18:46:51Z`: Done via #85 (spike), #86 (update), #87 (spawn), #88 (effect files), #89 (collision and death). Open follow-up: color/size in ParticleState (#91).

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
status: closed
priority: low
kind: task
labels: effort:m, area:rendering, deferred
created: 2026-10-18T01:45:02Z
updated: 2026-10-19T19:00:46Z
closed: 2026-10-19T19:00:46Z
+++

Debug wireframes (DebugWireframes.swift, ColliderWireframe.swift) use a hand-rolled WireframeBuilder and a custom line-list RenderPipeline (wireframeVertex/wireframeFragment), one flat color per kind.

Evaluate replacing this with Canvas3D. Possible wins: less custom shader/pipeline code, shared look with other MetalSprockets tools, and features we lack (line width, depth fade, labels).

Check first: dependency weight for the library target (maybe keep wireframes in an optional target), and that it fits inside a RenderPass the same way renderWireframes does now. Keep the particles-render --wireframes flag and the demo toggle working.

- `2026-10-18T12:40:25Z`: Triaged: Low, task, effort:m, area:rendering.
- `2026-10-18T13:22:11Z`: Looked for Canvas3D to evaluate it: no Swift source mentions it under ~/Shared/Projects or ~/Projects (MetalSprockets, AddOns, all .build checkouts), in DerivedData, or in a GitHub code search of schwa's repos. Punting: can't judge dependency weight or RenderPass fit without its API. Where does Canvas3D live (package/repo/branch)? Meanwhile the current wireframes are small (WireframeBuilder + one flat-color line pipeline, ~300 lines) and work in particles-render --wireframes and the demo.
- `2026-10-18T18:50:43Z`: Decision (user): defer. Canvas3D lives in MetalSprocketsAddOns.

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
status: closed
priority: low
kind: task
labels: effort:s, area:demo, deferred
created: 2026-10-18T12:36:57Z
updated: 2026-10-19T15:20:18Z
closed: 2026-10-19T15:20:18Z
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
status: closed
priority: high
kind: task
labels: effort:m, area:tooling, deferred
created: 2026-10-18T13:39:42Z
updated: 2026-10-18T18:50:43Z
closed: 2026-10-18T18:50:43Z
+++

This project is meant to replace MetalSprocketsSceneGraph's particle system (Sources/MetalSprocketsParticles there; scene integration in Particles.swift: node.particleSystems advanced per node with system.advance(by:emitterTransform:) and drawn by ParticleRenderer as depth-tested soft sprites). Check the API fit: per-node emitters vs one ParticleSystem with many emitters (apply/simulate(transforms:)), hidden nodes stopping emission, scene colliders and lights from nodes, depth for soft particles (render(sceneDepth:)), deformed meshes (see the deformed-mesh emitter issue), and draw order with transparent scene geometry. Output: an integration plan or a thin adapter in the scene graph, plus any API gaps filed here.

- `2026-10-18T18:50:43Z`: Decision (user): not this project's job; MetalSprocketsSceneGraph will integrate this library. Here we only keep the API easy to integrate (per-node emitters, scene colliders and lights, depth for soft particles, deformed meshes).

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
status: closed
priority: medium
kind: feature
labels: area:demo, effort:l
created: 2026-10-18T15:36:26Z
updated: 2026-10-18T19:06:22Z
closed: 2026-10-18T19:06:22Z
+++

Particles can't react to the user. Let them respond to the camera and the pointer.

Ideas:
- Mouse: unproject the pointer into the scene (ray, or a point on a plane or depth). Use it as a moving force field (attract, repel, vortex), a moving collider, or an emitter position. Click to burst.
- Camera: particles react to the camera position, e.g. push away from the eye, fade or die near the near plane, or a force field that follows the camera.

Probably a library API (pointer ray or position in, as a tracked object or force field) plus demo wiring and a preset that shows it off. particles-render has no input, so test with scripted pointer paths.

Open questions: which interactions first, and whether the pointer is a ray or a point on a plane.

- `2026-10-18T18:50:43Z`: Decision (user): bind force fields, colliders, or emitters to the mouse; that is enough for now. Camera reactions later.
- `2026-10-18T19:06:22Z`: Pointer bindings: PointerBinding (collider, forceField, emitter by index) on ParticlePreset.pointerBindings, with pointerMotion standing in for the mouse in renders, videos, and goldens. ParticlePreset.colliders(at:pointer:), forceFields(at:pointer:), transforms(at:pointer:); PointerProjection.worldPosition projects a view point onto the plane through the camera target. Demo: hover drives the pointer (falls back to pointerMotion off the view); Follow Pointer toggles on colliders, force fields, and emitters, stored by item id so removals do not shift them. New Pointer Stir preset (vortex and ball follow the pointer). Camera reactions and click-to-burst are left for later. Tests: projection, bindings, pointerMotion fallback, JSON; demo load/save/removal. Not checked live (app not launched).

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
status: open
priority: medium
kind: documentation
labels: area:docs, effort:l, deferred
created: 2026-10-18T15:45:41Z
updated: 2026-10-18T21:57:36Z
+++

The package has no DocC catalog, and many public symbols have no doc comments. Add DocC documentation.

Use MetalSprockets as the model for good DocC: its catalog layout, landing page, topic groups, articles, and tutorials (Sources/MetalSprockets/MetalSprockets.docc).

Scope:
- A MetalSprocketsParticles.docc catalog: a landing page, topic curation, and articles. Possible articles: getting started, presets and effect files, emitters and settings, colliders and force fields, sub-emitters and triggers, lighting and soft particles, performance.
- Doc comments on the public API, and fixes to the existing ones.

Rules: write in simple English (the simple-english skill), and follow the writing-comments and swift-documentation skills. The doc build must have no warnings.

- `2026-10-18T21:57:36Z`: Deferred (user): docs wait until the project is close to final.

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
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:29:00Z
closed: 2026-10-18T17:29:00Z
+++

Part of #24; needs the design from #85. A user-supplied Metal function runs for each live particle every step, after the built-in forces and before collisions. It needs a Swift API to supply the function and its parameter buffer, tests, and a preset that uses it.

- `2026-10-18T17:29:00Z`: ParticleEmitter.updateFunction: ParticleFunction (Metal source, visible function name, float4 parameters), Codable. Compiled once per source+name after ParticleFunction.prelude (public; declares ParticleState) and cached on the system; bound per dispatch through the kernel's visible function table, with a built-in no-op otherwise. Called after gravity, fields, and drag, before collisions. Compile errors throw from simulate. Replaced the spike-only system API. Tests: per-emitter scope, parameters, compile error, JSON round trip. New Strange Attractor preset (Lorenz system); golden, clip, poster.

---

## 87: User Metal function: spawn hook

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:31:56Z
closed: 2026-10-18T17:31:56Z
+++

Part of #24; needs the design from #85. A user-supplied Metal function sets up each newly born particle after the built-in spawn, e.g. custom positions, velocities, or colors.

- `2026-10-18T17:31:56Z`: ParticleEmitter.spawnFunction (ParticleFunction, Codable): called once per new particle after the built-in spawn, in world space with deltaTime 0; may change position, velocity, and lifetime. Second visible function table in the kernel with its own built-in no-op (linking one function twice into a pipeline fails with 'duplicated symbol', so an emitter using the same function for spawn and update links it once). Sub-emitter children are not passed through it (documented). Tests: ring placement and lifetime, spawn+update together, same function in both slots, JSON round trip. No preset: the issue asks for none, and color is not in ParticleState yet.

---

## 88: Effect files with user Metal functions

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:simulation
depends: 85
created: 2026-10-18T17:06:38Z
updated: 2026-10-18T17:35:06Z
closed: 2026-10-18T17:35:06Z
+++

Part of #24; needs the design from #85. Decide whether effect JSON can carry the Metal source or only a reference to a function the app supplies, and what happens when the function is missing (a clear error, or fall back to the built-in behavior).

- `2026-10-18T17:35:06Z`: Effect files carry the Metal source (ParticleFunction is part of the emitter settings since #86). Errors: ParticleFunctionError (name, compiler message; missing or non-[[visible]] names report 'no [[visible]] function'). ParticlePreset.validateFunctions(device:) and ParticleFunction.validate(device:) check without a system; ParticleSystem.load compiles every function up front (compileFunctions), so particles-render --effect fails on load; the demo validates before opening an effect, so a bad file shows the existing error alert and the current scene keeps running. Missing functions are an error, not a silent fallback. Tests: compile error by name, missing and non-visible names, sub-emitter functions, effect file round trip with Strange Attractor.

---

## 89: User Metal functions for birth, death, and collision events

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:simulation
depends: 85
created: 2026-10-18T17:06:39Z
updated: 2026-10-18T17:40:24Z
closed: 2026-10-18T17:40:24Z
+++

Part of #24; needs the design from #85. Call user functions when particles are born, die, or collide, built on the existing event counters. Lower priority than the update and spawn hooks.

- `2026-10-18T17:40:24Z`: Birth is covered by spawnFunction (#87). Added collisionFunction (runs when a particle hits a collider this step, after the bounce) and deathFunction (runs on the step age reaches lifetime, before on-death sub-emitters). Both may change position, velocity, age, and lifetime: setting age to lifetime kills; raising lifetime in a death function keeps the particle alive. Collision runs first, so it can kill and trigger the death function. Refactored the four hooks into ParticleFunctionSlot (table, parameters, built-in no-op per slot) and FunctionTables (each distinct function linked once). 1M simulate still 0.242-0.244 ms. Tests: stick instead of bounce, kill on contact, respawn via death, death runs once, JSON round trip.

---

## 90: Keep demo videos and posters in sync with the presets

+++
status: closed
priority: medium
kind: task
labels: area:docs, effort:s
created: 2026-10-18T17:07:32Z
updated: 2026-10-18T18:54:42Z
closed: 2026-10-18T18:54:42Z
+++

Documentation/Demos should have a video, a poster, and a README section for every built-in preset. Right now Flare has none: it was added after the clips were made, and new presets get their clips by hand.

Do:
- Add Flare's clip and poster (use --until-finished).
- Add a way to regenerate them all, e.g. a script or a particles-render option that writes the mp4, the poster, and the README section for every preset in index.json.
- Add a test that every preset in index.json has a video, a poster, and a README section, and that there are no extras (removed presets).

- `2026-10-18T18:54:43Z`: Added Flare's clip and poster. New Scripts/make-demos.sh [slug...]: renders clips (6 s, or until finished for confetti and flare, max 15 s) and middle-frame posters, and rewrites Documentation/Demos/README.md from index.json and the preset comments (now the single source for those descriptions). Uses PARTICLES_RENDER if set, else swift build. New test DemoDocumentationTests: clips and posters match index.json exactly and each preset has a README section; fails when Flare's poster is removed.

---

## 91: Particle transitions: turn into another particle type on an event

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:l
created: 2026-10-18T17:20:05Z
updated: 2026-10-18T19:14:52Z
closed: 2026-10-18T19:14:52Z
+++

Let a particle become a different particle type (move to another emitter) when something happens, keeping its position and velocity (and optionally age). The new emitter's sprite, curves, color, size, and settings then apply. A color change is just a transition to an emitter with a different color.

Events: on collision, after a time (age), on death, on entering a trigger volume, and possibly on a user function's request.

Today the closest is diesOnCollision plus an onCollision sub-emitter, which spawns new particles a frame late and loses the parent's motion.

Design notes: transitions are set on the source emitter (event, target emitter, what to keep). The target needs free slots, like sub-emitter children. Should work in presets and the demo without code. Related: #46, #89.

- `2026-10-18T19:14:53Z`: Built on sub-emitters, which already spawn children the same frame at the parent's position with a share of its velocity. Added SubEmitter.replacesParent (the parent dies when it spawns children, so it turns into them), the .atAge(seconds:) occasion, a per-sub-emitter sprite (children were always soft dots), and SubEmitter.transition(on:into:sprite:) (one child, full velocity, replaces the parent). Events covered: collision, age, death (onDeath), birth. Not done: trigger-volume transitions, and keeping the parent's age (children start at age 0). Demo sub-emitter editor: At Age occasion, Replaces Parent, Sprite. New Embers to Ash preset. Tests: age transition keeps position and velocity, collision transition and child sprite, Codable round trip and old files without the new keys.

---

## 92: Docs should not refer to xcb

+++
status: closed
priority: medium
kind: documentation
labels: area:docs, effort:xs
created: 2026-10-18T17:22:24Z
updated: 2026-10-18T18:51:33Z
closed: 2026-10-18T18:51:33Z
+++

README.md and Documentation/METHODOLOGY.md mention xcb, a personal tool. Replace with standard xcodebuild/swift commands.

- `2026-10-18T18:51:33Z`: README uses swift run -c release particles-render; METHODOLOGY describes the build wrapper generically. Docs only; not built. The swift run commands were not run here (this workspace builds through the wrapper).

---

## 93: Move DEVELOPMENT_TEAM out of xcodeproj into gitignored Local.xcconfig

+++
status: closed
priority: medium
kind: task
labels: deferred, area:tooling, effort:xs
created: 2026-10-18T19:03:42Z
updated: 2026-10-19T19:00:50Z
closed: 2026-10-19T19:00:50Z
+++

The demo xcodeproj has the developer team ID hardcoded in project.pbxproj. Other people must edit it to build.

Fix:
- Remove DEVELOPMENT_TEAM from project.pbxproj.
- Add a committed Config/Base.xcconfig with an empty DEVELOPMENT_TEAM and a BUNDLE_ID_PREFIX, ending with: #include? "Local.xcconfig"
- Add a gitignored Config/Local.xcconfig that sets the real team and bundle prefix.
- Set Base.xcconfig as the base configuration for Debug and Release.
- Set PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID_PREFIX).<name>.

Done when a fresh clone builds on macOS with no project edits.

- `2026-10-18T19:33:13Z`: Deferred (user).

---

## 94: Chained transitions: sub-emitter children with their own sub-emitters

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:l
created: 2026-10-18T19:16:57Z
updated: 2026-10-18T19:45:20Z
closed: 2026-10-18T19:45:20Z
+++

Sub-emitter children ignore their own subEmitters, so a particle can transition only once (ember -> ash, but not ember -> ash -> dust). Support nested sub-emitters, at least a few levels deep. Each level needs its own child slices (capacity multiplies per level, so cap the depth or the count), and the dispatch order must run each level after its parent. Related: #91.

- `2026-10-18T19:45:21Z`: Sub-emitter children now get their own sub-emitter instances, built level by level (so each level dispatches after its parents and first-level seeds are unchanged; goldens unchanged), up to ParticleSystem.maxSubEmitterDepth = 3 levels; deeper ones are ignored. Capacity multiplies per level (documented). The layout fingerprint is now recursive, so nested edits rebuild. Embers to Ash gains a third stage: landed ash turns into a dust puff. Gap: the demo outline/inspector only edits first-level sub-emitters. Tests: two-step chain keeps velocity, depth cap, nested edit rebuilds.

---

## 95: Transitions can keep the parent's age

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:s
created: 2026-10-18T19:16:57Z
updated: 2026-10-18T19:37:00Z
closed: 2026-10-18T19:37:00Z
+++

A transition child (SubEmitter.transition / replacesParent) always starts at age 0. Add an option to carry over the parent's age (and maybe its remaining lifetime), so a change of look does not restart the particle's over-life curves or lifetime. Related: #91.

- `2026-10-18T19:37:00Z`: SubEmitter.continuesParentLife (and transition(..., continuesLife:)): children take the parent's age and lifetime, so over-life curves continue and the child dies when the parent would have. Carrying only the age was rejected: a short-lived child would die at once. Demo toggle. Test: fresh vs continuing child ages and lifetimes.

---

## 96: Transition when a particle enters a trigger volume

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:s
created: 2026-10-18T19:16:57Z
updated: 2026-10-18T19:40:08Z
closed: 2026-10-18T19:40:08Z
+++

Sub-emitter occasions cover birth, death, collision, while alive, and age, but not entering a trigger volume. Add an occasion that fires when a particle enters a given TriggerVolume (the kernel already detects entries for trigger counters), so a particle can change type when it crosses a region. Related: #91, #34.

- `2026-10-18T19:40:08Z`: New SubEmitter.Occasion.onEntering(TriggerVolume): fires when the parent moves from outside to inside the volume during a step (same test the trigger counters use). The volume is carried in the occasion (world space) rather than referring to a trigger, since trigger volumes are derived from triggers and have no stable index. Works with transition(...). Demo: On Entering Volume with the volume editor. Tests: crossing particles transition, a missed volume does not, Codable.

---

## 97: ParticleView: a standalone SwiftUI view for particle effects

+++
status: closed
priority: medium
kind: feature
labels: area:api, effort:m
created: 2026-10-18T19:25:35Z
updated: 2026-10-18T19:55:54Z
closed: 2026-10-18T19:55:54Z
+++

Add a SwiftUI ParticleView that shows an effect with no MetalSprockets setup: no RenderView, render passes, simulate/render calls, or camera matrices.

Possible API:
    ParticleView(preset: .campfire)
    ParticleView(effect: url)
    ParticleView(system: mySystem)

It should handle the device, the frame loop (pause when off screen), the camera (the preset's camera; optionally orbit or fixed), a transparent or colored background, resizing, and collider solids and soft particles when the preset asks for them. Modifiers or parameters could cover playback (paused, speed, restart), events (send a trigger event), and the pointer (follow the mouse or touch, see #77).

Questions:
- Does it live in the main library or in a small UI target, so the core does not depend on SwiftUI or MetalSprocketsUI?
- Is it 3D only, or should there be a 2D overlay mode (particles in view space, for UI effects like confetti over an app)?
- iOS too? The iOS build is currently blocked inside MetalSprockets (Metal 4).

The demo app could then use ParticleView for simple cases, which also tests it.

- `2026-10-18T19:55:54Z`: ParticleView in a new MetalSprocketsParticlesUI library product (core stays UI-free), built on MetalSprockets RenderView. ParticleView(_ preset:seed:) owns its system and reloads when the preset name changes; ParticleView(system:preset:) shows a caller-owned system (playback, restart, events stay with the caller). Uses the preset's camera (.camera(eye:target:) overrides), solid colliders and soft particles when drawsColliders, animated and spun colliders, tracked objects, and pointer bindings driven by mouse hover. Decisions (user): UI product, RenderView-based, 3D only (2D overlay is #99). Tests cover the per-frame state (loading and reloading, caller system, scene depth, pointer); the view itself was not checked on screen. README usage shows ParticleView first.

---

## 98: Immersive (Vision Pro) support

+++
status: open
priority: medium
kind: feature
labels: area:rendering, needs-design, deferred
created: 2026-10-18T19:29:44Z
updated: 2026-10-18T19:32:51Z
+++

Show particle effects in a visionOS immersive space, using MetalSprockets' immersive support.

How MetalSprockets does it (MetalSprocketsUI/VisionOS): ImmersiveRenderContent { context in ... } in an ImmersiveSpace runs the CompositorServices render loop with ARKit world tracking. ImmersiveRenderPass(context:) wraps a render pass set up for stereo, with optional progressive (stencil) rendering. ImmersiveContext gives viewCount, viewports, and per-eye viewMatrix(eye:) and projectionMatrix(eye:). The example (Example/.../ImmersiveCubeElement.swift) draws both eyes in one draw call with vertex amplification: setVertexAmplificationCount with view mappings, setViewports, and maxVertexAmplificationCount on the pipeline descriptor; the shader picks the eye's camera by [[amplification_id]].

What this project needs:
- Rendering: render(projection:view:) takes one camera. Add a stereo path: per-eye view and projection in the render uniforms, vertex amplification in particleVertex (billboards must face each eye, or a shared center-eye orientation), and the pipeline's maxVertexAmplificationCount. Sorting uses one view; sort by the center eye.
- Simulation is camera-independent except the sort view; it can run once per frame as now.
- Soft particles and collider solids need the stereo depth (layered or per-eye) or must be off at first.
- World scale: presets are in meters already; place the effect with an emitter or system transform.
- Interaction: hand or gaze positions can drive pointer bindings (#77) or tracked objects.
- A visionOS demo target with an ImmersiveSpace, and maybe ParticleView (#97) gets an immersive variant.

Blocker to check: the iOS simulator build fails inside MetalSprockets (no Metal 4); visionOS may have the same problem. Needs a device or a fix upstream.

- `2026-10-18T19:32:51Z`: Deferred (user): no Vision Pro hardware this week.

---

## 99: 2D overlays with ParticleView

+++
status: closed
priority: medium
kind: feature
labels: area:api, effort:l
created: 2026-10-18T19:51:12Z
updated: 2026-10-18T22:12:20Z
closed: 2026-10-18T22:12:20Z
+++

Particles over an app's normal UI: confetti over a window, sparkles on a button, a burst where the user taps. No special view: a ParticleView placed with SwiftUI's own tools.

    content.overlay {
        ParticleView(confetti)
            .camera(.overlay)
            .allowsHitTesting(false)
    }

Decisions:
- No 2D particle type. 2D is the 3D simulation seen through an orthographic camera.
- ParticleView is transparent by default (clear color alpha 0 over a non-opaque layer), so it composites over SwiftUI content. A background is a SwiftUI .background.
- An overlay camera: one world unit is one point, origin at the view's top left, y down (matching SwiftUI), so a tap location is a world position. Gravity down the screen is +y.
- Constraining particles to the z = 0 plane is a separate emitter setting (#107), useful in 3D too.
- 3D-only features (lighting, soft particles, sorting) stay; unused in 2D.

Steps:
1. Transparent ParticleView by default. (done with the camera)
2. ParticleView camera option: the system's camera, look-at, or overlay.
3. runtime.burst(at:) (or emitter transform helper) for bursts at a point.
4. Helpers: a view's frame as a box collider, the view's edges as four planes.
5. 2D samples (confetti cannon, sparkles, tap bursts) and a demo screen.

Related: #97, #107.

- `2026-10-18T22:12:20Z`: Steps 3-5 done. Emitter.burst(_:at:) and ParticleSystemRuntime.burst(_:at:): each positioned burst is its own zero-length spawn step at the point, so per-frame transforms (as ParticleView passes) cannot overwrite it; the shape keeps its offset from the moved origin; bursts wait while paused and keep the emitter unfinished. Collider.box(frame:depth:), Collider.edges(of:), Collider.floor(of:) in overlay coordinates. Demo: a '2D Overlay' window (toolbar button) with SwiftUI content under a transparent ParticleView using the overlay camera; the button fires confetti that bounces off it and lands on the window's bottom edge, clicking anywhere bursts sparkles. The 2D effects are built in code in the demo, not sample presets, because a ParticleSystem stores a camera position but not a camera kind, so particles-render and the goldens would show them wrong; a camera kind on ParticleSystem would fix that if wanted. Tests: positioned bursts, transforms passed each frame, paused bursts, edges, frame box, demo effects. Not checked on screen.

---

## 100: A first-class, document-based particle system editor

+++
status: open
priority: medium
kind: feature
labels: area:editor, effort:xl, needs-design, deferred
created: 2026-10-18T19:51:12Z
updated: 2026-10-18T21:58:31Z
+++

Replace the demo's debug-style inspector with a real editor app for particle systems. It should be something an artist or developer would choose to use, not a test harness.

Direction:
- Document-based: each document is one particle system (the JSON effect file), opened, saved, and versioned like any other document (SwiftUI DocumentGroup, undo/redo, autosave, recent files, Save As, duplicate). Samples open as untitled copies.
- A real UI instead of long inspector forms: a structure view (emitters, sub-emitters at any depth, colliders, force fields, lights, triggers, tracked objects), focused editors per item, curve and gradient editors, and direct manipulation in the viewport (move and resize emitters, colliders, fields, and volumes with handles).
- Viewport: camera controls, playback timeline (play, pause, scrub, restart, speed, loop, finite effects), stats, wireframe and solid collider toggles, background and lighting options, pointer bindings.
- Editing user Metal functions (update, spawn, collision, death) with error display.
- Export: effect files, images, videos.

Decisions (draft):

Open questions, with recommendations:
- Name: "Particle Editor" for now (target ParticleEditor, package ParticleEditorKit). Pick a product name before anything ships; nothing in the design depends on it.
- Repo: stays in this repo, under Apps/ParticleEditor, replacing Demos/MetalSprocketsParticlesDemo. The library API is still moving (#101, #103, #104), and the editor is its main client; one repo keeps changes atomic. Revisit when the library has a release.
- Platforms: macOS first and polished. iPadOS second: the same package must build for iOS from the start (DocumentGroup works there), but touch gizmos and layout come later. No iPhone or visionOS editor; ParticleView covers viewing there.
- ParticleView and the editor viewport share the player (#103), not the view. Both are thin layers over one player that owns the frame loop. The viewport adds an interactive camera, overlays, gizmos, and stats; ParticleView adds nothing an app would not want.
- What survives from the demo: the outline (as the start of the structure view), the small controls in InspectorControls, the event and trigger adapters, and their tests. The long inspector forms (EmitterInspectorView, ParticleEmitter+Inspector), the preset picker, and ParticlesDemoModel's mirrored state do not. The demo is removed once the editor reaches parity (#119).

Document model:
- The document is a ParticleSystem value. It is the only copy of the description; the runtime is derived from it (#104), and the editor keeps no mirrored item lists (no ColliderItem/ForceFieldItem, no didSet sync).
- EffectDocument is a ReferenceFileDocument (an @Observable class holding `system: ParticleSystem`) so edits go through one place: `edit(_ actionName:, _ change: (inout ParticleSystem) -> Void)`, which registers undo with the document's UndoManager. Continuous edits (slider drags, gizmo drags, curve point drags) coalesce into one undo step between begin and end. Snapshots are the value, so saving is cheap and off the main actor.
- Every item has a stable id (#108): emitters already do; colliders, force fields, lights, sub-emitters, and triggers get one, saved in the file and generated when missing. Pointer bindings refer to ids. Selection, undo, gizmos, and runtime diffing all key on ids instead of indices.
- File format: plain JSON, still diffable and versionable in git. A declared UTType ("Particle Effect", conforming to public.json, extension .particles); .json files still open. Add a format version field. When custom sprite images arrive, move to a package (a folder with effect.json and images); until then, a single file.
- Not in the document: playback time, interactive camera, selection, viewport toggles, inspector state. Those are per window (SceneStorage where it makes sense). The document's suggested camera is set by an explicit "Use Current View as Default Camera" command.
- Per-frame inputs (pointer, animated and spinning colliders, tracked object motion) are computed by the player from the description each frame and never written back.

Architecture:
- MetalSprocketsParticles: ParticleSystem, runtime, player (#103), apply(system) (#104). No editor API (#105).
- ParticleEditorKit (Swift package in Apps/ParticleEditor/Packages): EffectDocument, edit and undo, selection, structure view, item editors, curve and gradient editors, viewport, gizmos, function editor, export. Takes over ParticleKind and the demo's inspector adapters (#105). Everything here is testable without the app.
- ParticleEditor (app target): DocumentGroup, commands and menus, the welcome window with samples, settings. Thin.
- Data flow: views read `document.system`; every change goes through `edit`; the player is told `apply(document.system)` after each change and keeps particles when only settings changed. Gizmos and inspectors use the same edit path, so direct manipulation is undoable like any other change.
- Selection: a set of item paths built from ids (emitter, sub-emitter by id chain at any depth, trigger, collider, force field, light, tracked object by name). The inspector edits a single selection; multi-selection supports delete, duplicate, and toggling.
- Window layout: structure view (leading sidebar), viewport with timeline below (center), item editor (trailing inspector). Function editing opens in a larger sheet or a separate tab within the inspector area, not inline in a form.

Phases:
- M1, replaces the demo: #108, #109, #110, #111, #112, #113, #115, then #119.
- M2, the real editor: #114, #116, #117, #118.
- Depends on #103 and #104 for #111; #105 lands with #113.

Sub-issues: #108 stable ids, #109 app and package skeleton, #110 document and undo, #111 viewport, #112 structure view, #113 item editors, #114 curve and gradient editors, #115 playback timeline, #116 gizmos, #117 function editor, #118 export, #119 retire the demo.

Related: #97 (ParticleView), #101 (rename, done), #103, #104, #105.

- `2026-10-18T21:58:31Z`: Deferred (user).
- `2026-10-19T21:40:28Z`: Related: #159-#168 add inspector controls for settings the demo cannot edit yet, one area at a time; they are steps toward this editor, not a replacement.

---

## 101: Rename ParticlePreset to ParticleSystem, and ParticleSystem to ParticleSystemRuntime

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
created: 2026-10-18T20:17:34Z
updated: 2026-10-18T20:50:09Z
closed: 2026-10-18T20:50:09Z
+++

ParticlePreset is the type for a whole effect (emitters, colliders, force fields, lights, camera), but 'preset' suggests a fixed built-in starting point. Most uses are not presets: effects built in code, loaded from effect files, edited in the demo, passed to ParticleView. The docs already call them effects ('effect files', 'Get an effect').

Candidates:
- ParticleEffect (recommended): matches 'effect file' and the README wording; ParticleView(effect).
- ParticleScene: but it is not a full scene (no geometry beyond colliders).
- ParticleSetup or ParticleConfiguration: accurate but bland.

Scope: the type and its nested Layer alias, file names (ParticlePreset.swift, PresetBuilder.swift, PresetFolder.swift, SamplePresets.swift), APIs with 'preset' in them (presets(in:), ParticlePresetBuilder, PresetComponent, ParticleSystem.load(_:), ParticleView(_:)), the demo (presetName, preset picker labels), CLI flags (--preset, --list-presets, --presets), tests, README, and docs. The JSON format has no type name, so effect files keep working. 'Sample presets' can stay as the name of the samples library's contents.

- `2026-10-18T20:19:46Z`: Decision (user): ParticleSystem is the public name for the effect description (today's ParticlePreset), as in SceneKit's SCNParticleSystem. The runtime (today's ParticleSystem: GPU buffers, simulate, render) becomes ParticleSystemRuntime. Rename the related APIs to match (e.g. ParticleSystemRuntime.load(_:), ParticleView(_ system:), presets(in:) -> systems(in:) or similar). 'Sample presets' can stay as the samples library's wording.
- `2026-10-18T20:50:09Z`: Done: ParticlePreset -> ParticleSystem (the description), ParticleSystem -> ParticleSystemRuntime (GPU state, simulate, render), ParticlePresetBuilder -> ParticleSystemBuilder, PresetComponent -> ParticleSystemComponent, presets(in:) -> systems(in:), ParticleView(system:preset:) -> ParticleView(runtime:system:), files renamed to match. Mechanical part done with sed across 73 files, then API names and comments by hand. The samples library keeps 'presets' wording (MetalSprocketsParticlesSamples, SamplePresets.swift, .campfire). Effect JSON is unchanged. Demo internals (presetName etc.) still say preset; that is UI wording for picking a sample.

---

## 102: Video export tests occasionally hang

+++
status: closed
priority: medium
kind: bug
labels: area:tooling, effort:s
created: 2026-10-18T20:49:53Z
updated: 2026-10-19T11:52:19Z
closed: 2026-10-19T11:52:19Z
+++

A full library test run hung for 10 minutes (killed by the timeout) and passed in 18 seconds when re-run. A sample of the stuck test process showed nothing working: the main thread idle in its run loop, and AVFoundation's video compression and QuickTime writer threads waiting on semaphores. My guess is that a video export test (VideoExportTests, which uses MetalSprockets' OffscreenVideoRenderer) awaits a completion that never arrives, such as the writer's finish callback or a GPU completion handler. Not confirmed; seen once so far. Next time, sample the process and look for the awaiting task. Consider a timeout inside the video tests so a hang fails instead of stalling the run.

- `2026-10-18T23:06:20Z`: Could not reproduce: 40 runs of VideoExportTests alone and 15 full library runs, no hangs. Best guess if it recurs: MetalSprockets VideoFrameWriter.waitUntilReady awaits AVAssetWriterInput.isReadyForMoreMediaData with no timeout and no check of the writer's status; if the writer fails, the flag stays false and the wait never resumes (matches the idle sample: test task suspended, AVFoundation threads waiting). If it happens again: sample the stuck test process, check assetWriter.status, and consider .timeLimit on VideoExportTests and an upstream fix that throws on writer failure. Closed (user): deal with it if it happens again.
- `2026-10-19T01:43:06Z`: Recurred: particles-render --video hung (showreel run stalled on the last preset; make-demos.sh point-cloud hung 34 min with no output).
- `2026-10-19T01:54:51Z`: Not reproduced on demand (7 CLI exports, 5 full test runs, make-demos, showreel). Likely cause filed upstream as MetalSprockets#2 (waitUntilReady never resumes if the writer fails). Added: particles-render --video watchdog (no progress for 30 s, or PARTICLES_RENDER_STALL_SECONDS, writes a sample to $TMPDIR/particles-render-hang-<pid>.txt and exits 2) and a 1-minute time limit on VideoExportTests. Leaving open until the upstream fix lands.
- `2026-10-19T01:57:03Z`: Correction: the upstream issue is MetalSprockets#532 (not #2, which was filed in the wrong ISSUES.md and removed).
- `2026-10-19T11:52:19Z`: Closing: MetalSprockets main 232673a includes the video writer wait fix (MetalSprockets#532); CLI smoke test and VideoExportTests pass. The watchdog stays in particles-render; reopen if a hang comes back.

---

## 103: Architecture: a player that owns the per-frame loop for a particle system

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
created: 2026-10-18T21:33:49Z
updated: 2026-10-18T22:27:44Z
closed: 2026-10-18T22:27:44Z
+++

Five callers repeat the same per-frame sequence by hand: particles-render, ParticleSystem.exportVideo, the preset golden test, ParticleView (ParticleViewState), and the demo (ParticlesDemoModel+Pointer, ParticlesView). The sequence: work out the pointer, colliders(at:pointer:), forceFields(at:pointer:) and assign them to the runtime (simulate does not take fields), transforms(at:pointer:), trackedObjectPositions(at:), make or resize a SceneDepth when drawsColliders, simulate, then renderScene. The copies differ in small ways (tracked objects set before simulate vs passed in; the demo has its own colliders function with animate-colliders), and two bugs have come from this seam (per-frame force fields missed; colliders without the pointer).

Deepen into one module that owns a runtime, a ParticleSystem, the clock, the scene depth texture, and the pointer, and produces a frame's elements from a small input (delta time, drawable size, camera, optional pointer). The CLI, video export, golden test, ParticleView, and demo become thin callers.

Dependencies: in-process, plus the GPU through OffscreenRenderer/Runner, which already work in tests.
Tests: boundary tests on the player (deterministic frames, pointer bindings, finite effects, scene depth sizing) replace the scattered per-caller checks in PresetTests, ParticleViewTests, and the demo's frame tests.
Source: improve-codebase-architecture review. Related: #100, #99.

\- `2026-10-18T22:18:47Z`: Decisions (user):
1. The player owns its clock and advances it by deltaTime (deterministic; matches the CLI, video export, and goldens).
2. Move ParticleViewCamera into the core as ParticleCamera (system, lookAt, overlay); the player builds projection and view from the output size. One camera path for the CLI, video, goldens, and ParticleView; also enables a camera kind for 2D presets later.
3. Live edits: player.system = edited replaces the description, reloading only when the emitter layout changes (existing apply logic). Proper diffing stays with #104.
4. Name: ParticlePlayer.
Shape: let player = try ParticlePlayer(system:); player.pointer = worldPoint (optional); try player.frame(deltaTime:size:) gives the simulate and render elements. Callers to migrate: particles-render, exportVideo, the preset golden test, ParticleView, the demo.

- `2026-10-18T22:27:44Z`: ParticlePlayer (core): owns a runtime, the ParticleSystem description, a clock (advances while playing, scaled by speedFactor), a ParticleCamera, an optional world-space pointer, and a scene depth texture. frame(deltaTime:size:scale:wireframes:) uses the camera and its own depth; frame(deltaTime:projection:view:sceneDepth:wireframes:) is for hosts with their own camera and depth (the demo uses it; a scene graph would too). update(_:) replaces the description, rebuilding only on emitter layout changes. ParticleCamera moved from the UI library into the core. Callers migrated: particles-render, exportVideo, the preset golden test, ParticleView (now a thin wrapper), and the demo (its own per-frame functions and scene-depth cache are gone; it feeds currentEffect to the player). All goldens unchanged. The runtime API (simulate, render, renderScene) is untouched and stays first-class for hosts like MetalSprocketsSceneGraph. Tests: clock, identical output to the hand-written loop, update vs rebuild, scene depth, pointer; ParticleView setup and overlay mapping; demo tests now check currentEffect.

---

## 104: Architecture: apply a ParticleSystem to the runtime as a whole

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
created: 2026-10-18T21:33:49Z
updated: 2026-10-18T22:39:02Z
closed: 2026-10-18T22:39:02Z
+++

The runtime keeps its own copy of the description: public colliders, forceFields, lights, ambientLight, trackedObjects, and emitters[i].settings, set piecemeal or through load(_:) and apply(_ layers:). The demo keeps a third copy (ColliderItem, ForceFieldItem, emitters) and pushes changes with didSet. Ownership is unclear: per-frame overrides replace stored values, and toggling an item resets them. This is the main thing a document-based editor (#100) would trip over.

Deepen into one entry point, e.g. runtime.apply(system), that diffs the new description against the last one: keeps particles when only settings change, rebuilds when emitter layout changes, and makes the description the single source of truth. Per-frame inputs (pointer, animated colliders) stay separate from the description.

Dependencies: in-process.
Tests: 'apply a changed description, check what is kept and what is rebuilt' tests replace parts of EmitterDescriptionTests, MultipleEmitterTests, and the demo model's sync tests.
Source: improve-codebase-architecture review. Related: #100, and the player issue.

- `2026-10-18T21:57:36Z`: Related: #108 gives every item a stable id, which apply needs to diff descriptions.
- `2026-10-18T22:39:02Z`: ParticleSystemRuntime.apply(_ system:rebuild:) is now the one way a description reaches the runtime: layers (particles kept unless the emitter layout changes or rebuild is set), colliders, force fields, lights, ambient, compiled functions. load(_:) is apply(rebuild: true); ParticlePlayer.update calls apply. The demo's separate didSet pushes for emitters, colliders, and force fields are now one applyToRuntime() that applies currentEffect. Design choices made here: no item-level diffing (no stable ids, #108 closed), so colliders, fields, and lights are replaced wholesale, which is cheap; emitter diffing stays the existing id/capacity layout check. The demo still keeps its editing items (ids for the inspector) as its editing model; they reach the runtime only through apply. Tests: ApplySystemTests (everything arrives, settings and world changes keep particles, rebuild and layout changes start over).

---

## 105: Architecture: move editor-support API out of the core library

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:s
created: 2026-10-18T21:33:49Z
updated: 2026-10-18T22:36:02Z
closed: 2026-10-18T22:36:02Z
+++

ParticleKind.swift (about 430 lines) adds writable kind properties, display names, and case lists to library enums so SwiftUI pickers can switch cases. The demo adds more of the same (Inspector+Events.swift, ParticleEmitter+Inspector.swift). The library ships UI-shaped API that apps never call, and editor helpers are split between the library and the demo.

Move this into one place owned by the editor: the demo package now, or an editor-support library alongside the document-based editor (#100). Keep in the library only what non-editor callers need.

Dependencies: in-process.
Tests: ParticleKindTests and the demo's adapter tests merge where the code lands.
Source: improve-codebase-architecture review. Related: #100.

- `2026-10-18T22:36:02Z`: Moved ParticleKind.swift (the ParticleKind protocol, display names, case lists, writable kind setters) and ParticleKindTests into the demo package, which is the editor. The core keeps only internal gpuKind getters for the two mappings it needs (EmitterShape, SubEmitter.Occasion). The core now @_exported-imports MetalSprocketsParticlesShaders, so library users and the demo can name the shared types (ParticleBlendMode etc.) that already appear in its API. Design choice made here: the demo package, not a new editor-support library, since the editor (#100) is deferred; move it with the editor later.

---

## 106: Architecture: adding an emitter setting touches six places

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:m
created: 2026-10-18T21:33:49Z
updated: 2026-10-18T22:43:49Z
closed: 2026-10-18T22:43:49Z
+++

Each new per-emitter setting goes through: ParticleEmitter (property and Codable line), ParticleTypes.h (SimulationUniforms or RenderUniforms), FramePlan.uniforms(for:) (or the render draw), Particles.metal, the demo inspector, and sometimes ParticleKind. The Swift and Metal structs are mirrored by hand. Softness, user functions, and transitions all went through every step.

Look for ways to cut this: generate the Codable tolerant decoding from the property list, group related settings into nested structs that map 1:1 to C structs, or keep the Swift settings and the uniform packing in one file so a setting is added in two places at most. Weakest of the architecture candidates; worth a look when the settings next change a lot.

Dependencies: in-process, across the Swift/Metal boundary.
Tests: little change; behavior tests already cover settings.
Source: improve-codebase-architecture review.

- `2026-10-18T22:43:49Z`: Looked for ways to cut the six places. The GPU struct, the packing in FramePlan, the shader, and the inspector are inherent; code-generating one from another (Swift settings -> C uniforms) is heavy for this project. The real trap was silent: forgetting the tolerant-decoding line drops a setting from effect files with no error. Added DecodingCoverageTests: for every key ParticleEmitter, ParticleSystem, and SubEmitter encode, a wrong-typed value must make decoding fail, so an ignored key is caught without a hand-kept list (verified: removing the softness line fails the test). Added an 'Adding a setting' checklist at the top of ParticleEmitter.swift. Deeper unification left for if settings churn a lot.

---

## 107: Constrain particles to a plane

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:s
created: 2026-10-18T21:38:49Z
updated: 2026-10-18T22:01:53Z
closed: 2026-10-18T22:01:53Z
+++

An emitter setting that keeps particles on a plane (z = 0 in emitter or world space): zero the plane-normal component of spawn positions, velocities, spread, turbulence, and force-field accelerations, every step. Without it, spread cones, sphere shapes, and turbulence add depth motion; under an orthographic 2D camera that is invisible but changes collisions and sorting. Useful in 3D too: flat sheets, effects on a wall, side-scrolling scenes. Split out of #99.

- `2026-10-18T21:57:36Z`: Related: #99 (2D overlays use it to keep particles at z = 0).
- `2026-10-18T22:01:53Z`: ParticleEmitter.constrainsToPlane: each step the kernel projects world position and velocity onto the emitter's XY plane (through its position, facing its local Z), after integration (spread, fields, turbulence, user update) and again after collisions. No transform means the world z = 0 plane (2D); a transformed emitter carries its plane. Sub-emitter children with the setting use the world z = 0 plane. Codable, demo toggle. Tests: z stays 0 with spread, turbulence, and z gravity; rotated and moved plane; sphere collisions stay on the plane; round trip.

---

## 108: Stable ids for every item in a particle system

+++
status: closed
priority: medium
kind: task
labels: area:api, area:editor, effort:m
created: 2026-10-18T21:47:02Z
updated: 2026-10-18T22:16:43Z
closed: 2026-10-18T22:16:43Z
+++

Colliders, force fields, lights, sub-emitters, and triggers have no identity; the demo wraps colliders and fields in ColliderItem/ForceFieldItem with UUIDs and identifies sub-emitters and triggers by index, and PointerBinding refers to items by index. The editor needs ids for selection, undo, gizmos, and drag reordering, and #104 needs them to diff descriptions.

Give each an id, saved in the effect file and generated when missing, so old files load. Pointer bindings refer to ids; decode the old index form. Emitters keep their existing id. Decide whether ids sit on the library types or a small Identified<T> wrapper used in ParticleSystem; prefer on the types if the Codable shape stays flat.

Tests: old files load with fresh ids; ids round-trip; index-form pointer bindings decode to the right ids. Part of #100.

- `2026-10-18T21:57:36Z`: Related: #104 (apply needs ids to diff), #100 (editor), #105. ColliderSpin also refers to colliders by index and should move to ids with PointerBinding.
- `2026-10-18T22:13:27Z`: Tried: checked how ids would sit on Collider, ForceField, ParticleLight, SubEmitter, and EmissionTrigger. Punting: putting a generated id on the types changes their value equality, which about 40 call sites rely on (tests, the demo, ParticleKind): factories like .sphere(center:radius:) would make a fresh id each call, so colliders[1] == .sphere(...) stops matching. ParticleLight is an enum and has no place for an id without becoming a struct. Options: (A) id on each type, excluded from == and hash (value equality stays; Identifiable for lists and diffing; a little surprising). (B) An Identified<T> wrapper used only in ParticleSystem's lists (ids are a description concern; the runtime and factories stay plain values; ParticleSystem.colliders becomes [Identified<Collider>], a wide API change, with JSON as { id, ...flattened fields }). (C) id on each type and included in ==, updating tests to compare shapes or ignore ids (most honest, most churn). Which do you want? My pick is B if #104 (apply) and the editor are the main users, A if lists elsewhere also need ids.
- `2026-10-18T22:16:43Z`: Closed (user): not needed now. Ids would mainly serve the deferred editor (#100) and #104; revisit with them if it comes up.

---

## 109: Ribbons and trails

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:l
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:57:49Z
closed: 2026-10-19T02:57:49Z
+++

Draw particles as connected strips instead of separate sprites: trails behind sparks and comets, swooshes, lightning, sword arcs. Like Niagara ribbons and Unity VFX Graph strips. Options: a per-particle history ring (last N positions) drawn as a strip, or strips that link particles born in sequence from one emitter. Needs width and color over the strip's length, UVs along it for textures, and facing the camera. Today the closest is a while-alive sub-emitter trail of separate dots.

- `2026-10-19T02:57:49Z`: Done as a per-particle history: ParticleEmitter.trail (ParticleTrail: pointCount 2...64, tapers, fades) keeps each particle's last positions, one per simulation step, in a trail buffer made only when an emitter has a trail (16 bytes per point per particle, at the largest pointCount in the system). Births and sub-emitter children start with a collapsed trail, so reused slots do not streak. Drawn as camera-facing triangle strips with soft edges across, texture coordinates along, width from size over life, color from all the color settings. Not done: ribbons that link particles born in sequence (one ribbon per emitter), and time-based point spacing (points are per step, so trail length in time depends on the frame rate).

---

## 110: Custom particle attributes, and color and size in ParticleState

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:05:05Z
closed: 2026-10-19T02:05:05Z
+++

User Metal functions (#86-89) see only position, velocity, age, lifetime, and id. Add color and size, and a few custom float4 attributes per particle that functions can read and write and that persist between steps (Niagara and VFX Graph attributes). Lets functions do things like change color on collision, store a phase or target, or pass state from spawn to update. Costs particle memory, so make the custom ones optional per emitter.

- `2026-10-19T00:16:31Z`: Related: #121 (color by speed and similar could also be done in user functions once ParticleState has color).

---

## 111: Flocking: neighbor-aware simulation

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:l
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T03:09:38Z
closed: 2026-10-19T03:09:38Z
+++

Boids-style separation, alignment, and cohesion, and other effects that need nearby particles (simple fluids, crowd avoidance). Needs a spatial grid built each frame on the GPU (count, prefix sum, scatter, which the sort code partly has) and an extra simulation pass that reads it. Could be the first 'simulation stage' (Niagara) that user functions can also use later. Impressive at a million particles.

- `2026-10-19T03:09:38Z`: Done: ParticleEmitter.flocking (ParticleFlocking: radius, separationRadius, separation, alignment, cohesion, speedRange, maxNeighbors). Each frame, before the update, a GPU pass per flocking emitter builds a spatial hash grid of its live particles (clear, count, one-thread scan, scatter, per-cell sort for determinism) and a steering kernel sums boids forces over the 27 neighboring cells into a steering buffer; the update kernel adds it and clamps speed. Determinism: the atomic scatter made neighbor order vary and the Murmuration golden mismatch between runs; sorting each cell by slot fixed it (flockingIsDeterministic). Not done: a general 'simulation stage' for user functions to read neighbors, and a parallel scan (the scan is one thread over 16384 cells, which is fine at these sizes). Murmuration's preview is about 1 MB: thousands of moving dots compress poorly.

---

## 112: Curl-noise turbulence

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:s
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T00:51:10Z
closed: 2026-10-19T00:51:10Z
+++

Check whether the turbulence force field is curl noise (divergence-free). If not, add a curl-noise mode: it swirls without particles clumping into sinks or spreading out of sources, which reads much better for smoke and magic. Unity, Unreal, and Houdini all use curl noise for this.

- `2026-10-19T00:51:10Z`: Already done: ForceField.turbulence is analytic curl noise (curlNoise in Particles.metal, curl of a noise vector potential, so it is divergence-free). Ten sample presets use it already (Color Smoke, Campfire, Fog, Snow, ...), so no new demo.

---

## 113: Sample textures: spawn from an image, color from an image

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:09:15Z
closed: 2026-10-19T02:09:15Z
+++

Emit particles from the bright or opaque pixels of an image (a logo dissolving into sparks), and let particles take their color from a texture at their spawn position or as they move. Niagara and VFX Graph both sample textures. Needs an image emitter shape (weighted by pixel brightness or alpha, like the mesh area table) and a texture input for color.

- `2026-10-19T02:09:15Z`: Done: spawn from an image (EmitterImage on EmitterDescription.image: alpha or brightness weighting, colors from pixels, saved in effect files as PNG data). Not done: coloring moving particles from a texture each frame (sampling a texture in the simulation or in user functions). Spawn colors cover the common case; file a follow-up if per-frame texture lookups are needed.

---

## 114: Particle events with data back to the app

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:15:40Z
closed: 2026-10-19T02:15:40Z
+++

Triggers today are counts the CPU diffs. Add events that carry data from the GPU: where a particle hit a collider, how fast, which emitter, so game code can play sounds, leave decals, or spawn app objects at the hit (Niagara and VFX Graph output events). A small GPU ring buffer of event records read back a frame or two late, with a callback or polling API.

---

## 115: Emit from point caches

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:s
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T01:43:06Z
closed: 2026-10-19T01:43:06Z
+++

Emit from a list of baked points (a scanned model, a logo outline, an SVG path sampled to points) with optional per-point normals and colors, as VFX Graph point caches do. Simpler than meshes and works for shapes with no surface. Load from a file or pass an array; store in effect files like mesh positions.

---

## 116: Follow a path: spline force field

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:20:10Z
closed: 2026-10-19T02:20:10Z
+++

A force field that pulls particles along a curve: magic swirling along a path, energy flowing through a pipe, particles orbiting a spline. Houdini, Niagara, and PopcornFX have curve forces. Defined by control points with a radius of influence, strength toward the curve, and speed along it. Shows as a wireframe.

- `2026-10-19T02:20:10Z`: Done as ForceField.Effect.path(points:speed:strength:radius:closed:): a Catmull-Rom curve through the points, tessellated on the CPU (12 samples per span, at most 512 points) into a shared path point buffer; the GPU finds the closest segment and steers toward speed along the tangent plus a pull of strength per second onto the curve. Draws as a wireframe with flow arrows. Demo: Magic Loop.

---

## 117: Particle LOD and culling

+++
status: closed
priority: medium
kind: feature
labels: area:simulation, effort:m
created: 2026-10-19T00:12:15Z
updated: 2026-10-19T02:24:14Z
closed: 2026-10-19T02:24:14Z
+++

Spend less on effects that are far away or off screen: scale emission rate and particle size with distance from the camera, and skip simulating or drawing emitters whose bounds are outside the view (with a choice to keep simulating so they stay correct when they come back). Common in Niagara (scalability) and Unity. Needs emitter bounds.

- `2026-10-19T02:24:14Z`: Done: distance LOD scales birth rate (lodNearDistance, lodFarDistance, lodFarRateScale) and a culling sphere (cullingRadius) skips drawing out-of-view emitters, and simulating too when simulatesWhenCulled is off. Uses the camera from the last render, one frame behind. Not done: scaling particle size with distance (perspective already shrinks far particles; add if a use appears).

---

## 118: Particles that light the scene

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T00:12:16Z
updated: 2026-10-19T02:32:33Z
closed: 2026-10-19T02:32:33Z
+++

Let particles emit light onto other particles and, through the host, onto scene geometry: sparks lighting the ground, fireflies glowing. Niagara has a light renderer that turns some particles into lights. Pick the brightest or a sample of particles each frame (GPU reduction), expose them as lights for the host renderer, and light lit particles with them.

- `2026-10-19T02:32:33Z`: Done: ParticleEmitter.light (ParticleLightEmission: count, color, intensity, range) turns live particles into point lights each frame, gathered on the GPU after the simulation (one live particle per stretch of the emitter's live window, dimming with age), at most 16 per system. They light lit particles of every emitter. The host gets particleLightBuffer (GPU) and emittedLights() (CPU, last finished frame) for its own geometry. Picking the brightest particles (a GPU reduction) is not done; even sampling over the live window was enough for the demo.

---

## 119: Mesh particles

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T00:12:16Z
updated: 2026-10-19T02:37:52Z
closed: 2026-10-19T02:37:52Z
+++

Draw each particle as a small 3D mesh instead of a sprite: debris, rocks, leaves, coins, confetti with thickness. Unity and Niagara both have mesh renderers. Instanced draw of a SwiftMesh mesh with the particle's position, rotation (needs a full 3D orientation per particle), scale, and color; lit by the particle lights.

- `2026-10-19T00:16:31Z`: Related: #118 (mesh particles would be lit by particle lights) and #110 (needs a full 3D orientation per particle).
- `2026-10-19T02:37:52Z`: Done: ParticleEmitter.particleMesh (ParticleMesh: cube, tetrahedron, coin, or custom triangles, also from a SwiftMesh mesh) draws each particle as an instanced 3D shape with depth testing. Full 3D orientation without new particle storage: each particle tumbles about a random axis hashed from its slot by its existing rotation angle. Lit by scene and particle lights with real normals. Limitation: collisions still treat particles as points, so shapes sink into colliders by up to their size (visible in Coin Shower); a per-particle collision radius would fix it.

---

## 120: Collide with the scene depth buffer

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:m
created: 2026-10-19T00:12:16Z
updated: 2026-10-19T02:45:00Z
closed: 2026-10-19T02:45:00Z
+++

Collide particles against whatever the host renders, using the depth buffer (screen-space collision, as Unreal and Unity GPU particles do), so effects hit arbitrary scene geometry without colliders. Uses the SceneDepth path from soft particles: project each particle, compare with the stored depth, and bounce off a normal rebuilt from neighboring depths. Only works for what is on screen; pairs with real colliders for the rest. Related: #2.

- `2026-10-19T02:45:00Z`: Done: ParticleEmitter.collidesWithSceneDepth bounces particles off the SceneDepth texture of the previous frame (ParticleSystemRuntime.collisionDepth, set automatically by renderSceneDepth or by the host). A particle just behind the stored surface (within thickness) is put back on it and bounced with the emitter's restitution and friction, using a normal rebuilt from neighboring depth samples. Hits report as events with colliderIndex -1. Limits as expected for screen-space collision: only on-screen, unoccluded surfaces; particles behind objects fall through. Uses the r32Float SceneDepth texture, not a raw depth32Float attachment.

---

## 121: More color gradients: by speed, random between two, by position

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T00:15:37Z
updated: 2026-10-19T02:51:12Z
closed: 2026-10-19T02:51:12Z
+++

Colors today: colorOverLife (a multi-stop RGBA gradient over each particle's life), opacityOverLife, and per-particle HSB colorVariation. Add, as Unity and Niagara have:
- Color by speed: a gradient sampled by speed (between a min and max speed), multiplied with or replacing color over life. Sparks and fire read hot when fast, cool when slow.
- Random between two gradients: each particle picks a blend between two over-life gradients at birth. More varied than a hue shift.
- Color by position: a gradient across the emitter's shape or along a world axis, picked at birth (a rainbow along a line, a two-tone fountain).
Each needs a setting, a curve table on the GPU, the demo's gradient editor, and Codable with tolerant decoding. Related: #110 (user functions could do these once ParticleState has color).

- `2026-10-19T02:51:12Z`: Done, all at draw time: colorBySpeed + colorBySpeedRange (multiplies), alternateColorOverLife (each particle blends toward it by a fixed random amount hashed from its slot), colorByPosition + colorByPositionStart/End (multiplies, by current position in world space). Deviation: position color uses the current position rather than the birth position, so it needs no particle storage; birth-position color can be done with a spawn function setting ParticleState.color (#110). Demo: Spark Spectrum.

---

## 122: More than one custom attribute per particle

+++
status: closed
priority: low
kind: enhancement
labels: area:simulation, effort:m
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:41:56Z
closed: 2026-10-19T12:41:56Z
+++

ParticleState.custom is one float4 per particle (#110). Allow a few (for example up to 4), chosen per emitter so memory is only spent where used. Needs a per-emitter attribute count, a strided attributes buffer, and a prelude change (custom as an array or custom0...custom3).

- `2026-10-19T12:41:56Z`: Done: ParticleState gains custom1, custom2, custom3 (after custom, so existing functions compile unchanged), and ParticleEmitter.customAttributeCount (1 to 4) says how many are kept between steps. The attribute buffer's stride is the largest count among emitters with functions, so systems that use one keep 16 bytes per particle; asking for more reallocates (and clears) it.

---

## 123: Color particles from a texture as they move

+++
status: closed
priority: low
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:52:07Z
closed: 2026-10-19T12:52:07Z
+++

EmitterImage (#113) colors particles at birth only. Add sampling a texture each frame by position, projected onto a plane or by screen position, so particles change color as they move over an image. Could be a render-time lookup, like colorByPosition (#121), with a texture instead of a gradient.

- `2026-10-19T12:52:07Z`: Done: ParticleEmitter.colorImage (ParticleColorImage: image data and a world-space rectangle, origin plus width and height edge vectors, or centered in the XY plane with its aspect ratio) multiplies each particle's color by the image under its current position, every frame, for sprites, meshes, trails, and ribbons. Particles off the image take the nearest edge color; transparent edges make them invisible. Saved in effect files as image data; textures are cached per image. Demo: Living Picture (preview about 710 KB: dense moving dots compress poorly). Not done: projecting the image from the camera (screen space) instead of a world rectangle.

---

## 124: Scale particle size with camera distance

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:s
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:30:20Z
closed: 2026-10-19T12:30:20Z
+++

Distance LOD (#117) scales emission only. Optionally scale size with distance from the camera too, for example keeping a minimum on-screen size so far particles do not shrink to nothing, or growing them to fill in for lower emission.

- `2026-10-19T12:30:20Z`: Done: ParticleEmitter.minimumScreenSize (half-size as a fraction of the view height; far particles never draw smaller) and lodScalesSize (grows particles by 1/sqrt of the distance LOD rate scale, so coverage stays about the same with fewer particles). Sprites and mesh particles; trails and ribbons keep their widths. Both off by default, so goldens hold.

---

## 125: Pick the brightest particles as lights

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:m
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:44:33Z
closed: 2026-10-19T12:44:33Z
+++

ParticleEmitter.light (#118) takes one live particle from each stretch of the live window. Picking the brightest (by color times opacity at their age) would light more convincingly: a GPU reduction or a top-k pass over the live window.

- `2026-10-19T12:44:33Z`: Done: ParticleLightEmission.picksBrightest (default on): each light takes the brightest live particle in its stretch of the live window, by the luminance of its color over life (opacity included) at its age times its tint, instead of the first live one. Lights stay spread across the effect. Off restores the cheaper first-live pick. Ember Glow's golden is within tolerance. A global top-k over the whole emitter is not done (lights could then bunch up).

---

## 126: Collision radius for particles

+++
status: closed
priority: medium
kind: enhancement
labels: area:collision, effort:m
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:11:16Z
closed: 2026-10-19T12:11:16Z
+++

Collisions treat particles as points, so mesh particles (#119) and large sprites sink into colliders by up to their size (visible in Coin Shower). Add a per-emitter collision radius (or use the particle's size) that offsets every collider test: planes by distance, spheres and capsules by radius, boxes by half extents, and scene depth.

- `2026-10-19T11:47:47Z`: Related: #132 (spin should also stop on contact).
- `2026-10-19T12:11:16Z`: Done: ParticleEmitter.collisionRadius. When above 0, each collider is inflated by it for that emitter (planes moved out, sphere and capsule radii grown, box half extents grown), so all tests and sweeps treat particles as spheres; scene depth contacts keep particles that far off the surface. At 0 the code path is unchanged, so goldens hold. Coin Shower uses 0.05: far fewer coins sink into the floor; steeply tilted coins can still clip a little, since a sphere only approximates a coin. Not done: using each particle's own size as its radius.

---

## 127: Color gradient by birth position

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:s
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:33:01Z
closed: 2026-10-19T12:33:01Z
+++

colorByPosition (#121) uses the current position. Add an option to sample it once at birth and keep it (in the particle tint, like point cache colors), for two-tone fountains whose colors stay with each particle. A spawn function setting ParticleState.color can do this today.

- `2026-10-19T12:33:01Z`: Done: ParticleEmitter.colorByPositionAtBirth samples colorByPosition once at the spawn position (world space) and multiplies it into the particle's tint, so the color stays with the particle; drawing then skips the per-frame position gradient. 8 bits per channel, values above 1 clip. Sub-emitter children are not colored this way (they spawn on the parent's dispatch).

---

## 128: Ribbons that join an emitter's particles in birth order

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:l
created: 2026-10-19T11:40:05Z
updated: 2026-10-19T12:24:30Z
closed: 2026-10-19T12:24:30Z
+++

Trails (#109) are per particle. Add a mode that draws one ribbon through all of an emitter's live particles in birth order, as Niagara and VFX Graph strips do: a stream from a moving emitter, a sword arc, a lightning bolt. Needs the live window in spawn order (it already is, as a ring) and handling of dead gaps.

- `2026-10-19T12:24:30Z`: Done: ParticleEmitter.ribbon (ParticleRibbon: tapers) draws one camera-facing strip through the emitter's live window in birth order; width is each particle's size, color its own color. Dead particles inside the window break the ribbon cleanly (zero width, no color). Ribbon emitters give births in one step ordered birth ages (the random draw is kept, so other draws do not change), so slot order matches path order; without it fast emitters zigzag (ribbonEmittersBirthInSlotOrderAlongTheirPath fails). Demo: Streamers. Not done: ribbons across several emitters, or one ribbon per sub-emitter parent.

---

## 129: Space trail points by time, not by step

+++
status: closed
priority: low
kind: enhancement
labels: area:rendering, effort:s
created: 2026-10-19T11:40:06Z
updated: 2026-10-19T12:35:38Z
closed: 2026-10-19T12:35:38Z
+++

Trail points (#109) are recorded once per simulation step, so a trail covers less time at higher frame rates. Add a point interval in seconds: record a point only when that much time has passed since the last, and move the head point every step so the ribbon still reaches the particle.

- `2026-10-19T12:35:38Z`: Done: ParticleTrail.pointInterval (seconds; 0 keeps one point per step). The head point follows the particle every step; a new point is pushed only once pointInterval has passed since the head was recorded (the age is kept in each trail point's w). Trails then cover pointCount x pointInterval seconds at any frame rate, plus the partly covered newest interval.

---

## 130: Sand on Shapes runs at 80 fps instead of 120

+++
status: closed
priority: medium
kind: bug
labels: area:performance, effort:m
created: 2026-10-19T11:42:02Z
updated: 2026-10-19T12:03:27Z
closed: 2026-10-19T12:03:27Z
+++

Reported in the demo app: Sand on Shapes (scene depth collision, #120) is the slowest demo, about 80 fps where others hold 120 on the M5 Max. Cause not measured yet. Candidates to check with a GPU capture or particles-bench:
- The depth collision test in the update kernel: every particle of the emitter projects into the depth texture, and contacts read five depth texels and do two 4x4 matrix inverses' worth of math (depthWorldPosition) per step.
- The extra scene depth render pass (renderSceneDepth) plus the solid collider pass, every frame.
- Overdraw from about 8,000 alpha-blended sand sprites, or the preset's warmup.
- CPU side: renderSceneDepth runs SceneDepthCollision.data, which inverts the view-projection matrix each frame (cheap, but check nothing else per frame is heavy).
Fix whatever dominates; compare against Rain (similar count, analytic colliders).

- `2026-10-19T11:42:11Z`: Correction to the description: the shader does no matrix inversion; each contact does five depth reads and five matrix-vector multiplies by the precomputed inverse view-projection.
- `2026-10-19T11:47:47Z`: Related: #131 (benchmark to catch regressions like this).
- `2026-10-19T12:03:27Z`: Measured (debug build, 1920x1080, frame build vs whole frame): Sand on Shapes 9.84 / 11.45 ms, Fog 9.78 / 13.25 ms; with drawsColliders off both build in about 0.15 ms. Depth collision cost nothing (11.44 vs 11.48 ms). The cost was CPU: renderSceneDepth and renderColliderSolids each re-tessellated the colliders (sphere 6144, capsule 12672 vertices; 4.7 ms per set) every frame. Now cached until the colliders change: Sand on Shapes 0.18 / 1.37 ms, Fog 0.21 / 2.22 ms. Still re-tessellates when colliders move each frame (Pointer Stir's sphere while the pointer moves, about 1.5 ms in debug); tessellating shapes once in local space and transforming would fix that if needed.

---

## 131: Frame time benchmark for every sample preset

+++
status: closed
priority: medium
kind: task
labels: area:performance, effort:m
created: 2026-10-19T11:42:02Z
updated: 2026-10-19T12:26:04Z
closed: 2026-10-19T12:26:04Z
+++

Nothing catches performance regressions: Sand on Shapes dropped to 80 fps unnoticed. Add a benchmark (particles-bench or a test tagged as slow) that runs each sample preset for a few seconds at a fixed size and reports GPU time per frame, with a budget per preset (for example 8 ms for 120 fps) and a table in the output. Run it before releases, not in every test run.

- `2026-10-19T12:26:04Z`: Done: particles-bench --presets runs every sample preset through ParticlePlayer at 1920x1080 (scene depth and solid colliders included) and prints median frame build (CPU), GPU, and whole-frame times, the worst frame, live particles, and ok/OVER against --budget (8.33 ms default, 120 fps). --preset filters by name; --check exits with an error when any preset is over budget, for a pre-release run. Use a release build (xcb build -c release, then .build/out/Products/Release/particles-bench) for meaningful numbers. No unit test: it is a measuring tool; checked with a debug run and --check against a tiny budget (exit 1).

---

## 132: Particles keep spinning after they come to rest on a collider

+++
status: closed
priority: medium
kind: bug
labels: area:collision, effort:s
created: 2026-10-19T11:42:29Z
updated: 2026-10-19T11:59:41Z
closed: 2026-10-19T11:59:41Z
+++

In Coin Shower, coins stop sliding on the floor but keep rotating in place. Collisions damp linear velocity (restitution and friction) but never touch angular velocity (Particle.rotation.y), so spin set by angularSpeedVariation runs for the particle's whole life. Most visible with mesh particles (#119), also true for spinning sprites.

Expected: contact friction slows spin as well, so a particle resting on a collider stops turning. Possible fix: in collide(), scale rotation.y by the same friction factor applied to tangential velocity (or a separate angular damping on contact). Related: #126 (collision radius).

---

## 133: Lifetime sliders are hard to use: replace Min/Max with Lifetime and Variation

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T11:43:27Z
updated: 2026-10-19T12:05:35Z
closed: 2026-10-19T12:05:35Z
+++

The inspector shows lifetime as two sliders, Lifetime Min and Lifetime Max (0.1...10 s; sub-emitters 0.05...5 s). To make particles live longer you must raise Max and then Min, and dragging either one past the other drags the other along (ParticleEmitter+Inspector.swift lifetimeMinimum/lifetimeMaximum). It does not match the rest of the inspector, which uses a value plus a variation (birth rate, size, speed, angle).

Proposal: show Lifetime (the middle of the range) and Lifetime Variation (plus or minus, in seconds or as a fraction), so one slider makes particles live longer and the spread stays the same. Map onto the existing lifetime range, so effect files do not change. Also raise or remove the 10 s cap (long-lived presets like Murmuration use 1000 s) and allow typing a value.
Reported by the user: 'I expect to be able to easily extend lifetime but these sliders are counterintuitive.'

---

## 134: Debug view modes: particle wireframes and false-color views

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T11:43:47Z
updated: 2026-10-19T12:17:22Z
closed: 2026-10-19T12:17:22Z
+++

Add debug view modes that replace normal particle drawing, selectable in the demo (and as an option on render / ParticlePlayer, so particles-render can use them):

Wireframe:
- Draw each particle's geometry as lines: sprite quads (shows size, orientation, stretch, overdraw), mesh particles (#119), and ribbons (#109).

False color (color each particle by something other than its color):
- Emitter or layer (a distinct color per emitter, sub-emitters included)
- Normalized age (age / lifetime)
- Speed (with a range)
- Lifetime remaining
- Slot index or ring position (shows spawn order and the live window)
- Collision state (hit this step, resting), and scene depth contacts (#120)
- Culled or LOD scale (#117), flocking neighbor count (#111)
- Overdraw / fill cost (additive count per pixel, heat-mapped)

Debug views ignore blend mode and textures (opaque or additive heat map as fits). Collider and field wireframes already exist (DebugWireframes) and should combine with these.

- `2026-10-19T12:17:22Z`: Done: ParticleSystemRuntime.debugView (ParticleDebugView: none, wireframe, emitter, age, speed, lifeRemaining, slot, overdraw) with debugRange for speed and life remaining. Works for sprites, mesh particles, and ribbons; wireframe draws triangles as lines (solid green), overdraw is a dim additive heat map, the others are a blue-to-red ramp. In the demo: World section, Debug View picker; in the CLI: --debug-view (images and videos). Simulation is unaffected. Not done: collision state, culled/LOD state, flocking neighbor count, scene depth contacts (they need extra per-particle data).

---

## 135: Show particles born and died per frame in the stats overlay

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:s
created: 2026-10-19T11:44:07Z
updated: 2026-10-19T12:39:00Z
closed: 2026-10-19T12:39:00Z
+++

The demo's stats overlay (StatsView in ParticlesView.swift) shows the live particle count (aliveParticleCount). Add how many particles were born and how many died over the last N frames (shown as per-second rates, or per-frame averages), per emitter if room.

Born is known on the CPU (the spawner's count per step, plus bursts and sub-emitter children, which are written on the GPU). Deaths need a GPU counter (like aliveCounters, read a few frames late) or can be derived from births and the change in live count. Helps tune birth rates and lifetimes and spot capacity limits (births overwriting live particles when the ring is full, which could get its own counter).

- `2026-10-19T11:44:22Z`: Correction: the overlay is ParticleCountView in ParticlesView.swift (alive count and capacity), not StatsView.
- `2026-10-19T11:47:47Z`: Related: #139 (toggle to hide overlays).
- `2026-10-19T12:39:00Z`: Done: the GPU counts births (spawns and sub-emitter children written) and deaths per step into the same per-frame slots as the live count (one atomic per SIMD group); the runtime exposes bornParticleCount and diedParticleCount (one recent frame, read a few frames late) and birthsPerSecond / deathsPerSecond over the last 30 frames. The demo overlay shows '+N/s -M/s' next to the live count. Not done: per-emitter rates, and a counter for births that overwrite live particles when the ring is full.

---

## 136: Paint Drops does not splatter in the demo app: the model drops eventBursts

+++
status: closed
priority: high
kind: bug
labels: area:demo, effort:s
created: 2026-10-19T11:44:54Z
updated: 2026-10-19T11:56:07Z
closed: 2026-10-19T11:56:07Z
+++

In the demo app, Paint Drops' drops fall and vanish without splattering. particles-render, the preview, and the golden image are fine.

Cause (from the code, not yet confirmed by a test): ParticlesDemoModel.currentEffect rebuilds the ParticleSystem from the model's editor state every frame and never sets eventBursts (added in #114), and the model does not store it when a preset loads. ParticlePlayer applies system.eventBursts, so the player gets none. Saving an effect from the demo loses them too.

Fix: keep eventBursts in the model on load and set it in currentEffect. Test: for every sample preset, loading it into ParticlesDemoModel and reading currentEffect gives back an equal system (or at least equal encoded JSON), so fields added later cannot be silently dropped again. An editor for eventBursts in the inspector can be a separate issue.

---

## 137: Category mask UI is confusing

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T11:46:26Z
updated: 2026-10-19T12:07:36Z
closed: 2026-10-19T12:07:36Z
+++

CategoryMaskView (InspectorControls.swift) shows a row of eight toggle buttons numbered 1-8 for each mask (Collides With, Feels Fields, and Categories on colliders and fields). Problems:
- The numbers mean nothing; categories have no names.
- Only bits 0-7 are shown, but masks are 32 bits and default to all bits set, so 24 set bits are invisible and cannot be changed.
- No All or None, and no way to see which colliders or fields an emitter will actually feel.
Ideas: named categories per scene (for example Floor, Walls, Wind) stored with the effect; a menu or popover of checkboxes with All and None; show the colliders and fields an emitter matches (or highlight them in the viewport). Related: the next issue on having one mask instead of two.

- `2026-10-19T11:47:47Z`: Related: #138 (merging the two emitter masks would simplify this UI).
- `2026-10-19T12:07:36Z`: Done: masks are now a menu with a summary (All, None, '1, 3', '2 + 9–32'), All and None items, categories 1-8 as checkmarks, and 9-32 as one item, so no set bit is hidden. Emitter masks show what they match ('Matches 2 of 3 colliders'). Not done (needs a design decision): named categories stored with the scene, and highlighting matched colliders in the viewport. #138 (one mask) would simplify this further.

---

## 138: One mask per emitter instead of collisionMask and fieldMask

+++
status: closed
priority: low
kind: task
labels: area:simulation, effort:s
created: 2026-10-19T11:46:26Z
updated: 2026-10-19T13:38:33Z
closed: 2026-10-19T13:38:33Z
+++

An emitter has two masks, collisionMask (matched against Collider.categoryBitMask) and fieldMask (matched against ForceField.categoryBitMask), both UInt32. A single UInt32 would do the same job if colliders and fields use different bits: an emitter that should bounce off the floor but ignore the wind keeps the floor's bit and drops the wind's.
Trade-off: with one mask, colliders and fields share one 32-bit category space, and a bit used by both a collider and a field cannot be split per emitter. Two masks allow that but are more to explain and edit (and the UI, previous issue, shows both).
Decide whether to merge. If yes: add ParticleEmitter.categoryMask, decode old files by combining (an emitter matches a collider when collisionMask matches, and a field when fieldMask matches, so map carefully or keep reading the old keys), update docs, the inspector, and CategoryMaskTests.

- `2026-10-19T13:08:36Z`: Decision (user): merge into one categoryMask. Users keep collider and field bits apart; 32 bits is plenty. Old files: combine collisionMask and fieldMask when reading.
- `2026-10-19T13:38:33Z`: Done: ParticleEmitter.categoryMask replaces collisionMask and fieldMask; colliders and fields both match against it. Old files: equal masks carry over, different ones combine (OR). Two presets used them differently and were remapped by hand so they behave the same (goldens unchanged): Awning (its wind field moved to category 4; Rain 5, Sparks 3) and Sand on Shapes (mask 0: depth collision only). The other presets were migrated by one jq pass, keeping JSONEncoder's formatting. The demo inspector shows one Categories mask that says how many colliders and fields it matches.

---

## 139: Toggle to show and hide the viewport overlays

+++
status: closed
priority: low
kind: enhancement
labels: area:demo, effort:xs
created: 2026-10-19T11:46:53Z
updated: 2026-10-19T12:27:21Z
closed: 2026-10-19T12:27:21Z
+++

The demo viewport always shows its overlays (the particle count view, ParticleCountView, and any other stats or labels drawn over the render). Add a toggle to hide and show them: a toolbar button and a keyboard shortcut (for example Cmd-Shift-H), remembered between launches (@AppStorage). Useful for clean screenshots and recordings, and alongside #135 (more stats) and #134 (debug views).

- `2026-10-19T12:27:21Z`: Done: an Overlays toggle in the toolbar (⇧⌘H) hides the frame timing and particle count, remembered between launches (@AppStorage showsViewportOverlays). No unit test: a view-only toggle with no logic; checked by building (and per house rules the app is not launched).

---

## 140: 2D mode: particles all blob in the middle

+++
status: closed
priority: medium
kind: bug
labels: area:demo, effort:s
created: 2026-10-19T11:56:35Z
updated: 2026-10-19T13:12:59Z
closed: 2026-10-19T13:12:59Z
+++

In 2D mode, particles clump together in the center of the view instead of spreading out. Screenshot: /Users/schwa/Library/Application Support/CleanShot/media/media_p1yXCD4QzP/Screenshot 2026-10-19 at 07.56.00@2x.png

- `2026-10-19T13:07:05Z`: Triage: this is the 2D Overlay demo window (OverlayDemoView). The screenshot shows Celebrate's confetti as a small blob just above the button instead of a burst across the view. Not investigated yet; a guess to check first: the overlay camera works in points, so emitter speeds, spread, and sizes meant for world units are tiny there. Related: #141 (one 2D toggle).
- `2026-10-19T13:12:59Z`: Cause: velocitySpread and speedVariation are absolute speeds, not fractions of the velocity. The overlay demo works in points, so its confetti spread of 0.7 and speed variation of 0.4 were 0.7 and 0.4 points a second: every particle moved as one (a reproduction showed 300 particles 0.36 points apart). Fixed the demo values (confetti 600 and 300, sparkles 220 and 120 points a second). The library behaves as documented; #141's 2D defaults should set these in points too.

---

## 141: Make 2D mode a single toggle

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T11:56:36Z
updated: 2026-10-19T13:17:19Z
closed: 2026-10-19T13:17:19Z
+++

2D mode should be one toggle. Turning it on should change rendering, z limits, the camera, and any other related settings together.

- `2026-10-19T13:07:05Z`: Related: #140 (2D overlay confetti blob). Builds on the overlay camera, ParticleCamera.overlay, and ParticleEmitter.constrainsToPlane (#99, #107).
- `2026-10-19T13:08:36Z`: Decision (user): one ParticleSystem.is2D setting that turns on together: the overlay camera (points, y down), constrainsToPlane on every emitter, and 2D defaults for new emitters (speeds and sizes in points, which likely fixes #140). The 3D settings stay underneath, so turning it off returns to the 3D scene.
- `2026-10-19T13:17:19Z`: Done: ParticleSystem.is2D. The .system camera becomes the overlay camera (points, y down); apply keeps every emitter on its plane (effectiveLayers) without changing the stored layers, so turning 2D off restores the 3D scene; ParticleEmitter.default2D is a starting point in points (spreads in points too, see #140). Demo: a 2D toggle in the World section switches the viewport to the overlay camera, and Add Emitter uses the 2D defaults in 2D. Not done: converting an existing 3D scene's units to points (2D effects are authored in points).

---

## 142: Add CI using xcb ci

+++
status: closed
priority: medium
kind: task
labels: area:tooling, effort:m
created: 2026-10-19T11:57:41Z
updated: 2026-10-19T13:31:49Z
closed: 2026-10-19T13:31:49Z
+++

Use `xcb ci` to generate the CI rules. Metal 4 fails on GitHub runners, so use conditional compilation to work around it, the same way other MetalSprockets projects do.

- `2026-10-19T13:31:49Z`: Done: .github/workflows/swift.yml (SwiftLint --strict; swift build and swift test with warnings as errors) and xcode.yml (the demo app, macOS), from 'xcb ci generate --warnings-as-errors --destination platform=macOS'; 'xcb ci check' passes. Metal 4: the GitHub runners' paravirtual GPU has none, so every test suite now carries a .requiresMetal4 trait (RequiresMetal4.swift in each test target, as in MetalSprocketsAddOns), which skips it there and runs it everywhere else. Not verified: the first real GitHub run (not pushed), building with Xcode 26.6 instead of 27, and iOS/visionOS demo builds (left out: the iOS simulator build is known to fail inside MetalSprockets, and visionOS is #98).

---

## 143: Add a stress-test demo with a huge particle count

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:s
created: 2026-10-19T12:03:12Z
updated: 2026-10-19T13:24:59Z
closed: 2026-10-19T13:24:59Z
+++

Add a demo preset with a very large number of particles (millions), for performance testing and profiling.

- `2026-10-19T13:07:05Z`: Related: #131 (particles-bench --presets would time it against the frame budget).
- `2026-10-19T13:24:59Z`: Done: Stress Test sample preset, two million particles (a million born a second, two-second lives) in a curl-noise cloud, additive sub-pixel dots. particles-bench --presets times it with everything else; on the M5 Max (debug build, 1080p) it runs 4.25 ms GPU, 5.14 ms a frame. Preview about 445 KB; golden test adds little time.

---

## 144: Option to use reverse Z in depth buffers

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T12:09:39Z
updated: 2026-10-19T13:21:24Z
closed: 2026-10-19T13:21:24Z
+++

Add an option to render with reverse Z (clear depth to 0, compare greater, swap near/far in the projection) for better depth precision at distance.

- `2026-10-19T13:07:05Z`: Touches every depth consumer: SceneDepth and its depth pass, solid colliders, soft particles (the depthUnproject math), and scene depth collision (#120, which compares particle depth against the stored value). Default stays forward Z so goldens hold.
- `2026-10-19T13:21:24Z`: Done: ParticleSystemRuntime.reverseZ (off by default) plus reversingDepth(_:) for any projection. With it on: the scene depth pass clears to 0 and tests greater (its 'nothing drawn' value is 0), solid colliders and mesh particles test greater, renderScene's pass clears depth to 0, depth collision flips its in-front test and empty value, and ParticlePlayer reverses its camera's projection. Soft particles already unproject from the projection matrix, so they work unchanged. Hosts that draw their own passes must reverse their projection and clear depth to 0. Not done: a demo toggle.

---

## 145: Expand Methodology.md: issue subsystem and CLI rendering

+++
status: closed
priority: medium
kind: documentation
labels: area:docs, effort:s
created: 2026-10-19T12:10:30Z
updated: 2026-10-19T13:32:52Z
closed: 2026-10-19T13:32:52Z
+++

Documentation/Methodology.md should say more about the issues subsystem (how issues were filed, triaged, and closed during development) and the CLI rendering tool we used (what it does and how it fit into the workflow).

---

## 146: Demo descriptions should lead with the features and techniques shown

+++
status: closed
priority: medium
kind: documentation
labels: area:demo, effort:s
created: 2026-10-19T13:21:53Z
updated: 2026-10-19T13:23:07Z
closed: 2026-10-19T13:23:07Z
+++

Preset comments (the source of Documentation/Demos.md) mostly describe the scene. Readers want to know which library features and techniques each demo shows off. Rewrite every preset comment to lead with the features shown (with API names), and keep the scene to a short sentence.

- `2026-10-19T13:23:07Z`: Rewrote every preset comment to lead with the features shown; regenerated Demos.md.

---

## 147: Particle count overlay keeps resizing, so the centered panel jumps around

+++
status: closed
priority: medium
kind: bug
labels: area:demo, effort:xs
created: 2026-10-19T13:43:11Z
updated: 2026-10-19T13:48:22Z
closed: 2026-10-19T13:48:22Z
+++

The particle count overlay at the top of the viewport (ParticleCountView in ParticlesView.swift) changes width every time its numbers change, and since it is centered (.overlay(alignment: .top)) the whole panel jumps left and right. It got worse with #135, which added the '+N/s -M/s' rates that change every update.

Likely cause: the texts take only the width of their current digits. monospacedDigit() makes each digit the same width, but the number of digits (and the thousands separators) still changes, e.g. 9,980 vs 10,012, and 0/s vs 1,200/s.

Possible fixes: give each number a fixed width sized for its largest expected value (a hidden template like Text("0,000,000").hidden() in an overlay or a ZStack), or align the panel to a leading edge so changes grow to one side only. Rounding the rates (for example to tens) would also make them change less often. Related: #139 (hide overlays).

---

## 148: Max Particles field refreshes the UI on every edit, so it is hard to type into

+++
status: closed
priority: medium
kind: bug
labels: area:editor, effort:s
created: 2026-10-19T15:21:46Z
updated: 2026-10-19T16:08:26Z
closed: 2026-10-19T16:08:26Z
+++

Typing in the inspector's Max Particles field (EmissionSectionView, bound to EmitterDescription.editableCapacity) refreshes the UI on each edit, which makes it hard to enter a number.

Not investigated yet. Things to check first:
- Whether TextField(value:format:) writes the binding per keystroke here (on macOS it usually writes on commit), so each digit becomes a new capacity.
- Each new capacity changes the emitter layout, so the runtime rebuilds its buffer and the effect restarts; capacityError and the model's emitters also change, re-rendering the inspector, which may reset the field's focus or text.
- The warning label appearing and disappearing under the field shifts the layout as the value changes.

Expected: type a whole number, press Return (or leave the field), then one rebuild. Fix likely: edit a local @State draft and write the capacity only on submit/focus loss. Related: the Max Particles commits (f0b8e34c, 6b17e95f).

- `2026-10-19T16:08:26Z`: Fixed: Max Particles is now a CommittedNumberField, which edits a draft string and writes the capacity only on Return or when the field loses focus (unparsable text puts the current value back), so typing a number no longer rebuilds the buffer per digit. Outside changes still show when the field is not being edited. Test: the commit-time parsing (grouping separators, bad input). The typing behavior itself needs a window and keyboard, so it is not unit-tested; worth a quick try in the app.

---

## 149: SDF collider type

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:m, subtask
created: 2026-10-19T15:24:48Z
updated: 2026-10-19T20:14:55Z
closed: 2026-10-19T20:14:55Z
+++

Add a Collider case for a baked signed distance field: a distance grid (resolution, origin, spacing, distances as Float, negative inside) plus a transform, uploaded once as a 3D texture (r32Float or r16Float) and cached per grid. Saved in effect files (the grid as data). No collision yet; drawn as its bounds box in debug wireframes.

Acceptance: a grid round-trips through Codable; the runtime makes and reuses one texture per grid; the wireframe shows the bounds.

Part of #2.

- `2026-10-19T20:14:55Z`: Done: Collider.Shape.signedDistanceField(SignedDistanceField, center:rotation:) uses SwiftMesh's grid type (local space, placed like a box). Effect files store kind signedDistanceField with the grid's origin, spacing, resolution, and values as base64 little-endian Float32; decoding rejects resolutions under 2, over 256^3 samples, overflow, or a values size that does not match (SignedDistanceField's init would trap). The runtime keeps one r32Float 3D texture per grid (updateSignedDistanceFieldTextures in simulate), reused while colliders keep the grid and dropped when none do; equality is quick for copies of one grid since they share storage. The kernel skips the new kind (ParticleColliderKindSignedDistanceField) until #150, before the sweeps, which would otherwise treat it as a capsule. Wireframes draw the grid's bounds box; solids draw nothing (the field has no surface). Pointer bindings, translation, animation, and spin move or turn it like a box. Demo: kind and center accessors handle it; it is not in the collider kind picker (nothing to make it from yet).

---

## 150: Particles collide with SDF colliders

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:m, subtask
depends: 149
created: 2026-10-19T15:24:48Z
updated: 2026-10-19T20:21:22Z
closed: 2026-10-19T20:21:22Z
+++

In the simulation kernel, sample each SDF collider's texture (trilinear, in the collider's local space) and push particles with negative distance out along the gradient normal, with the emitter's restitution and friction, like the analytic colliders. Fast particles that cross the surface within a step are caught by checking the start and end of the step (or a few steps along it). Category masks and collisionRadius (inflate by subtracting it from the distance) apply.

Acceptance: particles dropped on an SDF sphere rest on its surface (within a cell); fast particles do not pass through a thin SDF wall; masks and radius behave as with other colliders.

Part of #2. Depends on the SDF collider type.

- `2026-10-19T20:21:22Z`: Done: the simulation kernel binds up to PARTICLE_MAX_SIGNED_DISTANCE_FIELDS (8) field textures as array<texture3d<float>, 8> (placeholder 1x1x1 in unused slots); ColliderData carries the slot (fieldIndex) and the grid's local bounds and spacing. Contact: sample trilinear (hardware, texel centers at (i + 0.5) / n), subtract collision radius (c.radius), push out by the penetration along the gradient normal (central differences one sample apart), then the usual collide() response. Fast particles: when the end is outside, sample along the step (about one per cell, up to 32) in the collider's current frame and bisect to the surface. Outside the grid nothing collides. Tests: rest on a baked sphere within a cell, placement by center and rotation (a standing slab), 45 m/s through a 0.1-thick wall, collision radius, category mask, nothing outside the grid (half-space negative at the border). Mutation check: disabling the sub-steps or the bounds check fails the wall and outside-grid tests. Stress Test bench unchanged (~5.5 ms frame).

---

## 151: Bake SDF colliders from SwiftMesh meshes

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:s, subtask
depends: 149
created: 2026-10-19T15:24:48Z
updated: 2026-10-19T20:27:10Z
closed: 2026-10-19T20:27:10Z
+++

Add Collider.sdf(mesh:resolution:padding:) that bakes a SwiftMesh mesh with SwiftMesh's signed distance baking (SwiftMesh #180) and wraps the grid in the SDF collider. CPU bake, once per mesh.

Acceptance: an SDF baked from a SwiftMesh cube matches the cube's analytic distance within a cell; particles collide with a baked teapot (golden image).

Part of #2. Depends on the SDF collider type and SwiftMesh #180.

- `2026-10-19T20:01:22Z`: Unblocked: SwiftMesh 0.0.11 has SwiftMesh #176-#180 (Mesh.bounds, TriangleBVH, closest point and distance, winding-number contains, Mesh.signedDistanceField(resolution:padding:bvh:) returning SignedDistanceField: origin, spacing, resolution, values x-fastest). The package now resolves 0.0.11.
- `2026-10-19T20:27:10Z`: Done: Collider.signedDistanceField(mesh:resolution:padding:center:rotation:categoryBitMask:) bakes with SwiftMesh's Mesh.signedDistanceField. resolution is samples along the longest side (default 64), other sides get about the same spacing (cube cells), padding is in cells (default 2) so the edge is outside the mesh; nil for a mesh with no triangles. Tests: a baked unit cube is within one cell of the exact box distance at every sample (and positive at the padded edge); grid sizing and padding; empty mesh. Golden sand-on-baked-teapot: sand rains on a SwiftMesh teapot (64 samples, turned so the spout is side on). The sand rests on the lid and body; the narrow, curved spout and handle shed it, but show as their shadow in the sand on the floor. (A probe showed the model's spout is along z, hence the turn.)

---

## 152: Moving SDF colliders for scene-graph nodes

+++
status: closed
priority: medium
kind: feature
labels: area:collision, effort:s, subtask
depends: 150
created: 2026-10-19T15:24:48Z
updated: 2026-10-19T20:38:51Z
closed: 2026-10-19T20:38:51Z
+++

Let SDF colliders take a new transform each frame (translation and rotation), with velocity and angular velocity from the motion between frames, so moving and spinning meshes push particles like the other colliders. This is the path MetalSprocketsSceneGraph needs for node geometry. Add a sample preset with a moving mesh collider.

Acceptance: a moving SDF collider carries resting particles along; a spinning one flings them; the preset has a preview and golden image.

Part of #2. Depends on particles colliding with SDF colliders.

- `2026-10-19T20:38:51Z`: Done: distance field colliders get angular velocity from rotation changes (like boxes), on top of the velocity from center changes, so turning meshes fling particles. Collider.placed(by:) takes a node's world matrix (translation and rotation; scale dropped, since baked distances do not scale) for hosts that pass colliders to simulate(colliders:) each frame. Tests: a sliding field carries resting particles; a spinning one flings them (and a still one does not); placed(by:) decomposes a scaled, rotated, moved matrix. Removing the distance field case from motion(from:) fails the spin test. Preset Spinning Teapot: a 32-sample baked SwiftMesh teapot (77 KB JSON) spun by ColliderSpin under falling sand, with golden, preview, and Demos.md section.

---

## 153: Effect files show "_0" keys for enum cases with unlabeled values

+++
status: closed
priority: medium
kind: enhancement
labels: area:simulation, effort:s
created: 2026-10-19T15:47:44Z
updated: 2026-10-19T16:13:02Z
closed: 2026-10-19T16:13:02Z
+++

Swift's synthesized Codable writes an enum case's unlabeled associated value under the key "_0", so effect files contain blobs like:

    "collider": { "_0": 0 }
    "burst": { "_0": 150 }
    "event": { "_0": "boom" }

They are hard to read and to hand-edit, and the key name is an implementation detail.

Cases that do it today:
- PointerBinding: collider(Int), forceField(Int), emitter(Int) (PointerBinding.swift)
- EmissionTrigger.Condition.event(String) and EmissionTrigger.Action.burst(Int) (EmissionTrigger.swift)
Seen in the sample presets Pointer Stir, Dunk, and Bumper.

Fix: give the values labels (for example collider(index:), burst(count:), event(name:)), so they encode as { "index": 0 }, or write custom Codable for a shorter form like "collider": 0. Keep reading the old "_0" form so saved effects still load, and migrate the sample presets. A test (or DecodingCoverageTests) could fail on any "_0" key in encoded effects so it does not come back.

- `2026-10-19T16:13:02Z`: Fixed: PointerBinding writes { "index": n }, EmissionTrigger.Action.burst writes { "count": n }, and EmissionTrigger.Condition.event writes { "name": s }, through per-case CodingKeys; the Swift API is unchanged (.collider(3), .burst(150)). Hand-written decoders read both the new names and the old "_0", so saved effects still load. The three affected presets (Pointer Stir, Dunk, Bumper) were migrated with jq and Prettier; goldens unchanged. EnumKeyTests checks the names, round trips every case, reads old files, and fails if any sample preset (file or re-encoded) contains "_0".

---

## 154: 2D mode shows nothing for scenes not made in points

+++
status: closed
priority: high
kind: bug
labels: area:rendering, effort:s
created: 2026-10-19T16:29:31Z
updated: 2026-10-19T16:32:16Z
closed: 2026-10-19T16:32:16Z
+++

Turning on 2D (ParticleSystem.is2D) for a normal 3D scene makes everything vanish. The .system camera becomes the overlay camera (one unit is one point, origin top left, y down), so a scene a few units across is a speck in the top-left corner and its gravity carries particles off the top. particles-render and video export use .lookAt, so they still show the 3D perspective view: the app and the CLI disagree.

Fix (agreed with the user): in 2D, the scene cameras (.system and .lookAt) become a flat front-on orthographic view fitted to the scene: centered on the camera target, looking along -z, y up, showing what the 3D camera shows at the target distance. .overlay stays as it is, for effects over an app's UI in points. The demo's 2D toggle uses the fitted view, and the CLI follows the same rule.

- `2026-10-19T16:32:16Z`: Fixed: in 2D, .system and .lookAt give an orthographic front view (looking along -z, y up) centered on the target and scaled to match the perspective view at the target distance; .overlay is unchanged for UI effects in points. The demo's 2D view uses it from the orbit camera's eye; Add Emitter no longer uses default2D in 2D, since the view is in scene units. particles-render follows the same rule (Fountain with is2D renders a flat, centered view). Test: TwoDModeTests.sceneCamerasShowAFlatFrontViewIn2D (centered target, y up, scale at the target, orthographic); demo test updated.

---

## 155: Foil particles: glinting, iridescent confetti

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T19:16:26Z
updated: 2026-10-19T22:35:26Z
closed: 2026-10-19T22:35:26Z
+++

Particles that render like metallic foil: tumbling pieces that flash when they catch the light and shift color with viewing angle, for confetti, tinsel, and glitter.

Today lit particles get only diffuse light per vertex with no normal (particleLight(..., float3(0))), so they look matte, and sprites do not carry a facing direction into shading.

Scope:
- A per-particle facing normal for sprites that tumble (from the particle's rotation and the orientation mode), passed to the fragment shader.
- A foil shading mode on the emitter: a sharp specular glint (Blinn-Phong, against the scene lights and particle lights; a fixed fake light in 2D, e.g. from the top left), a thin-film/iridescent tint from the view angle (gold-pink, holographic), and darkening edge-on.
- Optional sparkle: a short-lived star sub-emitter when a piece glints (may need a glint event).
- A Foil Confetti preset (3D) and a 2D version, with goldens.

Out of scope: a bloom post-process (the library has none); fake halos with additive star sprites instead.

Acceptance: a tumbling foil piece's brightness peaks when its normal bisects the light and view directions; color changes with angle; presets look like foil confetti in particles-render.

- `2026-10-19T22:35:25Z`: Done for mesh particles: ParticleFoil (glint, shininess, iridescence) on ParticleEmitter.foil, saved in effect files. In particleMeshVertex, foilColor gives a two-sided Blinn-Phong glint from each scene light and particle light (a fixed light above and in front when there are none), a thin-film hue shift with viewing angle, and darkening edge-on; per vertex, so a flat piece flashes as a whole. Presets Foil Confetti and Foil Confetti 2D (coin meshes, varied hues, fast tumbling), with goldens, previews, and Demos.md sections; inspector Foil switch and sliders for mesh particles. Test: one coin swept through 36 angles; with foil the brightest angle is far above the median and well above plain shading's variation, and the color balance changes with angle. Not done (filed as #171): foil for sprites (they have no facing direction) and sparkle sub-emitters on glints. Existing goldens unchanged (foil is off unless set).

---

## 156: Spun colliders fling particles after a long frame (app to background and back)

+++
status: closed
priority: medium
kind: bug
labels: area:collision, effort:xs
created: 2026-10-19T20:59:29Z
closed: 2026-10-19T20:59:29Z
+++

Spinning Teapot sometimes flings sand, notably when the app goes to the background and back. ParticlePlayer advanced its clock (which turns spun and animated colliders) by the whole frame, while ParticleSystemRuntime caps each step at 1/30 s and derives collider spin over the capped step. After a long frame the collider jumped ahead of the particles and looked many times faster, so it threw them.

- `2026-10-19T20:59:29Z`: Fixed: ParticleSystemRuntime.maximumStep (1/30 s) is the one cap; FramePlan uses it and ParticlePlayer advances its clock by min(deltaTime, maximumStep) * speedFactor. Test aLongFrameKeepsSpunCollidersInStep: after a 0.5 s frame the player's clock matches the simulation's (failed before the fix), and sand on a spinning slab stays on it. User confirmed the symptom tracks background/foreground switches; not checked in the app after the fix.
- `2026-10-19T21:04:33Z`: Still happened after the first fix, less badly (user). Second cause, found with a probe (Spinning Teapot for 10 s; fastest sideways sand speed per frame): steady 1/60 frames peak ~2.3 m/s (the designed flinging off spout and handle); jittered frames spiked to 5.6-7 m/s right after very short frames. ParticlePlayer placed colliders at its clock before advancing it, so each step got the previous frame's collider motion divided by this frame's deltaTime (0.03 s of turn over 0.004 s is 7.5 times the spin). The player now advances its clock first; the probe's jittered peak dropped to 2.31 m/s, matching steady. Test unevenFramesDoNotSpeedUpSpunColliders (alternating 0.03/0.004 s frames; sand on a 0.5 rad/s slab stays under 0.3 m/s). Animated preset goldens moved one frame (Fountain, Magic Trail, Portal, Paddle Wheel, Pointer Stir, Spinning Teapot, Snow Globe; reviewed side by side), and the hand-written-loop test uses end-of-step times. Not checked in the app.
- `2026-10-19T21:05:21Z`: User confirmed fixed in the app.

---

## 157: Fast particles sink into or slide off thin parts of distance field colliders

+++
status: closed
priority: medium
kind: bug
labels: area:collision, effort:m
created: 2026-10-19T21:29:36Z
updated: 2026-10-19T21:47:12Z
closed: 2026-10-19T21:47:12Z
+++

Found while making Sand on Letters (sand on extruded 'SDF' text, 96-sample grid, letters 0.35 tall). After 5 s, of the sand that landed: about 8 000 grains rest on the letter tops, about 45 000 on the floor beside them, and about 3 400 on the floor inside a letter's footprint, inside the solid. The letters cover roughly a quarter of the pour area, so far fewer stay on top than should, and some end up inside.

What I measured and tried:
- The baked field is right (columns through letters go positive, negative, positive at the expected heights).
- With 'METAL' at a smaller size the strokes were only about two cells wide and almost no sand stayed on top; bigger letters helped. So thin parts, relative to the grid, are part of it: normals near a thin part's top blend the top and its sides.
- Falling grains move 3 to 4 cells per step. fieldContact pushes a particle that ends inside out along the normal at its end point; deep inside a thin part that can be a side or the far face. Responding at the entry point along the path instead (when the step started outside) doubled the grains on top (about 16 000) and cut those inside to about 1 200, but broke aSpinningFieldFlingsParticles (resting grains on a spinning collider were put back at their entry point each step). Limiting it to steps that started more than half a cell clear of the surface kept the tests but lost most of the gain. Reverted; I do not fully understand why the unconditional version helped.

Ideas: entry-point response with the collider's motion accounted for (so resting contacts are not reset), smaller steps for fast particles near fields, or normals from a wider stencil near thin parts.

- `2026-10-19T21:40:28Z`: Related: #166 (distance field colliders in the inspector): its bake resolution setting is one of the levers here.
- `2026-10-19T21:47:12Z`: Fixed. Two changes in fieldContact: (1) a particle that ends a step inside the field but started outside responds where its path went in (bisected), not at the nearest surface to where it ended; (2) the step's start is carried by the collider's spin as well as its velocity (start + (v + w x (start - pivot)) dt). (2) is why the earlier entry-point attempt broke aSpinningFieldFlingsParticles: without the spin, a grain resting on a turning collider seemed to start off its surface, so every step counted as a new entry and reset it. Test fastParticlesRestOnTopOfThinParts (9 m/s onto a fin two cells wide; failed at 2 of 3 drop points before). Sand on Letters: grains on the letter tops 8 000 -> 15 900, inside the letters 3 400 -> 1 160 (not zero; some still get in, likely at stroke edges). Goldens moved for the five distance-field scenes: sand now rests on the baked teapot's spout and handle, and the umbrella's dry patch is crisp.
- `2026-10-20T00:07:26Z`: Fixed: on entry, the particle goes to the entry point plus the rest of the step's motion along the surface, under Coulomb friction (kept only beyond friction times the part into the surface). Sliding particles keep their speed; resting ones stay put, so thin parts still hold sand (a tilted normal near a thin part would otherwise walk grains off its edge, which a first attempt at pushing shallow dips straight out did). Test particlesSlideDownSlopesAtFullSpeed: a ball slides as far down a tilted distance-field slab as down the same analytic box (0.047 vs 0.23 before, about five times slower). Marble Run measured: mean marble speed 1.55-1.70 m/s over 6 s, matching the pre-#157 behavior (1.54-1.68). The #157 thin-part and spinning-fling tests still pass; five distance-field goldens moved slightly (reviewed: sand still rests on the teapot's spout and handle).
- `2026-10-20T00:08:00Z`: Correction: the 'Fixed: on entry...' comment above belongs to #176 (a regression from this issue's fix); posted here by mistake.

---

## 158: Inside the Teapot drops below 60 fps: flocking is slow in dense piles

+++
status: closed
priority: medium
kind: bug
labels: area:performance, effort:m
created: 2026-10-19T21:35:57Z
updated: 2026-10-19T21:54:26Z
closed: 2026-10-19T21:54:26Z
+++

Inside the Teapot (6 600 particles) takes about 5 ms of GPU a frame (particles-bench: 6.12 ms GPU, 16 ms worst), when Stress Test does 2 million particles in about 4.4 ms. In the app it falls below 60 fps.

Measured with copies of the preset, one part removed at a time (particles-render, last-frame GPU, two runs each):
- full preset: ~4.9 ms
- no flocking on the beads: ~0.4 ms
- no distance field collider (beads fall away and spread out): ~0.4 ms
- no outline-dots layer: ~8 ms (not understood)

The beads use flocking with separation only, as a stand-in for particle-particle collision (without it they stack into one point). My guess, not checked in the shader: the cost grows with how densely the particles pack, not their count. In a pile each hash-grid cell holds hundreds of beads, and the neighbor search may visit all of them although maxNeighbors (16) caps how many are used. Why removing the outline layer makes it slower is unexplained.

Fix ideas: stop the neighbor search once maxNeighbors are found, or cap the particles visited per cell; or give the preset a cheaper stand-in for separation.

- `2026-10-19T21:40:28Z`: Related: #159 (flocking in the inspector) would let the preset's flocking be turned off or tuned from the UI.
- `2026-10-19T21:54:25Z`: Fixed. The cost was the per-cell sort (flockSortCells): one thread per cell ran an insertion sort, so a crowded cell (most of the 3 000 beads in a pile) cost its count squared on a single thread. Not the neighbor search: maxNeighbors 4 did not help, and my first guess (search visits every particle in a cell) was wrong, since the search already stops at maxNeighbors. Now one thread per particle counts the earlier particles in its cell and writes itself to that place: the same slot order (so results and goldens are unchanged), with the work spread over the cell's particles. The scatter writes to a new scatteredOffsets buffer. Rendered-frame GPU time for the preset: 2-5 ms before (peaks as the pile packs), about 1.1 ms after; particles-bench: 6.12 -> 1.28 ms GPU, worst frame 16.1 -> 3.8 ms. Test flockingInADensePileStaysCheap compares the preset's average GPU time with and without flocking; it fails with the old kernel and passes with the new. A first test with stationary particles packed in one cell passed even before the fix (they land in each cell already in order, which is insertion sort's best case), so it was replaced.

---

## 159: Inspector: flocking

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T21:37:16Z
updated: 2026-10-19T21:57:05Z
closed: 2026-10-19T21:57:05Z
+++

ParticleEmitter.flocking (ParticleFlocking): an on/off switch plus radius, separationRadius, separation, alignment, cohesion, speedRange, maxNeighbors. Murmuration and Inside the Teapot use it and cannot be changed or turned off (see #158).

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T21:40:28Z`: Related: #158 (Inside the Teapot's flocking is slow in dense piles).
- `2026-10-19T21:57:05Z`: Done: a Flocking section in the emitter inspector, after Collision: a Flocks switch (on starts from ParticleFlocking's defaults, or the settings it had) and sliders for neighbor radius, separation radius, separation, alignment, cohesion, minimum and maximum speed (kept ordered), and neighbors (maxNeighbors, at least 1). Built on computed properties (isFlocking, editableFlocking, minimumSpeed, maximumSpeed, neighborLimit), no closure bindings. Tests: on/off and edits, speed bounds. Checked the layout with an offscreen snapshot; the switch drew in its off style there although flocking was on, likely a snapshot artifact, worth a look in the app.

---

## 160: Inspector: color by speed, by position, alternate colors, color image

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T21:37:16Z
updated: 2026-10-19T22:00:54Z
closed: 2026-10-19T22:00:54Z
+++

ParticleEmitter.colorBySpeed and colorBySpeedRange; colorByPosition, colorByPositionStart, colorByPositionEnd, colorByPositionAtBirth; alternateColorOverLife; colorImage (ParticleColorImage, an image picker).

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:00:54Z`: Done: a Color Effects group in Appearance. Color by Speed (switch, gradient, slow and fast speeds kept ordered), Color by Position (switch, gradient, start and end points, sample at birth), Alternate Colors (switch; starts as a copy of Color so nothing changes until edited), Color Image (Choose/Replace with a file picker, Remove, and origin, width, height; a new image is upright in XY at (0, 1.5, 0), 4 wide; a replacement keeps the old placement; non-images are rejected with an alert). Tests cover each switch and the image choice. Layout checked with an offscreen snapshot.

---

## 161: Inspector: trails and ribbons

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T21:37:16Z
updated: 2026-10-19T22:02:27Z
closed: 2026-10-19T22:02:27Z
+++

ParticleEmitter.trail (ParticleTrail: pointCount, pointInterval, fades, tapers) and ribbon (ParticleRibbon: tapers), each with an on/off switch.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:02:27Z`: Done: a Trails and Ribbons group in Appearance. Trail (switch; points 2-64, point interval, tapers, fades) and Ribbon (switch; tapers), with help noting the ribbon takes the place of trails and mesh particles. Test covers both switches and the point-count limits. Same pattern as #159/#160, so no new snapshot.

---

## 162: Inspector: LOD and culling

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T21:37:16Z
updated: 2026-10-19T22:03:36Z
closed: 2026-10-19T22:03:36Z
+++

ParticleEmitter.cullingRadius, simulatesWhenCulled, lodNearDistance, lodFarDistance, lodFarRateScale, lodScalesSize, minimumScreenSize.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:03:36Z`: Done: a Level of Detail section after Flocking: full rate within, reduced rate at, far rate, grow when thinned, minimum screen size, culling radius, and simulate when culled (shown when the culling radius is above 0), each with help text. No new test: the controls bind straight to stored settings with no adapter logic to test; the library's LOD and culling tests cover the behavior. Demo tests, build, and lint pass.

---

## 163: Inspector: collision extras and particle events

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:s
created: 2026-10-19T21:37:17Z
updated: 2026-10-19T22:04:44Z
closed: 2026-10-19T22:04:44Z
+++

ParticleEmitter.collisionRadius, collidesWithSceneDepth, softness, reportsCollisions, reportsDeaths.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:04:44Z`: Done: Collision section gains Radius (collisionRadius), Collide with Scene Depth, Report Collisions, Report Deaths; Appearance gains Softness. Each has help text. No new test: the controls bind straight to stored settings with no adapter logic; the library tests cover collision radius, scene depth collision, soft particles, and events. Demo tests, build, and lint pass.

---

## 164: Inspector: particle lights and scene lighting

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T21:37:17Z
updated: 2026-10-19T22:08:43Z
closed: 2026-10-19T22:08:43Z
+++

ParticleEmitter.light (ParticleLight: intensity, picksBrightest, on/off); the scene's lights (ParticleSystem.lights: add, remove, edit) and ambientLight.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:08:43Z`: Done. Emitter: a Particle Lights group in Appearance (Emit Light switch; lights count, color, intensity, range, brightest particles). Scene: a Lighting section after World (ambient color; each light in a disclosure with kind directional/point, color, intensity, position and range or direction, and Remove; Add Light up to PARTICLE_MAX_LIGHTS). The model now owns lights (as LightItems with ids, like colliders) and ambientLight and applies them to the runtime on change; before, it wrote them straight into the runtime, where the UI could not see them. Colors are linear sRGB via a Color view of SIMD3<Float>; values above 1 are clipped by the picker (use intensity for brighter). Tests: particle light switch and count floor, light accessors keep the other fields and ignore the other kind's, scene lights and ambient reach the saved effect; every preset still round-trips.

---

## 165: Inspector: mesh particles, emitter meshes, point caches, emitter images

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T21:37:17Z
updated: 2026-10-19T22:13:53Z
closed: 2026-10-19T22:13:53Z
+++

Inputs that need data, not just numbers: ParticleEmitter.particleMesh (mesh particles); EmitterDescription.mesh (for the mesh shape), points (point caches), image (EmitterImage: data, pointCount, weighting, usesColors), meshDeformation; ImageSequence.initialFrame. Pickers could offer SwiftMesh primitives, the teapot, and files (images, OBJ).

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:13:53Z`: Done. Appearance: Draw As (sprite, cube, tetrahedron, coin; a custom triangle mesh from a saved effect shows as Custom Mesh and is kept). Sprite sheet: Start Frame (initialFrame). New Shape Source section, shown for the Mesh and Point Cache shapes: Mesh picks a SwiftMesh teapot, sphere, torus, cube, or cylinder, or the first mesh in a model file Model I/O reads (OBJ, USD, ...), with a Wave deformation (amplitude, wavelength, speed); Point Cache takes points from an image (points, width, weighting, use image colors; Replace keeps the settings) or shows an existing point cache's size, with Clear. Tests: Draw As mapping, built-in meshes, model file loading (an OBJ cube, and a file with no mesh), wave edits, image choice. The model-file test caught that MDLAsset needs an MTKMeshBufferAllocator for SwiftMesh's MetalKit conversion. Not done: making a point cache from scratch other than from an image (none of the presets need it).

---

## 166: Inspector: distance field colliders

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T21:37:17Z
updated: 2026-10-19T22:17:33Z
closed: 2026-10-19T22:17:33Z
+++

Distance field colliders (Collider.Shape.signedDistanceField) are not in the collider kind picker, and there is no way to bake one in the demo. Offer baking from a SwiftMesh primitive, the teapot, extruded text, or an OBJ file, with resolution and padding; show the grid size and bake time.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T21:40:28Z`: Related: #157: thin parts need several grid cells across, so the bake UI should make the resolution and cell size visible.
- `2026-10-19T22:17:33Z`: Done. Distance Field is in the collider kind picker; choosing it bakes a small teapot (32 samples) at the collider's center. The editor shows center, turn (about +Y), the grid's samples and cell size (with a note that parts thinner than a couple of cells blur, see #157), and a Bake group: from a SwiftMesh teapot, sphere, torus, cube, or cylinder, extruded text, or a model file; resolution 16-128, padding 0-8 cells, Inside Out (negated, a container); Bake runs off the main thread and shows how long it took, keeping the collider's place and turn. Tests: switching kind bakes in place, each source bakes (positive at the padded corner), Inside Out flips it, turn about Y. Layout checked with an offscreen snapshot.

---

## 167: Inspector: user functions

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T21:37:17Z
updated: 2026-10-19T22:21:49Z
closed: 2026-10-19T22:21:49Z
+++

ParticleEmitter.updateFunction, spawnFunction, collisionFunction, deathFunction (ParticleFunction: source, parameters) and customAttributeCount: a source editor per slot with compile errors (ParticleFunction.errorDescription) and parameter fields.

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:21:49Z`: Done: a User Functions section after Level of Detail. Per slot (update, spawn, collision, death) a disclosure (marked with a dot when set): Enabled switch (starts from a template that compiles, with a commented example using parameters[0].x), function name and a monospaced source editor kept as drafts, Compile & Apply (checks with ParticleFunction.validate on the device first; the compiler's message shows in red and nothing is applied on failure) and Revert, and parameters (four numbers each, add and remove; apply at once). Custom Attributes 1-4. Drafts reset when another emitter is selected. Tests: every template compiles and runs in a runtime for a few frames; slot switches; attribute count limits; bad code is caught. Snapshot only checked the collapsed row (the disclosure did not expand offscreen), so the expanded editor's layout is unchecked; worth a look in the app.

---

## 168: Inspector: scene-level animation and events

+++
status: closed
priority: medium
kind: enhancement
labels: area:editor, effort:m
created: 2026-10-19T21:37:18Z
updated: 2026-10-19T22:26:59Z
closed: 2026-10-19T22:26:59Z
+++

ParticleSystem.colliderSpins (spin per collider: axis, speed), eventBursts (EventBurst: sourceLayer, targetLayer, and the rest; the model keeps them but notes there is no editor), trackedObjects (name and motion), and pointerMotion (the scripted pointer path used when the mouse is away).

Found by an audit of every public setting in the description types against the demo sources: these are loaded and saved, but nothing in the UI shows or edits them.

- `2026-10-19T22:26:59Z`: Done. Collider inspector: Spins switch with axis and speed. Scene inspector: Event Bursts (list; when [emitter]'s particles [hit a collider / die], burst [count] from [emitter]; warns when the source emitter does not report that event, since EventBurst needs reportsCollisions or reportsDeaths), Tracked Objects (name and path; add and remove), and Scripted Pointer (the path pointer-bound items follow without the mouse). The model now keeps spins on ColliderItem, bursts as EventBurstItem by emitter id, and tracked objects as named items, converting to the saved index/dictionary forms on save and back on load, so removing or reordering colliders or emitters keeps them attached (before, colliderSpins and eventBursts were index arrays that would shift). Tests: bursts follow their emitters through removals and drop when a target goes; spins follow their collider; tracked object names; every preset still round-trips. Not snapshot-checked (same controls as other sections).

---

## 169: No base64 blobs in effect JSON; reference external files

+++
status: closed
priority: medium
kind: enhancement
labels: area:api, effort:l
created: 2026-10-19T21:50:25Z
updated: 2026-10-20T02:01:06Z
closed: 2026-10-20T02:01:06Z
+++

Effect JSON embeds large binary data as base64 strings:

- Signed distance field `values` (float32): inside-the-teapot, spinning-teapot, marble-run, sand-on-letters, snow-globe, umbrella.
- PNG `data`: butterfly-dust (`image`), living-picture (`colorImage`).

Replace these with references to files. A reference is either:

- a name, resolved next to the JSON file or through the bundle, or
- a URL.

Move the existing blobs out to files (e.g. raw float32 `.bin` for fields, `.png` for images) and update the presets. Consider doing the same for inline mesh arrays (`meshPositions`/`meshTriangles`), which make inside-the-teapot.json ~9800 lines.

- `2026-10-20T01:44:21Z`: Decisions (user): (1) the app saves effects as a package (a folder, e.g. Name.particles/ with effect.json plus image and field files); bundle presets use the same layout, resources next to their JSON. (2) No inline base64 any more: references only; old files with inline data fail with a clear error. (3) URL references are file URLs only, loaded during decoding; remote http(s) deferred. Plan: library reference type and coding plumbing (encoder collects named resources, decoder resolves names against the effect's folder), applied to distance field values, EmitterImage.data, ParticleColorImage.data; then migrate the presets; then the demo's open/save as packages.
- `2026-10-20T02:01:06Z`: Done. EffectResources stores binary data as files: encoding names each by a prefix and the first 8 hex digits of its SHA-256 (stable across saves), decoding resolves plain names in the effect's folder (no paths, nothing outside it) or absolute file URLs; in-memory stores for tests. Applied to distance field values (raw little-endian Float32, .bin; origin, spacing, resolution stay in the JSON), EmitterImage.data and ParticleColorImage.data (extension from the image's bytes). ParticleSystem(contentsOf:) reads a .particles package (folder with effect.json) or a JSON file with its files next to it; write(to:) writes either; encoded(), init(json:resources:), and package FileWrappers for documents. Inline base64 is no longer read (a clear error, per the decision). Presets migrated: 6 fields and 2 images moved to files, preset JSON 1.9 MB -> about 0.35 MB plus 1.1 MB of binary files; every golden unchanged. Demo: Open accepts packages and JSON; Save writes a package via a FileDocument (ParticleEffectDocument); the app declares the io.schwa.metalsprocketsparticles.effect package type (.particles). ParticleSystem's Transferable conformance is removed: its FileRepresentation of a directory failed to export (CoreTransferable 'unknown reason'), so it would not have worked. Tests: data saved as files, stable names, package and side-file round trips on disk, file wrapper round trip, bad references (inline base64, ../, missing, no store) are errors, file URLs load. CLI checked: --save-effect to a .particles package and --effect from it renders pixel-identical. Meshes (meshPositions/meshTriangles) remain inline; that is #170.

---

## 170: Emitter meshes as file references (OBJ/PLY) instead of inline JSON arrays

+++
status: closed
priority: medium
kind: enhancement
labels: area:api, effort:m
depends: 169
created: 2026-10-19T21:51:47Z
updated: 2026-10-20T02:15:05Z
closed: 2026-10-20T02:15:05Z
+++

Emitter meshes are saved inline in effect JSON as `meshPositions` and `meshTriangles` number arrays (see `EmitterDescription` Codable). This makes presets huge: inside-the-teapot.json is ~9800 lines, mostly the teapot.

Store the mesh as a file reference instead, using the same reference scheme as #169: a name (next to the JSON or in the bundle) or a URL. Load OBJ and PLY (e.g. via ModelIO `MDLAsset`, or SwiftMesh if it has loaders).

Move the existing inline meshes in the presets out to files. Decide whether to keep reading the inline arrays for old files.

- `2026-10-20T02:15:05Z`: Done. Emitter meshes are saved as OBJ files through EffectResources (mesh-<hash>.obj, positions and triangles, floats in shortest exact form), read back exactly by our own OBJ reader (v and f lines; polygons, v/vt/vn, negative indices); other formats Model I/O reads (PLY, USD) load through it. Inline meshPositions/meshTriangles are no longer read (a clear error), following #169's decision. Presets migrated: 8 meshes in 6 presets to 7 files (Teapot's two layers share one); inside-the-teapot.json went from ~9800 lines to 279; every golden unchanged. Tests: exact round trip, out-of-range and faceless OBJ are errors, OBJ from other tools, PLY, inline meshes rejected. CLI: Teapot saved as a package and rendered from it is pixel-identical. Point caches and custom particle meshes are still inline: #177.

---

## 171: Foil shading for tumbling sprites, and sparkles on glints

+++
status: closed
priority: low
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T22:35:25Z
updated: 2026-10-19T23:11:53Z
closed: 2026-10-19T23:11:53Z
+++

Follow-up to #155, which added foil (ParticleEmitter.foil) for mesh particles only. Not done there:
- Sprites: they always face the camera and only spin in their plane, so they have no facing direction for the glint. Needs a per-particle 3D orientation (tumble axis and angle) carried to the sprite vertex shader, turning the quad (like mesh particles) or at least its shading normal.
- Sparkles: a short-lived star sub-emitter when a piece glints. Needs a glint event (the glint is computed at draw time, not in the simulation), or computing the glint term in the simulation kernel to fire a sub-emitter.

Workaround today: use mesh particles (Draw As Coin) for foil confetti, as the Foil Confetti presets do.

- `2026-10-19T22:40:04Z`: Related: #172 makes shading pluggable; foil for sprites becomes giving sprites a real tumbling normal in ShadingInput, and foil itself becomes a built-in shading model.
- `2026-10-19T23:01:44Z`: Sprites done (first half): ParticleOrientation.tumbling makes each sprite a world-space card turned about its own random axis (the same per-particle axis mesh particles use) by its spin angle, so it has a real facing normal. The sprite vertex shader now applies foil with the quad's own plane normal in every orientation (a tumbling card flashes; a billboard faces the camera, so its glint stays put). New Confetti sprite (a flat rectangle). Foil Confetti and Foil Confetti 2D now use tumbling confetti sprites, no coins. Inspector: Tumbling in the orientation picker; the Foil switch shows for sprites too. Tests: a tumbling card glints and shifts color like a mesh particle; a foil billboard does not glint; tumbling round-trips. Other goldens unchanged. Sparkles on glints next.
- `2026-10-19T23:11:53Z`: Sparkles done (second half): SubEmitter.Occasion.onGlint(threshold:) fires when the parent's foil glint, as the camera sees it, rises past the threshold during a step. The simulation computes the same glint the renderer draws: the particle's tumble axis (same per-particle hash) and its rotation before and after the step, the camera from simulate(view:) (ParticlePlayer passes it), the first scene light or foil's fixed light, and the foil's shininess. Without a view nothing fires. Foil Confetti and Foil Confetti 2D sparkle with a short white star at each flash. Inspector: On Glint in the sub-emitter occasion picker with a threshold. Tests: a spinning foil card fires with a camera, not without one, and not when it does not spin; onGlint round-trips. Goldens updated for the two presets only.

---

## 172: Pluggable shading: one shading function per emitter, with built-in models

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
created: 2026-10-19T22:40:03Z
updated: 2026-10-20T21:52:32Z
closed: 2026-10-20T21:52:32Z
+++

Today lighting is special cases in the vertex shaders (unlit, isLit diffuse, and foil for mesh particles, #155). Make it one shading function slot per emitter instead, like user functions (#167) for the simulation: the mesh and sprite vertex shaders call a visible function with a ShadingInput (world position, normal, to-camera, base color, ambient and lights, particle age and custom attributes) that returns a color.

Port the built-ins onto it: ShadingModel.unlit, .lit (today's isLit), .foil(glint:shininess:iridescence:) (today's ParticleEmitter.foil). Keep isLit and foil decoding in old effect files (map them to the model). Sprites get today's fake sphere normal in the input.

Acceptance: every existing golden unchanged; foil and lit presets look the same; ShadingModel round-trips in effect files; old files with isLit or foil load as .lit or .foil. Per vertex only; a fragment variant is a separate issue.

- `2026-10-19T22:40:04Z`: Related: #171 (foil for tumbling sprites, sparkles on glints) and #155 (foil, which becomes .foil here).
- `2026-10-20T02:31:44Z`: Related: #179, the composable-modules refactor; this becomes part of its rendering stage.
- `2026-10-20T18:26:32Z`: Related: #193 (render modules) builds on this; if the module refactor (#179) lands first, this may be reshaped as render modules.
- `2026-10-20T21:52:33Z`: ShadingModule (render, required) with ShadingModel .unlit/.lit/.foil(settings:)/.custom(function:). Vertex shaders call one [[visible]] function per vertex (ShadingInput, ShadingScene, lights, particle lights, parameters). Built-ins hold the old inline math: all goldens, FoilTests, LightingTests unchanged. Unlit sprites/trails/ribbons compile the call out (function constant particleHasShading), meshes always call. Custom functions compile after ShadingModule.prelude; demo has a model picker and code editor. Format 4: old foil module / sprite isLit load as .foil/.lit; presets migrated. Perf: render parameters collapsed into one .parameters modifier per pipeline (deep modifier chains cost CPU); on battery, Stress Test within ~0.2 ms of before (noisy), Lantern unchanged. Not done: per-pixel (#174); foil sprites' glint stays in the fragment shader.

---

## 173: Custom shading functions (user Metal code)

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, area:editor, effort:m
depends: 172
created: 2026-10-19T22:40:03Z
updated: 2026-10-21T01:48:56Z
closed: 2026-10-21T01:48:56Z
+++

On top of the shading function slot (#172): ShadingModel.custom(ParticleFunction-style source, name, parameters), compiled against a shading prelude that declares ShadingInput, validated like user functions. For toon, rim light, hologram, smoke tints, and the like, without library changes.

Inspector: a Shading picker (Unlit, Lit, Foil, Custom) with the Custom source editor reusing the user-function editor (#167): drafts, Compile & Apply, compiler errors.

Acceptance: a custom function that returns, say, a rim light compiles, renders (golden), round-trips; bad source is rejected before it reaches the runtime.

- `2026-10-20T18:26:32Z`: Related: #193 (render modules) builds on this; if the module refactor (#179) lands first, this may be reshaped as render modules.
- `2026-10-21T01:48:57Z`: Delivered with #172: ShadingModel.custom(function:) compiled after ShadingModule.prelude; inspector Shading picker with a Custom code editor (drafts, Compile & Apply, errors). Added: golden custom-rim-light-shading (the rim-light template), a round-trip test (custom model + perPixel survive saving), and rejection tests (bad source and simulation-style source fail validateShading).

---

## 174: Per-pixel shading functions

+++
status: closed
priority: medium
kind: feature
labels: area:rendering, effort:m
depends: 172
created: 2026-10-19T22:40:04Z
updated: 2026-10-20T22:53:10Z
closed: 2026-10-20T22:53:10Z
+++

A fragment-stage variant of the shading function (#172): the same ShadingInput interpolated per pixel, so glints and rim light on large meshes are smooth instead of faceted (per vertex, a flat face flashes as a whole). Costs a function call per pixel; opt in per emitter.

Acceptance: a large foil mesh glints smoothly across a face (golden); per-vertex stays the default and unchanged.

- `2026-10-20T02:31:44Z`: Related: #179, the composable-modules refactor; this becomes part of its rendering stage.
- `2026-10-20T18:26:32Z`: Related: #193 (render modules) builds on this; if the module refactor (#179) lands first, this may be reshaped as render modules.
- `2026-10-20T22:42:37Z`: Implemented: ShadingModule.perPixel; the vertex shader hands the ShadingInput on (function-constant varyings, absent otherwise) and the fragment shader calls the same function. ShadingInput gained uv. Tests: custom function per pixel matches per vertex; lit per pixel is brighter at the sprite center (interpolated sphere normal). Golden for a large foil mesh waits for #175's foil model.
- `2026-10-20T22:53:10Z`: ShadingModule.perPixel: the fragment shader calls the shading function with the interpolated input. Golden foil-mesh-per-pixel: a large foil coin's reflection varies smoothly across its face. Per-vertex stays the default; all other goldens unchanged.

---

## 175: Foil should look like reflective metal, not a matte card with white highlights

+++
status: open
priority: medium
kind: enhancement
labels: area:rendering, effort:m, deferred
depends: 172
created: 2026-10-19T23:59:01Z
updated: 2026-10-21T00:23:11Z
+++

Foil (ParticleFoil, #155/#171) shades a card with its own matte color, darkens it edge-on, and adds a Blinn-Phong glint from one light. On tumbling confetti that reads as colored rectangles that turn white (per-vertex glint) or get white dots (per-pixel crinkled glint, uncommitted experiment) instead of foil. User: 'that's just white dots on the foil'.

What real foil does, and the model to build:
- Reflection takes the metal's color, not white: gold foil flashes bright gold, pink foil bright pink; white only at the hottest core.
- No matte color of its own: dark when it reflects nothing, bright and saturated when it does. The contrast is most of what reads as shiny.
- It reflects its surroundings, not one light: reflect the view direction off each facet's normal and sample a procedural environment (bright sky band, dark floor, a few soft bright patches), so a tumbling card's brightness shimmers continuously.
- Crinkle (a grid of tilted facets, per pixel) breaks the reflection into a mosaic of brighter and darker patches of the same tint: that is the sparkle, not added white points.
- Iridescence stays as a hue shift with angle, applied to the reflection.
- Sprites per pixel (crinkle); mesh particles the same model per vertex.

Acceptance: Foil Confetti reads as metallic foil in renders and in motion (cards go from near-black to bright tint as they turn, with patchy facet variation), reviewed by the user; FoilTests updated (brightness swings with angle, highlight hue follows the base color rather than white, crinkle varies brightness across a card).

Related: #172 (pluggable shading; foil could become a built-in shading model there), #174 (per-pixel shading).

- `2026-10-20T02:27:15Z`: Blocked on #172 (user): build the reflective metal model as a built-in shading model on the pluggable shading slot, not as more special-case shader code.
- `2026-10-20T02:31:44Z`: Related: #179, the composable-modules refactor; this becomes part of its rendering stage.
- `2026-10-20T18:26:33Z`: Related: #193 (render modules) builds on this; if the module refactor (#179) lands first, this may be reshaped as render modules.
- `2026-10-20T22:53:10Z`: Implemented the reflective model as the built-in foil shading function: procedural environment (sky band, dark floor, three soft patches) plus scene/particle lights as hot spots, tinted by the metal, hue-preserving clip, white only at the hottest core; iridescence shifts the tint with angle. Sprites shade per pixel with crinkled facets (21x21 grid, small tilts); meshes per vertex. The old special-case fragment glint is gone. FoilTests updated (brightness swings 3x+ with angle, crinkle spread across the card, brightest pixels keep the gold hue). Goldens: preset-foil-confetti re-recorded. Waiting on your review of Foil Confetti in motion before closing; the facets still read as a visible square grid up close.
- `2026-10-21T00:23:11Z`: User review: much better, still needs work; parked for later. Known next step: smoother crinkle (noise-based facets instead of a visible square grid).

---

## 176: Marble Run marbles crawl down the track (regression from #157)

+++
status: closed
priority: high
kind: bug
labels: area:collision, effort:s
created: 2026-10-20T00:07:26Z
updated: 2026-10-20T00:08:00Z
closed: 2026-10-20T00:08:00Z
+++

Since #157, marbles in Marble Run roll very slowly. #157 made a particle that enters a distance field during a step respond at the entry point on its path; a particle sliding along the surface starts each step at the surface and dips in under gravity, so every step counted as an entry and put it back near where it started, throwing away its motion along the surface.

- `2026-10-20T00:08:00Z`: Fixed: on entry, the particle goes to the entry point plus the rest of the step's motion along the surface, under Coulomb friction (kept only beyond friction times the part into the surface). Sliding particles keep their speed; resting ones stay put, so thin parts still hold sand (a first attempt, pushing shallow dips straight out, let a thin part's tilted normal walk grains off its edge). Test particlesSlideDownSlopesAtFullSpeed: a ball slides as far down a tilted distance-field slab as down the same analytic box (0.047 vs 0.23 before). Marble Run: mean marble speed 1.55-1.70 m/s over 6 s, matching pre-#157 (1.54-1.68). The #157 thin-part and spinning-fling tests still pass; five distance-field goldens moved slightly (reviewed).

---

## 177: Point caches as PLY files, not inline arrays

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:s
created: 2026-10-20T02:14:44Z
updated: 2026-10-20T17:54:43Z
closed: 2026-10-20T17:54:43Z
+++

Follow-up to #169 and #170, which moved images, distance fields, and emitter meshes out of effect JSON. EmitterDescription.points (point caches: position, normal, color per point, e.g. Point Cloud) is still inline.

Store point caches through EffectResources as PLY files (x y z, nx ny nz, red green blue alpha). Same decisions as #169: references only, no inline reading. Custom particle meshes are split out to their own issue.

- `2026-10-20T02:22:48Z`: Decision (user): use PLY for both (point caches: x y z, nx ny nz, red green blue alpha; custom particle meshes: positions, normals, faces). Do it later, with one shared PLY implementation: move PLYReader from MetalSprocketsGaussianSplats into SwiftMesh and add a writer there (SwiftMesh #187), rather than depending on the Splats target or copying it. Waiting on SwiftMesh #187.
- `2026-10-20T17:48:04Z`: Split (user): this issue now covers point caches only; custom particle meshes moved to a new issue. Use SwiftPLY (https://github.com/schwa/SwiftPLY) instead of waiting on SwiftMesh #187.

---

## 178: Make particle behavior composable (modules instead of one large settings struct)

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:xl, needs-design
created: 2026-10-20T02:29:21Z
updated: 2026-10-21T00:37:57Z
closed: 2026-10-21T00:37:57Z
+++

Particle systems are complex, and ParticleEmitter has grown into one flat struct with dozens of settings (motion, color, size, collision, foil, flocking, trails, ribbons, lights, LOD, user functions...). Every feature adds fields, kernel branches, uniforms, inspector controls, and Codable keys in several places. Make behavior composable instead.

Direction to design (not decided):
- An emitter is a stack of small modules in stages, like Niagara and VFX Graph: Spawn (shape, rate, initial velocity, color), Update (gravity, drag, forces, collision, flocking, color/size over life), Render (sprite, mesh, trail, ribbon, shading).
- Each module is a small value type with its own settings, Codable on its own, and its own inspector view; order in the stack is the order applied.
- On the GPU, modules are visible functions in stage tables (as user functions #167 and pluggable shading #172 already do), so built-in and user modules are the same thing.
- Existing settings become built-in modules; effect files and presets migrate.

Questions to answer first: per-module function calls vs. generated kernels (performance; the stress test must not regress); how modules share per-particle data (fixed fields vs. declared attributes, see custom attributes #122); where events and sub-emitters fit; how much of today's API stays as convenience.

Related: #172 (pluggable shading, the Render-stage version of this), #167 (user functions), #100 (document-based editor).

- `2026-10-20T02:31:43Z`: Implementation path: #179 (refactor to composable modules via Metal function stitching).
- `2026-10-21T00:37:58Z`: Done via #179 (see its closing note and Documentation/Modules.md).

---

## 179: Refactor behavior and rendering into composable modules (stitched Metal functions)

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:xl, needs-design
depends: 178, 182, 197
created: 2026-10-20T02:31:43Z
updated: 2026-10-21T00:37:57Z
closed: 2026-10-21T00:37:57Z
+++

Goal: refactor particle behavior and rendering so emitters are built from composable modules instead of one large settings struct and special-case kernel code. Implementation path for #178.

Approach: Metal function stitching. Each module is a small [[stitchable]] function compiled ahead of time with the library (applyGravity, applyDrag, colorOverLife, collide, foil shading...). An emitter's module stack per stage (spawn, update, render/shading) becomes an MTLFunctionStitchingGraph, turned at runtime into one function without compiling Metal source, and placed in the stage's visible function table (the mechanism user functions #167 already use). User modules compile once from source as stitchable functions and join graphs like built-ins. A node editor (#100) could build graphs directly.

Steps:
1. Spike: stitch gravity, drag, and color over life into the update slot; compare output with the built-in path and measure the Stress Test and graph build time. Answer: what stitchable functions can pass (values, vectors, pointers; whether ParticleState must be split), and whether stitching works with the Metal 4 pipeline and compiler APIs the library uses.
2. Module model in Swift: module value types per stage, Codable, with inspector views; stack order is application order.
3. Move update behaviors to modules, keeping goldens identical.
4. Move spawn behaviors.
5. Rendering/shading through the same mechanism (#172, then #175 foil as a module, #174 per pixel).
6. Migrate effect files and presets; decide what of today's ParticleEmitter API stays as convenience.

Each step to be split into its own issue once the spike answers the open questions.

Related: #178 (why), #172, #174, #175, #167, #122 (custom attributes), #100.

\- `2026-10-20T02:35:19Z`: Scope note (user): the JSON and the UI change too, as part of this refactor, not as follow-ups.
- Effect JSON: an emitter becomes its module stacks per stage (an ordered list of modules, each with a type and its settings) instead of one flat settings object. A new format version; existing effects and presets need a migration (a converter from today's flat settings to modules), and the decision on reading old files (after #169/#170, references only; here likely a one-time migration tool rather than reading both forever).
- Demo UI: the inspector becomes a module stack per stage (add, remove, reorder, enable modules; each module has its own section), replacing the fixed sections built in #159-#168. The outline may show modules under emitters. Effect packages (#169) carry user module sources.
Steps 2 and 6 cover these; split them into their own issues after the spike.

- `2026-10-20T18:19:58Z`: Split into sub-tickets (user: plan the big refactor first). Order: #182 spike (gates everything) and #184 perf baseline; #183 MetalSprockets stitching API; #185 design; #186 JSON format; #187 Swift module types; #188 runtime; #189-#191 update modules; #192 spawn; #193 render (with #172/#175/#174); #194 migration tool; #195 presets; #196 demo inspector; #197 retire flat settings. Dependencies are recorded on each issue.
- `2026-10-20T18:32:44Z`: Spike results (#182, Tests/MetalSprocketsParticlesTests/StitchingSpikeTests.swift):
- `2026-10-20T18:32:44Z`: Works. gravity, drag, and color over life as [[stitchable]] modules, stitched with MTLFunctionStitchingGraph into the update slot, give bit-identical particles to the same code written as one user function.
- `2026-10-20T18:32:44Z`: ABI: modules use the user-function signature (thread ParticleState &, dt, time, constant float4 *parameters) and return parameters advanced past their own entries. That pointer is the data dependency that orders the chain; a void endModules(pointer) node ends it. ParticleState passes whole by thread reference; no need to split it. Structs by value, vectors, constant and device pointers also compile as stitchable.
- `2026-10-20T18:32:44Z`: Metal 4: device.makeLibrary(stitchedDescriptor:) gives a library whose function wraps as a MetalSprockets VisibleFunction and links through MTL4StaticLinkingDescriptor and the existing visible function tables. No MetalSprockets change needed (#183).
- `2026-10-20T18:32:44Z`: Cost, 1M particles, simulate GPU (debug build, M-series): built-in only 0.294 ms; hand-written user function 0.360 ms; stitched 0.360 ms. Stitching itself costs nothing over a user function. The visible function call (state marshalling plus indirect call) costs about 0.07 ms per 1M, about 22% of simulate.
- `2026-10-20T18:32:44Z`: Build time: about 2.3 ms per graph. Pipeline creation with a stitched function linked: about 420 ms first frame vs 60 ms for a source user function, so pipelines per distinct stack must be cached (and maybe a binary archive) and built off the frame path.
- `2026-10-20T18:32:44Z`: Graphs per effect: one per (emitter, stage) distinct stack; typical effects 2 to 6.
- `2026-10-20T18:32:44Z`: Verdict: go, with one risk. If all built-in behavior moves into modules, every particle pays the call overhead; the Stress Test may regress past the #184 gate. Mitigations to try in #188: keep hot built-ins (integrate, gravity, drag) inline in the kernel and only stitch the rest; or link the stitched function by direct extern call rather than through a table so the pipeline compiler can inline it. Fallback if both fail: generated Metal source per stack.
- `2026-10-20T18:48:40Z`: Landed: modules model, effect format 2, stitched user modules in update/spawn, migration tool, presets migrated, demo module stacks. Open: #193 (render-stage stitching, after #172).
- `2026-10-20T19:04:14Z`: Correction to the #182 notes: the ~22% was the custom attribute buffer, not the function call. See #205 and #206.
- `2026-10-21T00:37:57Z`: Done: modules model, stitched user modules, effect format 4, demo module stacks, ParticleEmitter internal, shading functions. Built-ins run at fixed points by design (#207/#208). First-frame stall fixed upstream (#209). Follow-ups standing alone: #175 (foil look, deferred), #215, #218, #219.

---

## 180: Raise unit test coverage

+++
status: closed
priority: medium
kind: task
labels: area:tooling, effort:m
created: 2026-10-20T02:41:02Z
updated: 2026-10-20T18:06:15Z
closed: 2026-10-20T18:06:15Z
+++

Measure with: xcb test --coverage-summary --coverage-sort-by-impact

Baseline (library package, 2026-10-19): 85.0% of lines (5701/6711), 83.5% of functions (830/994). Biggest gaps by uncovered lines:
- MetalSprocketsParticlesUI/ParticleView+Previews.swift: 629, 0% (SwiftUI #Previews; exclude from coverage or accept, rather than test)
- MetalSprocketsParticlesUI/ParticleView.swift: 61, 30% (the view itself; ParticleViewState is partly tested)
- ParticleFlocking.swift: 51, 75%
- MetalSprocketsParticlesSamples/SamplePresets.swift: 28, 56% (convenience accessors for presets)
- DebugWireframes.swift: 23, 89%
- ParticleSystemRuntime.swift: 22, 98%
- EffectResources.swift: 17, 83%; MeshFile.swift: 14, 83% (new in #169/#170: error paths, Model I/O path)
- ParticleDebugView.swift: 12, 62%; ParticleColorImage.swift: 11; ParticleSprite.swift: 11
- ParticleSystemRuntimeError.swift: 8, 0% (error descriptions)
- EventBurst.swift: 6, 70%; ParticleSystemFolder.swift: 6, 62%
Everything else is above 90%.

Also measure the demo package (MetalSprocketsParticlesDemoSupport), which this baseline does not include.

Approach: start with the gaps by impact; tests should check behavior, not just touch lines; decide what to exclude (previews) instead of writing tests for them. Set a target once the previews question is settled (excluding them, the library is about 93%).

- `2026-10-20T02:42:09Z`: Decision (user): exclude code that is not testable or not worth testing rather than writing tests for it. Candidates: ParticleView+Previews.swift (SwiftUI #Previews), and review the rest case by case (e.g. thin SwiftUI glue in ParticleView.swift). Tooling gap: xcb test has no option to exclude files from the coverage summary (only --coverage-include-tests), so exclusions need either an xcb option (file a request) or a project-side list the summary is filtered by.
- `2026-10-20T02:43:33Z`: Filed xcb #96: --coverage-exclude <glob> and coverage_exclude in .xcb.toml.
- `2026-10-20T11:40:40Z`: xcb #96 landed. .xcb.toml now has [defaults.test] coverage_exclude = ["Sources/**/*+Previews.swift"]. New baseline: 93.7% of lines (5701/6082), 90.5% of functions (830/917); 1 file (629 lines) excluded. Next gaps: ParticleView.swift 61, ParticleFlocking.swift 51, SamplePresets.swift 28, DebugWireframes.swift 23.
- `2026-10-20T18:03:34Z`: Progress: 97.4% of lines (5989/6148), 94.9% of functions. ParticleViewState moved to its own file; ParticleView.swift (SwiftUI glue) excluded in .xcb.toml. New tests: two flocking emitters (covers the multi-flock pass), debug wireframes (paths, box/plane shapes, tracked objects), error descriptions, OBJ/PLY/image-extension edge cases, folders without index.json, sample preset accessors, pointer projection misses, color image unpremultiply. Left: mostly preconditionFailure and GPU-allocation-failure paths, plus a long tail of 4-6 lines per file; demo package not yet measured. No target set yet.
- `2026-10-20T18:06:13Z`: Closed for now (user) at 97.4% lines / 94.9% functions. Demo package coverage and a target were not done.

---

## 181: Custom particle meshes as mesh files via MeshFile/Model I/O, not inline arrays

+++
status: closed
priority: low
kind: enhancement
labels: area:api, effort:s
created: 2026-10-20T17:48:04Z
updated: 2026-10-20T18:17:44Z
closed: 2026-10-20T18:17:44Z
+++

Split from #177. ParticleMesh.triangles(positions:normals:) (custom mesh particles) is still saved inline in effect JSON. No preset uses it yet.

Store it through EffectResources as a mesh file, reusing MeshFile (#170): write OBJ, read OBJ ourselves and other formats (PLY, USD) through Model I/O. References only, no inline reading (#169).

Open point: MeshFile keeps positions and faces only. Normals must either be written (OBJ vn) and read back, or be rebuilt as flat normals, as ParticleMesh(mesh:) does now.

---

## 182: Spike: stitch update behaviors into one function with MTLFunctionStitchingGraph

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:m, needs-design
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:32:44Z
closed: 2026-10-20T18:32:44Z
+++

Nothing yet shows that Metal function stitching works for particle behaviors in this library.

Spike: write gravity, drag, and color over life as [[stitchable]] functions, stitch them into the update slot, and compare against the built-in path (same particles after N steps; goldens).

Answer and write up on #179:
- What stitchable functions can take and return (values, vectors, pointers, structs); whether ParticleState passes whole or must be split into fields.
- Whether stitching works with the Metal 4 pipeline and compiler APIs the library uses (MTL4Compiler, linked functions, visible function tables).
- Cost: Stress Test GPU time vs. today's kernel; time to build a graph; how many distinct graphs a typical effect needs.
- Go / no-go, and the fallback if no-go (e.g. generated Metal source per stack, or fixed kernels with module flags).

Part of #179 (plan for #178).

- `2026-10-20T18:32:44Z`: Spike done; findings on #179. Go, with the call-overhead risk noted there.

---

## 183: MetalSprockets has no API for stitched functions

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:s
depends: 182
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:32:44Z
closed: 2026-10-20T18:32:44Z
+++

MetalSprockets' VisibleFunctionTable docs mention stitched functions, but there is no way to build one (MTLFunctionStitchingGraph / stitched function descriptor) and get a VisibleFunction from it. The module runtime needs this. Check after the spike what is missing and file it in MetalSprockets if the work belongs there.

Part of #179 (plan for #178).

- `2026-10-20T18:32:44Z`: Not needed: a stitched library's function wraps as VisibleFunction(library:name:) and links through the existing linkedFunctions path (see #179 spike notes). Reopen if #188 wants a convenience builder.

---

## 184: No performance gate for the module refactor

+++
status: closed
priority: medium
kind: task
labels: area:tooling, effort:s
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:32:44Z
closed: 2026-10-20T18:32:44Z
+++

The module refactor must not slow the simulation, but there is no recorded baseline to compare against. Record particles-bench numbers (Stress Test and every preset: GPU ms, frame ms) on the current code, and a way to re-run and compare them after each migration step (a script or a bench mode that diffs against the baseline).

Part of #179 (plan for #178).

- `2026-10-20T18:32:44Z`: Added --save-baseline / --compare / --tolerance / --noise-floor to particles-bench; baselines in Benchmarks/ (README there).
- `2026-10-20T18:32:44Z`: Baselines recorded in Benchmarks/; compare with particles-bench --compare.

---

## 185: Design the module model: stages, per-particle data, parameters, events

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m, needs-design
depends: 182
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:40:48Z
closed: 2026-10-20T18:40:48Z
+++

The module model is not designed. Decide and write down (a design doc in the repo, linked from #178):
- Stages and what belongs in each: spawn, update, collision/events, render/shading.
- Module identity and settings: a type per module or one enum; enable flag; order = application order.
- How modules share per-particle data: fixed ParticleState fields vs. declared attributes (builds on custom attributes, #122).
- How a module's settings reach the GPU (parameter buffer layout per module in a stack).
- Where colliders, force fields, events, sub-emitters, triggers, trails, ribbons, LOD, and lights fit (module, system-level, or unchanged).
- What of today's ParticleEmitter API stays as convenience (builders, presets DSL).
- Performance rules from the spike (e.g. what must stay in the kernel).

Part of #179 (plan for #178).

- `2026-10-20T18:40:48Z`: Done: see Documentation/Modules.md. Modules are the stored model (EmitterDescription.modules), lowered to ParticleEmitter for the kernel; user [[stitchable]] modules stitch into the update/spawn slots; effect format 2 with format-1 loading.

---

## 186: Effect JSON format for module stacks, with a version and migration path

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m, needs-design
depends: 185
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:40:48Z
closed: 2026-10-20T18:40:48Z
+++

Effect files store one flat ParticleEmitter settings object. With modules, an emitter is ordered module stacks per stage. The new format needs: a format version, the shape of a module entry (type + settings), how user modules' sources are carried in effect packages (#169), and the decision on old files (per #169/#170: likely a one-time migration tool, not reading both forever).

Part of #179 (plan for #178).

- `2026-10-20T18:40:48Z`: Done: see Documentation/Modules.md. Modules are the stored model (EmitterDescription.modules), lowered to ParticleEmitter for the kernel; user [[stitchable]] modules stitch into the update/spawn slots; effect format 2 with format-1 loading.

---

## 187: Swift module types per stage (Codable, ordered stacks)

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:l
depends: 185, 186
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:40:48Z
closed: 2026-10-20T18:40:48Z
+++

There are no Swift types for modules. Per the design: module value types per stage, each Codable on its own, an ordered stack per stage on EmitterDescription, and an enabled flag. Equatable/Hashable so the runtime can cache stitched graphs by stack shape.

Part of #179 (plan for #178).

- `2026-10-20T18:40:48Z`: Done: see Documentation/Modules.md. Modules are the stored model (EmitterDescription.modules), lowered to ParticleEmitter for the kernel; user [[stitchable]] modules stitch into the update/spawn slots; effect format 2 with format-1 loading.

---

## 188: Runtime: build, cache, and bind stitched functions from module stacks

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 187, 183
created: 2026-10-20T18:19:52Z
updated: 2026-10-20T18:40:48Z
closed: 2026-10-20T18:40:48Z
+++

The runtime cannot turn a module stack into GPU code. Needed: build a stitching graph per stage from a stack, cache the result by stack shape (not by parameter values), pack module parameters, and link/bind the functions in the stage's visible function table, sharing the path user functions (#167) use today. Errors from bad user modules surface like ParticleFunctionError.

Part of #179 (plan for #178).

- `2026-10-20T18:40:48Z`: Done: see Documentation/Modules.md. Modules are the stored model (EmitterDescription.modules), lowered to ParticleEmitter for the kernel; user [[stitchable]] modules stitch into the update/spawn slots; effect format 2 with format-1 loading.

---

## 189: Update modules: gravity, drag, force fields, plane constraint

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 188, 184
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:22Z
closed: 2026-10-20T18:42:22Z
+++

Gravity, drag, force fields, and the plane constraint are hard-coded in updateParticles. Move them to update modules. Every golden stays identical and the performance gate does not regress.

Part of #179 (plan for #178).

- `2026-10-20T18:42:22Z`: Per Documentation/Modules.md: these are now modules (EmitterModules) in the API and effect files, lowered to kernel uniforms. Kernel code stays: the #182 spike measured ~22% simulate cost for per-module function calls, which would fail the #184 gate. Goldens unchanged.

---

## 190: Update modules: color, size, rotation over life, image sequences

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 189
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:22Z
closed: 2026-10-20T18:42:22Z
+++

Color, size, and rotation over life and image sequence playback are fixed emitter settings sampled in the kernel/vertex shader. Move them to modules. Goldens identical; no performance regression.

Part of #179 (plan for #178).

- `2026-10-20T18:42:23Z`: Per Documentation/Modules.md: these are now modules (EmitterModules) in the API and effect files, lowered to kernel uniforms. Kernel code stays: the #182 spike measured ~22% simulate cost for per-module function calls, which would fail the #184 gate. Goldens unchanged.

---

## 191: Update modules: collisions, flocking, and user update functions

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 190
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:23Z
closed: 2026-10-20T18:42:23Z
+++

Collisions (analytic, SDF, scene depth, with events), flocking steering, and the user update function are separate code paths in the kernel. Move them into the module stack (or document why some stay in the kernel, per the design). User functions become user modules. Goldens identical; no performance regression.

Part of #179 (plan for #178).

- `2026-10-20T18:42:23Z`: Collisions and flocking are modules lowered to uniforms (perf rule, Documentation/Modules.md). User code: update/collision/death functions are modules, and user [[stitchable]] modules (StitchedModule) stitch into the update/spawn slots in stack order.

---

## 192: Spawn modules: shape, rate, initial velocity, color, user spawn functions

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 188, 184
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:23Z
closed: 2026-10-20T18:42:23Z
+++

Spawn behavior (emitter shape, birth location and direction, velocity and spread, variations, birth color gradient, user spawn function) is fixed code in spawnParticle. Move it to spawn modules. Goldens identical; no performance regression.

Part of #179 (plan for #178).

- `2026-10-20T18:42:23Z`: Per Documentation/Modules.md: these are now modules (EmitterModules) in the API and effect files, lowered to kernel uniforms. Kernel code stays: the #182 spike measured ~22% simulate cost for per-module function calls, which would fail the #184 gate. Goldens unchanged.

---

## 193: Render modules: shading, foil, and per-pixel functions through the module stack

+++
status: closed
priority: medium
kind: task
labels: area:rendering, effort:l
depends: 188
created: 2026-10-20T18:19:53Z
updated: 2026-10-21T00:37:57Z
closed: 2026-10-21T00:37:57Z
+++

Rendering (sprite/mesh/trail/ribbon drawing, shading models, foil) does not use modules. Bring the render stage onto the same mechanism, building on #172 (pluggable shading), then #175 (foil) and #174 (per-pixel functions).

Part of #179 (plan for #178).

- `2026-10-20T18:42:23Z`: Render modules exist at the API/file level (sprite, foil, mesh, trail, ribbon, light, LOD) and lower to current settings. Stitching render/shading functions still needs #172 first.
- `2026-10-20T21:52:33Z`: Shading is now a render module (#172). What's left for render modules: per-pixel functions (#174) and reflective foil as a shading model (#175).
- `2026-10-21T00:37:57Z`: Render stage is on modules: shading module with per-vertex/per-pixel functions (#172, #174); foil as a built-in model (#175, deferred for look).

---

## 194: Migration tool: convert flat effect files to module stacks

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
depends: 186, 191, 192
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:12Z
closed: 2026-10-20T18:42:12Z
+++

Existing effects (presets, user files, packages) use flat settings. Needed: a converter from today's settings to module stacks (library function + particles-render or a CLI subcommand), round-trip tested so every preset renders identically after conversion.

Part of #179 (plan for #178).

- `2026-10-20T18:42:12Z`: particles-migrate rewrites effect files/packages/folders in the current format (--dry-run to report).

---

## 195: Migrate bundled presets to the module format

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:s
depends: 194
created: 2026-10-20T18:19:53Z
updated: 2026-10-20T18:42:13Z
closed: 2026-10-20T18:42:13Z
+++

The bundled presets are in the flat format. Convert them with the migration tool; every golden stays identical.

Part of #179 (plan for #178).

- `2026-10-20T18:42:13Z`: All bundled presets migrated to format 2 (modules), formatted with prettier --print-width 120 like before.

---

## 196: Demo inspector: module stack per stage

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:l
depends: 187, 194
created: 2026-10-20T18:19:54Z
updated: 2026-10-20T18:44:36Z
closed: 2026-10-20T18:44:36Z
+++

The demo inspector has fixed sections (#159-#168) for the flat settings. It needs a module stack per stage: add, remove, reorder, enable/disable modules, each with its own section; the outline may show modules under emitters. User modules reuse the user-function editor (#167).

Part of #179 (plan for #178).

- `2026-10-20T18:44:36Z`: Inspector has a Modules section: per-stage stacks with enable toggles, move up/down, add (menu of addable kinds) and remove; required modules can't be removed. The existing sections still edit values; editing settings keeps the user's module order (EmitterModules.merging).

---

## 197: Retire the flat ParticleEmitter settings

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
depends: 195, 196, 193, 199, 200, 201, 202, 203, 205, 204, 207
created: 2026-10-20T18:19:54Z
updated: 2026-10-20T20:20:36Z
closed: 2026-10-20T20:20:36Z
+++

After migration, the flat settings and the kernel branches behind them remain. Remove them or keep a thin convenience layer per the design decision; update the presets DSL (ParticlePresetBuilder), README, and docs.

Part of #179 (plan for #178).

- `2026-10-20T18:48:40Z`: Decision: ParticleEmitter stays public as the lowered/flat convenience form (EmitterDescription.settings converts both ways); modules are the stored and saved model. Kernel branches stay (perf rule, Documentation/Modules.md). README, docs, and the 'adding a setting' checklist updated; the preset builder works unchanged through settings.
- `2026-10-20T18:58:49Z`: Reopened: closing it with 'ParticleEmitter stays' was a shortcut, not the design. Redo properly, perf-neutral: #199 #200 #201 #202 #203 #204, plus #205 for real ordering.
- `2026-10-20T19:39:30Z`: Revised: built-ins stay at fixed points (#207 won't do, #208 decided). Appearance modules moved to the render stage (format 3).
- `2026-10-20T20:20:36Z`: Done: flat settings are retired from the public API (#204); modules are the model (#199-#203). Built-ins stay at fixed points by design (#207/#208).

---

## 198: Stitched module stacks travel as a fake ParticleFunction with a marker in its source

+++
status: closed
priority: low
kind: task
labels: area:api, effort:s
created: 2026-10-20T18:57:18Z
updated: 2026-10-20T19:11:29Z
closed: 2026-10-20T19:11:29Z
+++

StitchedModule.function(for:slot:) packs a stack of stitched modules into a ParticleFunction whose source is a marker string plus each module's name and source. ParticleFunction.compile checks for the marker and parses the modules back out (StitchedModule.modules(in:)). This reuses the function-slot cache and binding path, but it is fragile: a module source that contains the separator line breaks parsing, and the type does not say what the slot holds.

Fix: give FramePlan.Dispatch.functions a real type per slot (e.g. an enum: user function or stitched stack), key the compiled-function cache by it, and remove the marker. Tests: EmitterModulesTests, StitchingSpikeTests.

Part of #179.

- `2026-10-20T19:11:29Z`: SlotFunction (user function or stitched stack) replaces the marker ParticleFunction; the cache keys by SlotFunction.Key (sources and names, not parameter values).

---

## 199: Modules lower once when they change; runtime reads the cached result

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l
depends: 206
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T19:24:46Z
closed: 2026-10-20T19:24:46Z
+++

Modules are lowered to the flat ParticleEmitter, and the runtime and FramePlan read that. Lower EmitterModules directly into the per-emitter runtime state and SimulationUniforms/RenderUniforms instead, so ParticleEmitter leaves the runtime path. Lower once when modules change and cache the result; today lowering runs every frame (about 0.01 ms per emitter of build time).

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:24:46Z`: Done partly: EmitterDescription caches modules.lowered() on change (settings reads are free; mean preset build 0.026 → 0.0245 ms vs 0.0223 baseline), and 2D no longer re-lowers per frame (#212). Kept: the runtime's resolved per-emitter form is still ParticleEmitter. Lowering straight into SimulationUniforms isn't worth it: FramePlan builds uniforms per frame from time, transforms, and LOD anyway, and a flat resolved struct is the fast path. Making that struct internal and renaming it is #204.

---

## 200: Each module owns its settings, coding, lowering, and defaults in one place

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:l
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T19:18:40Z
closed: 2026-10-20T19:18:40Z
+++

A module's fields are spread over ParticleEmitter, the module enum case, apply(to:), and the lifting in EmitterModules.init(_:). Make each module one type (e.g. a protocol with a settings struct, Codable, and a lower-into-uniforms method), so adding a feature touches one module plus the kernel. Replace the enum cases with long associated-value lists (which needed a swiftlint disable).

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:04:14Z`: Per #205: built-ins can be stitched modules running in stack order at no measured cost (after #206). Decide per module whether it's stitched or a fixed kernel stage (collisions, fields, events need system data).
- `2026-10-20T19:18:40Z`: Each module is a ParticleModule struct owning its settings, kind, required flag, editor default, apply(to:), and init?(lifting:). Stage enums (SpawnModule/UpdateModule/RenderModule) are thin StageModule wrappers with shared Codable; saved JSON is byte-identical (presets re-saved: no diff). Still lowers to ParticleEmitter; #199 changes that target.

---

## 201: Sub-emitters hold modules instead of flat ParticleEmitter settings

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T19:26:34Z
closed: 2026-10-20T19:26:34Z
+++

SubEmitter.settings is still a ParticleEmitter inside the subEmitters module. Make sub-emitters hold EmitterModules, lowered like top-level emitters. Effect files: format bump or migration via particles-migrate.

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:26:35Z`: SubEmitter stores EmitterModules (lowered and cached like EmitterDescription); settings is the flat view. Effect files: sub-emitters save 'modules'; old 'settings' still loads. 4 presets with sub-emitters migrated.

---

## 202: Preset builder, tests, and samples build modules, not ParticleEmitter

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:l
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T19:28:47Z
closed: 2026-10-20T19:28:47Z
+++

ParticleSystemBuilder, the sample presets in code, the README example, and many tests build ParticleEmitter and pass it as settings. Move them to modules (with convenient builders so code stays short).

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:28:47Z`: EmitterModulesBuilder: EmitterDescription(name) { ShapeModule(...); GravityModule(...) } places each module in its stage and fills missing required ones; EmitterDescription(_:modules:) designated init. README example uses it (compiled by EmitterModulesTests.readmeExample). Tests keep building the flat form via @testable: that becomes the internal resolved form in #204.

---

## 203: Demo inspector sections edit modules directly

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:l
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T20:12:42Z
closed: 2026-10-20T20:12:42Z
+++

The inspector's sections (#159-#168) bind to EmitterDescription.settings, which converts both ways and merges to keep module order (EmitterModules.merging). Give each module its own section bound to its slot, shown in stack order, and drop the settings bridge.

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T20:12:42Z`: Emitter inspector is now one section per module in stack order (Spawn/Update/Render), each bound to its module struct; enable/remove in headers; Add menus per stage; stitched modules reorder. Description-level sections: Emitter (with capacity), Appearance (sprite, Draw As via the mesh module, Add Color Image), Emitter Motion, Shape Source. Sub-emitters edit their own module stacks. Old ParticleEmitter adapters removed; their tests ported to module adapters (77 demo tests pass). Not built by eye: I haven't run the app.

---

## 204: Remove ParticleEmitter and EmitterDescription.settings

+++
status: closed
priority: medium
kind: task
labels: area:api, effort:m
depends: 199, 200, 201, 202, 203
created: 2026-10-20T18:58:48Z
updated: 2026-10-20T20:20:35Z
closed: 2026-10-20T20:20:35Z
+++

After the other #197 tasks, ParticleEmitter has no users. Remove it, the settings bridge, lifting (EmitterModules.init(_:)) except inside particles-migrate for format-1 files, and update docs (Documentation/Modules.md, README, the adding-a-setting checklist).

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:28:47Z`: Before ParticleEmitter goes internal, move its remaining public users to modules: ParticleView+Previews (8 previews use ParticleEmitter.default2D), particles-bench, ParticleSystemRuntime's public API (init(emitter:), emitters[].settings, setEmitters), SubEmitter.transition(into:), the demo (#203). Gotcha found in #202: EmitterDescription and SubEmitter cache modules.lowered() in a didSet, which doesn't fire inside initializers; set the cache in every init.
- `2026-10-20T19:48:56Z`: Non-UI prep done: LoweredModule (internal) holds apply/lift; runtime has module APIs (init(modules:), init(capacity:modules:), setEmitters/addEmitter with modules, Emitter.modules); EmitterModules.default2D; SubEmitter.transition(into: EmitterModules); previews and particles-bench build modules. Left before flipping ParticleEmitter to internal: the demo app and its tests (#203), and MetalSprocketsParticlesUITests (no @testable).
- `2026-10-20T20:12:42Z`: After #203 the demo still uses .settings in: UserFunctionEditor (functions), OutlineView (sub-emitters/triggers lists), ParticlesDemoModel (add sub-emitter/trigger, pointer), Inspector+Events, SceneAnimationViews, ParticleKind (an extension on ParticleEmitter); and demo tests construct EmitterDescription(settings:).
- `2026-10-20T20:20:36Z`: ParticleEmitter is internal, as are EmitterDescription.settings, SubEmitter.settings, the runtime's flat-settings API, lifting, and lowering. Public code builds modules (builder, .standard/.default2D, modules[SomeModule.self]). Demo, previews, CLI tools, and UI tests use modules; library tests keep the flat form via @testable. Preset comments and Demos.md name modules instead of ParticleEmitter fields. Lifting stays (internal) because format-1 files still load.

---

## 205: Built-in modules run in stack order without losing speed

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:m, needs-design
created: 2026-10-20T18:58:49Z
updated: 2026-10-20T19:04:14Z
closed: 2026-10-20T19:04:14Z
+++

Built-in modules run in the kernel's fixed order whatever the stack says; only stitched user modules follow stack order. Find a way to honor order with no regression. Try first: stitch an emitter's whole update stack (built-ins as [[stitchable]] modules) into one function and check whether the pipeline compiler inlines it (spike: 1 call measured ~22% of simulate on 1M). Fallback: generated kernel source per distinct stack, compiled off the frame path and cached (binary archive). If neither meets the gate, keep the fixed order and make the inspector show built-ins as unordered.

Gate: no regression in particles-bench --compare (#184) for presets and scenarios; goldens identical.

Part of #197.

- `2026-10-20T19:04:14Z`: Spike (StitchingInlineSpikeTests, STITCHING_TIMINGS=1): the call is not the cost. Standalone kernel, 8 modules, 1M particles: inline 0.22-0.26 ms, through a visible function table 0.22-0.25, direct extern call with privateFunctions 0.23-0.28: same within noise, bit-identical results. Real runtime: a no-op user function adds 0.07 ms only because of the custom attribute load/store; with that off, no-op = none. So built-ins can be stitched modules that run in stack order without losing speed, if attribute traffic is fixed first (#206). Direct extern linking (privateFunctions, '[[visible]] extern' declaration) also works if we ever want to drop the table. Open design points for #199/#200: modules that need system data (colliders, force fields, SDF textures, events, sub-emitters) can't get it through the (state, dt, time, parameters) signature; either keep those as kernel stages around the stitched stack, or widen the ABI with a context struct of pointers. #182's '22% per call' note on #179 was wrong; corrected here.

---

## 206: Custom attribute buffer is read and written whenever an emitter has any user function

+++
status: closed
priority: medium
kind: enhancement
labels: area:simulation, effort:s
created: 2026-10-20T19:04:14Z
updated: 2026-10-20T19:13:44Z
closed: 2026-10-20T19:13:44Z
+++

When any emitter has a user function or stitched module, the update kernel loads and stores ParticleState.custom for every particle (16+ bytes each way). On 1M particles that costs about 0.07 ms of simulate GPU time (0.28 → 0.35 ms), even for a no-op function. With the attribute traffic off, a no-op function costs the same as none (#205 spike). Only keep attributes for emitters whose functions or modules use them: e.g. a declared customAttributeCount of 0 meaning none, or modules declaring what they read and write. This matters for #205: if built-ins become stitched modules, every emitter has a function, and this cost would apply everywhere.

- `2026-10-20T19:13:44Z`: Emitters whose functions/modules never mention 'custom' get customAttributeCount 0; the kernel then skips attribute load/store and no buffer is made. 1M particles with a no-op update function: 0.35 → 0.27 ms simulate, same as no function.

---

## 207: Built-in update modules don't run in stack order

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:l, needs-design
depends: 208
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T19:39:30Z
closed: 2026-10-20T19:39:30Z
+++

#205 showed a stitched stack costs the same as inline kernel code (once #206 removed the attribute traffic), but nothing implements it yet: gravity, drag, color/size over life, color by speed/position, and the plane constraint still run in the kernel's fixed order whatever the stack says. Write them as [[stitchable]] built-in modules (compiled with the library), stitch each emitter's update stack into one function, and drop the matching kernel code. Gate: particles-bench --compare (#184), goldens identical for presets whose order matches today's. Part of #197.

- `2026-10-20T19:39:30Z`: Won't do. Appearance modules (color/size over life, by speed/position, image sequence) are evaluated in the vertex shaders, not the simulation, and multiply, so order is meaningless; they moved to the render stage. Force fields, flocking, and collisions need system data (#208). That leaves gravity, drag, plane constraint, where order barely matters. Built-ins run at fixed, documented points (Documentation/Modules.md 'Order'); only stitched modules are ordered; the inspector only offers moving those.

---

## 208: Stitched modules can't read system data (colliders, force fields, textures, events)

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:m, needs-design
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T19:39:30Z
closed: 2026-10-20T19:39:30Z
+++

The stitched module ABI is (thread ParticleState &, dt, time, constant float4 *parameters). Collisions, force fields, SDF and scene-depth textures, events, and sub-emitters need buffers and textures the kernel has, so they can't be modules in a stack. Decide: keep them as fixed kernel stages around the stitched stack, or widen the ABI with a context struct of pointers (and check what stitching allows for textures). Blocks moving those behaviors into the stack (#207).

- `2026-10-20T19:39:30Z`: Decided: behaviors that need system data (force fields, flocking, collisions, scene depth, SDFs, events, sub-emitters) stay fixed kernel stages. Stitched modules keep the (state, dt, time, parameters) ABI and run at one point: after the move, before the plane constraint and collisions. Revisit with a context-struct ABI if a user module needs system data.

---

## 209: First frame with a new user function or stitched stack stalls ~360 ms building the pipeline

+++
status: closed
priority: medium
kind: task
labels: area:simulation, effort:m, needs-design
created: 2026-10-20T19:20:17Z
updated: 2026-10-21T00:34:16Z
closed: 2026-10-21T00:34:16Z
+++

#182 measured about 420 ms for the first frame after a stitched function is linked (vs ~60 ms for a source user function); graph build itself is ~2 ms. Editing a module stack in the demo will hitch. Build stitched pipelines off the frame path (keep the old one until ready) and consider a binary archive cache.

- `2026-10-20T19:40:59Z`: Measured (StitchingSpikeTests.firstFrameCost, STITCHING_TIMINGS=1): not stitching-specific. Fresh source user function: compile 4 ms, first frame ~360 ms; fresh stitched stack: stitch 7 ms, first frame ~360 ms. The cost is the Metal 4 compute pipeline for updateParticles being rebuilt with a new linked function (MetalSprockets PipelineCache.computePipeline, static linking). The earlier 60 ms for user functions was a warm cache. Options, both need MetalSprockets: (1) build the pipeline off the frame path and keep the previous one (or no function) until it's ready; (2) Metal's binary-function path: link visible functions into an existing pipeline without recompiling the kernel (MTL4 dynamic linking / pipelines with additional binary functions). Option 2 is the real fix if MTL4 supports it for compute.
- `2026-10-20T20:03:59Z`: Filed upstream: MetalSprockets #534 (async pipeline builds / linking into an existing pipeline).
- `2026-10-21T00:34:16Z`: Fixed upstream by MetalSprockets #534 (binary-linked compute pipelines; new linked functions skip the kernel rebuild). Updated the dependency: StitchingSpikeTests.firstFrameCost now ~5 ms first frame for a new user function or stitched stack (was ~360 ms). All tests, demo, and benchmark gate pass.

---

## 210: Demo has no editor for stitched user modules

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T20:24:39Z
closed: 2026-10-20T20:24:39Z
+++

The Modules section lists stitched modules but can't add or edit them. Reuse the user-function editor (UserFunctionEditor, #167) for a stitched module: source, name, parameters, parameterCount, with compile errors shown.

- `2026-10-20T20:24:39Z`: Stitched modules: Add menu offers them any number of times (update template 'swirl', spawn template 'tint'); StitchedModuleEditor edits name/source as drafts with Compile & Apply (StitchedModule.validate), parameters, and parameterCount. Library: public StitchedModule.validate(device:) and .template.

---

## 211: Outline doesn't show modules under emitters

+++
status: closed
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T20:24:39Z
closed: 2026-10-20T20:24:39Z
+++

The outline lists emitters, sub-emitters, and triggers, but not modules. Show each emitter's modules by stage, selecting one to edit it (pairs with #203).

- `2026-10-20T20:24:39Z`: Outline: each emitter has a collapsed Modules group listing modules by stage (slashed icon when off). Selecting one shows only its section (OutlineItem.module); Delete removes it unless required.

---

## 212: 2D effects lower and re-lift every emitter every frame

+++
status: closed
priority: low
kind: bug
labels: area:simulation, effort:s
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T19:24:46Z
closed: 2026-10-20T19:24:46Z
+++

ParticleSystem.effectiveLayers sets layer.settings.constrainsToPlane in 2D, which lowers the modules, lifts them again, and merges, for every layer on every frame. Add the plane constraint module directly (or fold into #199's cached lowering).

- `2026-10-20T19:24:46Z`: 2D now passes constrainsToPlane into apply(_:rebuild:constrainsToPlane:) instead of editing each layer's settings every frame.

---

## 213: Custom attribute detection is a text search for 'custom'

+++
status: closed
priority: low
kind: enhancement
labels: area:simulation, effort:s
created: 2026-10-20T19:20:17Z
updated: 2026-10-20T20:30:55Z
closed: 2026-10-20T20:30:55Z
+++

#206 keeps attributes only when a function's source contains 'custom'. Comments or names with 'custom' turn them on needlessly; macros could hide a real use (unlikely). Consider an explicit declaration on functions and modules (e.g. reads/writes custom attributes) once #200-style module metadata exists.

- `2026-10-20T20:30:55Z`: Detection now looks for a .custom/.custom1-3 member access outside // and /* */ comments (not \b: Unicode word boundaries treat custom.x as one word). Comments and names like customize no longer turn attributes on. No new API; code reaching custom some other way (macros, pointers) is still not seen, which seems acceptable.

---

## 214: Benchmark baseline has drifted

+++
status: closed
priority: medium
kind: task
labels: area:tooling, effort:s
created: 2026-10-20T19:20:18Z
updated: 2026-10-20T19:34:49Z
closed: 2026-10-20T19:34:49Z
+++

Benchmarks/baseline-presets.json was recorded before the module work; pre-module code now also measures Torch Avenue GPU ~20% slower, so --compare flags noise. Re-record baselines on a quiet machine from a known commit, and note the commit and machine in Benchmarks/README.md.

- `2026-10-20T19:34:49Z`: Re-recorded both baselines at dc0ee23aefd2 on M5 Max with new --repeats 3 (best median of 3 runs); identical code had shown ±25% frame noise with 1 run, now compares clean twice. Benchmarks/README.md updated.

---

## 215: Swift compiler crash: key path to a static property on an existential metatype

+++
status: open
priority: low
kind: task
labels: area:tooling, effort:s, deferred
created: 2026-10-20T19:20:18Z
updated: 2026-10-21T02:03:42Z
+++

In ParticleModule.swift, 'types.compactMap(\\.added)' where types is [any ParticleModule.Type] crashes swift-frontend (Xcode 27 RC). Worked around with a closure. Reduce to a minimal repro and report to Swift (swiftlang/swift).

\- `2026-10-20T20:29:01Z`: Minimal repro (crashes swift-frontend in SILGen, signal 5, Apple Swift 6.4 swiftlang-6.4.0.34.1, Xcode 27 RC, `swiftc -swift-version 6 repro.swift`):

```swift
protocol P {
    static var added: Self? { get }
}

struct S: P {
    static let added: Self? = S()
}

let types: [any P.Type] = [S.self]
let values = types.compactMap(\.added)
print(values.count)
```

Crash: ASTLoweringRequest; Transform::transform during Conversion::emit, on an opened existential (`@opened(...) any P`). A closure `{ $0.added }` compiles. Not yet reported upstream (needs a swiftlang/swift GitHub issue).

---

## 216: Stitched modules whose sources define the same function name fail to compile together

+++
status: closed
priority: medium
kind: bug
labels: area:simulation, effort:s
created: 2026-10-20T19:40:59Z
updated: 2026-10-20T19:42:37Z
closed: 2026-10-20T19:42:37Z
+++

StitchedModule.stitch concatenates every distinct module source into one Metal library. Two modules from different sources that define the same function (a helper, or two versions of a module with one name) fail with 'redefinition of ...'. Found while writing StitchingSpikeTests.firstFrameCost. Fix: compile each distinct source into its own library and pass functions from several libraries to MTLStitchedLibraryDescriptor (check that stitching accepts that), and report two modules with the same name in one stack clearly.

- `2026-10-20T19:42:37Z`: Each distinct module source compiles into its own library; the stitched descriptor takes functions from several libraries. Two modules with one name but different sources now fail with a clear error. Test: StitchingSpikeTests.modulesWithSameHelperNameStitch.

---

## 217: Two stitched modules with the same name but edited sources break the emitter

+++
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-20T20:24:39Z
updated: 2026-10-20T20:28:49Z
closed: 2026-10-20T20:28:49Z
+++

Adding the stitched template twice gives two modules named 'swirl'. Editing one's source but keeping the name makes the stack fail to stitch ('Two stitched modules in one stack are named ... but have different sources', #216), so the emitter's functions fail at runtime. The editor's Compile & Apply only validates the module alone. Fix: validate against the whole stack before applying, or give added templates unique names (swirl2...).

- `2026-10-20T20:28:49Z`: Added stitched modules get unique names (swirl, swirl2, ...; the source's function is renamed too). A user can still type a clashing name by hand; the stack then fails with #216's clear error.

---

## 218: Hard-deprecate effect file formats older than 4

+++
status: closed
priority: low
kind: task
labels: area:api, effort:s
created: 2026-10-21T00:24:43Z
updated: 2026-10-21T01:58:02Z
closed: 2026-10-21T01:58:02Z
+++

Effect files are at format 4. The library still reads formats 1 (flat settings), 2 (appearance modules in update), and 3 (foil module, SpriteModule.isLit), through lifting (EmitterModules.init(ParticleEmitter)), the update-stage fallback and LegacyRenderEntry in EmitterModules decoding, and SubEmitter's flat 'settings'.

Hard deprecation: stop reading them. Files without formatVersion 4 fail to load with a clear error ('effect format N is not supported; this library reads format 4'). Remove the legacy decoding paths, the tests that cover them, and particles-migrate (the bundled presets are already format 4). Lifting stays only where tests still use it (@testable), or goes too if tests move to modules.

Docs: Modules.md 'Effect files' section, README.

- `2026-10-21T01:58:02Z`: Hard-deprecated: ParticleSystem requires formatVersion 4 and fails first with an error naming the found format (or 'no format version'). Removed: flat-settings decoding in EmitterDescription and SubEmitter, format 2/3 conversions in EmitterModules, ParticleEmitter's Codable (with the old collisionMask/fieldMask), the '_0' key fallbacks in EmissionTrigger and PointerBinding, the pre-category ForceField form, and particles-migrate. Lifting stays internal (settings setter, standard/default2D). Tests round-trip through modules (Tests/RoundTrip.swift); legacy tests removed; new EffectFileTests.olderFormatsAreRejected. Docs updated.

---

## 219: New custom shading functions may still stall the first frame (render pipelines are statically linked)

+++
status: closed
priority: low
kind: task
labels: area:rendering, effort:s
created: 2026-10-21T00:34:16Z
updated: 2026-10-21T01:44:16Z
closed: 2026-10-21T01:44:16Z
+++

MetalSprockets #534 binary-links compute pipelines, which removed the ~360 ms first-frame stall for update/spawn functions (#209). Render pipelines are still statically linked, so a new custom shading function (ShadingModel.custom, #172; per pixel, #174) probably rebuilds the particle vertex or fragment pipeline on its first frame. Not measured yet. Measure it (like StitchingSpikeTests.firstFrameCost, with a custom shading function); if it stalls, ask MetalSprockets for the same binary linking on render pipelines.

\- `2026-10-21T00:44:36Z`: Measured (StitchingSpikeTests.firstFrameShadingCost, STITCHING_TIMINGS=1): warm built-in lit ~5 ms; a new custom shading function costs 50-100 ms on its first frame per vertex and ~34 ms per pixel. A real stall, smaller than the old compute one (360 ms). Needs binary linking for render pipelines in MetalSprockets (like #534 did for compute).

Found and fixed a bug while measuring: per-pixel shading after per-vertex shading from another runtime on the same renderer failed with "Linked function 'particleShadeUnlit' has conflicting definitions". We linked functions into one stage only; the other stage's linked list carried over from the previous frame's element tree. Now both stages are set every frame (EmitterDraw.linkedShading). Regression tests: ShadingPipelineTests.

- `2026-10-21T00:47:41Z`: Filed upstream: MetalSprockets #538 (binary linking for render pipelines) and #539 (stage-specific linked functions carrying over between frames).
- `2026-10-21T01:20:52Z`: MetalSprockets #538 landed: a new custom shading function's first frame is ~8 ms (was 50-100 ms). #539 landed too; the both-stages workaround is removed and ShadingPipelineTests pass without it. Cost: binary linking stops inlining, so per-pixel shading is slower (Foil Confetti GPU 0.12 -> ~0.175 ms). Filed MetalSprockets #540 for a per-pipeline static/binary choice; keep this open until it lands, then statically link the built-ins.
- `2026-10-21T01:44:16Z`: MetalSprockets #538/#539/#540 landed. Built-in shading functions link statically (inlinable; Foil Confetti GPU back to 0.12 ms), custom ones binary (a new custom shading function's first frame ~7-8 ms, was 50-100 ms). Update functions ~5 ms (was 360 ms, #209). Benchmark gate clean.

---

## 220: Statically link built-in shading functions

+++
status: closed
priority: medium
kind: enhancement
labels: area:performance, effort:s
created: 2026-10-21T01:38:00Z
updated: 2026-10-21T01:49:39Z
closed: 2026-10-21T01:49:39Z
+++

MetalSprockets 60e2abad (MetalSprockets #540) lets each VisibleFunction choose static or binary linking. Binary-linked calls cannot be inlined; Foil Confetti went from 0.12 ms GPU to ~0.175 ms after MetalSprockets #538 switched to binary linking.

Fix: in Sources/MetalSprocketsParticles/ShadingModule.swift, change `all` to

    var all: [VisibleFunction] { [unlit, lit, foil].map { $0.linking(.static) } }

This covers every shading pipeline (ParticleSystemRuntime.swift linkedFunctions calls at ~870/892/922/943). Custom shading stays binary. Leave tables.linked (~666) binary.

Requires bumping the MetalSprockets dependency to include 60e2abad.

Verify: particles-bench --presets --preset foil --repeats 5 returns to ~0.12 ms.

- `2026-10-21T01:49:39Z`: Done in nwxlzyvz: built-in shading functions use .linking(.static) (MetalSprockets #540); Foil Confetti GPU back to 0.12 ms.

---

## 221: Each draw's rendering decisions are spread across ParticleSystemRuntime

+++
status: closed
priority: medium
kind: task
labels: area:architecture, area:rendering, effort:l
created: 2026-10-21T02:03:07Z
updated: 2026-10-21T02:17:14Z
closed: 2026-10-21T02:17:14Z
+++

render(projection:view:sceneDepth:) decides, for each emitter, in several places and a fixed order: the kind (ribbon, mesh, trail, sprite), the shading function, per-pixel or not, the shader variants (function constants), parameters, linked functions and their linking mode, and blend state. EmitterDraw's large init, shading(for:draw:), vertexShader/fragmentShader, BuiltInShading, four near-identical RenderPipeline branches, and ParticleBlendMode.configure share it. Bugs this session lived in these seams (#219 linked lists carrying over, per-draw lookups, long modifier chains). The runtime file is ~1,100 lines with ~76 stored properties and 21 files extend it.

Deepen: a draw planner that turns (lowered settings, emitter state, camera, lights) into a complete draw description (pure, in-process), plus one thin encoder that binds any description. Dependency: in-process for planning; real MTLDevice (local-substitutable) for encoding.

Tests: assert draw decisions at the planner boundary (e.g. foil sprite -> per-pixel fragment variant, foil linked statically; unlit sprite -> no shading call) instead of through pixels; keep a few goldens end to end.

- `2026-10-21T02:03:43Z`: Related: #222 (shading-function compile/link/caching is one of the decisions the draw planner would consume).
- `2026-10-21T02:17:15Z`: Rendering is now plan + encode. planDraws(projection:view:sceneDepth:) makes every decision once per emitter: DrawKind (ribbon > mesh > trail > sprite), uniforms, shading function, stage, shader variants. encode(_:sceneDepth:) builds one pipeline shape for any plan (one .parameters with kind-specific extras, the draw call from DrawKind); only meshes add a depth test. The four copy-pasted RenderPipeline branches and EmitterDraw.isRibbon/mesh are gone; shading reads draw.kind. Boundary tests in DrawPlanTests (unlit skips shading, lit per vertex, foil sprite per pixel + static, meshes always shade, ribbon wins and gets no foil, custom shading binary, sort order) without rendering. Goldens identical; 477 tests, demo, benchmark gate pass. ParticleSystemRuntime.swift ~1,100 -> ~900 lines.

---

## 222: User GPU code is compiled, cached, and linked four different ways

+++
status: closed
priority: medium
kind: task
labels: area:architecture, area:simulation, effort:m
created: 2026-10-21T02:03:07Z
updated: 2026-10-21T02:10:15Z
closed: 2026-10-21T02:10:15Z
+++

ParticleFunction.compile(prelude:), SlotFunction and its key, StitchedModule.stitch, ShadingModule's prelude and validateShading, the custom-attribute detection cache, and three caches on the runtime (compiledFunctions, compiledShadingFunctions, cachedBuiltInShading) all do: user source + prelude -> validated, cached visible function, linked statically or binary. Each feature (user functions #167, stitched modules #188, shading #172/#174) added its own path.

Deepen: one compiler/cache for user GPU code: given what fills a slot (user function, stitched stack, shading function, built-in), return the linked function, compiled once per source, with linking mode and validation errors handled in one place. Dependency: local-substitutable (real MTLDevice in tests).

Tests: replace the compile/validation checks spread over ParticleFunctionTests, StitchingSpikeTests, EmitterModulesTests, LightingTests with boundary tests: compiles once per source, rejects bad source with ParticleFunctionError, clashing stitched names fail clearly, built-ins link statically and user code binary.

- `2026-10-21T02:03:43Z`: Related: #221 (the draw planner would get shading functions from this compiler).
- `2026-10-21T02:10:15Z`: GPUFunctions (internal, one per runtime) owns compiling, caching, and linking for every visible function the pipelines call: simulation functions and stitched stacks (simulation(_:slot:), with per-slot no-ops), custom shading (shading(_:)), and the built-ins (builtInShading(), static). One cache keyed by source and name; one compileSource with the prelude; ParticleFunctionError everywhere. The runtime's three caches, ParticleFunction.compile(prelude:), SlotFunction.compile, and visibleFunction(for:) are gone; validate/validateShading/validateFunctions call GPUFunctions' uncached compile. Boundary tests in GPUFunctionsTests (compile once regardless of parameters, per-slot no-ops, static vs binary linking, errors by name, templates, stitched clashes) replace checks spread over ParticleFunctionTests, StitchingSpikeTests, EmitterModulesTests, LightingTests. 470 tests, demo, benchmark gate pass.

---

## 223: One setting passes through three representations (modules, flat ParticleEmitter, GPU uniforms)

+++
status: open
priority: medium
kind: task
labels: area:architecture, area:api, effort:xl, needs-design
depends: 221, 226, 227, 228, 229
created: 2026-10-21T02:03:07Z
updated: 2026-10-21T12:17:54Z
+++

Module structs apply onto and lift from ParticleEmitter; EmitterModules lowers/lifts and merges to keep order; EmitterDescription and SubEmitter cache the lowered form in a didSet that does not fire in initializers; FramePlan.uniforms(for:) and EmitterDraw then read ~49 and ~39 ParticleEmitter fields. Adding a setting touches every layer, and lifting must stay exact for every preset.

Deepen: modules produce their GPU-facing contribution directly (e.g. each module writes its part of the simulation/render uniforms and CPU state), so the flat ParticleEmitter and lifting disappear. Dependency: in-process.

Tests: the lift/lower round trips (presetsRoundTrip, Tests/RoundTrip.swift users) become 'given modules -> expected uniforms/draw' tests. Large: needs a design pass first; likely after the draw planner (see related issue) so render-side uniforms have one home.

---

## 224: Particles.metal is one 2,000-line file; the four vertex shaders repeat their setup

+++
status: closed
priority: low
kind: task
labels: area:architecture, area:rendering, effort:m
created: 2026-10-21T02:03:07Z
updated: 2026-10-21T12:16:39Z
closed: 2026-10-21T12:16:39Z
+++

Particles.metal holds the update kernel, spawning, collisions, sorting helpers, lights, shading, four particle vertex shaders, and the fragment shader. The sprite, mesh, trail, and ribbon vertex shaders each repeat dead-particle handling, color/tint, ShadingInput building, and the shade-or-store step.

Split by concern into several files, and share the common vertex setup. Goldens must stay identical.

- `2026-10-21T12:16:39Z`: Split Particles.metal (2,035 lines) by concern: Simulation.metal (spawn, forces, collision, update kernel, 1.2K), Rendering.metal (vertex/fragment shaders, shading functions, particle lights), Colliders.metal (wireframe/solid), and ParticleCommon.h for the five helpers both halves use (hash, sampleCurve, particleTint, rotateAbout, tumbleAxis). The four particle vertex shaders now share particleIndex, isDead/deadVertex, particleColor (base color, variation, tint), and finishVertex (shade or store for per-pixel, debug color, view depth); the mesh shader uses tumbleAxis instead of its own copy. Goldens identical; 477 lib + 80 demo tests pass. Benchmarks: machine on battery, so the AC baseline gate could not run; an A/B against the previous commit under the same conditions showed no regressions (Stress Test alone varied 5.4-10.6 ms run to run).

---

## 225: Demo module editors are one large switch

+++
status: closed
priority: low
kind: task
labels: area:demo, area:architecture, effort:s
created: 2026-10-21T02:03:07Z
updated: 2026-10-21T03:18:58Z
closed: 2026-10-21T03:18:58Z
+++

ModuleStackView's Spawn/Update/RenderModuleEditor switch over every module case, with editing adapters in ModuleEditing.swift and Inspector+Editing.swift. Adding a module means editing the switch, the adapters, and the menu defaults in different files.

Deepen: one editor per module type (e.g. a protocol the demo conforms each module to), looked up from the module, so adding a module adds one editor.

- `2026-10-21T03:18:58Z`: Each module type now owns its editor: EditableModule (static editor(_: Binding<Self>)) in demo ModuleEditors.swift, conformed by all 33 module types. StageModuleEditor opens the stage enum's existential once and gives the module's editor a typed binding, replacing the three Spawn/Update/Render switch editors and the payload() helper. ModuleEditorTests fails if any StageModule.types entry lacks an editor. 80 demo tests pass, demo app builds, lint clean.

---

## 226: Modules write their own GPU uniforms (#223 stage 1)

+++
status: new
priority: medium
kind: task
labels: area:architecture, effort:l
created: 2026-10-21T12:17:47Z
updated: 2026-10-21T14:13:04Z
+++

Each module fills its part of SimulationUniforms, RenderUniforms and per-emitter CPU state via contribute hooks; FramePlan.uniforms(for:) and planDraws iterate modules instead of reading flat ParticleEmitter fields. Tests: given modules -> expected uniforms/draw. Goldens identical, bench gate.

- `2026-10-21T14:13:04Z`: Simulation half done: modules write SimulationUniforms (SimulationModules.swift; stage enums switch to each module's contribute, since dynamic SimulationContributor casts cost Torch Avenue +0.05 ms build per frame). Emitter stores modules (configure(modules:settings:) per frame without lifting; assigning settings lifts). 2D mode is Emitter.forcesPlane, not a flat-settings override. Byte-equal to the flat path for every preset and sub-emitter in 3D and 2D (checked, then the flat builder was deleted). Still on flat settings until #227: function slots and customAttributeCount. Remaining for #226: RenderUniforms in planDraws.

---

## 227: Runtime holds only modules; ParticleEmitter becomes input-only (#223 stage 2)

+++
status: new
priority: medium
kind: task
labels: area:architecture, effort:m
depends: 226
created: 2026-10-21T12:17:47Z
updated: 2026-10-21T12:17:53Z
+++

EmitterDescription and SubEmitter stop caching the lowered ParticleEmitter (and the didSet that skips initializers). ParticleEmitter stays as a convenience converted to modules once at the edge.

---

## 228: Migrate tests, demo and README from ParticleEmitter to the module builder (#223 stage 3)

+++
status: new
priority: low
kind: task
labels: area:architecture, effort:l
depends: 227
created: 2026-10-21T12:17:48Z
updated: 2026-10-21T12:17:54Z
+++

Mechanical sweep: ~67 test files plus demo and README build ParticleEmitter(...) directly; move them to EmitterDescription { ... } modules.

---

## 229: Delete flat ParticleEmitter and lifting (#223 stage 4)

+++
status: new
priority: low
kind: task
labels: area:architecture, effort:m
depends: 228
created: 2026-10-21T12:17:48Z
updated: 2026-10-21T12:17:54Z
+++

Remove ParticleEmitter, LoweredModule apply/lift and the lift round-trip tests; round-trip tests become modules <-> JSON only.

---

## 230: Tests never run under Metal API validation (MTL_DEBUG_LAYER)

+++
status: new
priority: high
kind: task
labels: area:testing, effort:s, area:ci
created: 2026-10-21T12:21:43Z
updated: 2026-10-21T13:52:07Z
+++

The suite never runs under the Metal layers that Xcode Debug runs turn on by default: API validation (MTL_DEBUG_LAYER=1) and GPU frame capture (MTL_CAPTURE_ENABLED=1). So layer-only failures never fail a test. Example: binary-linked user functions and stitched modules crashed under both layers (MetalSprockets #541, #542, now fixed upstream), and the suite passed while the demo crashed in Xcode. GitHub CI (macos-26 runners) has no Metal 4 GPU, so it cannot cover this.

Local check after the MetalSprockets fixes (7588ede): 477 tests pass under each layer, except flockingInADensePileStaysCheap under validation (a timing test; the debug layer is slower).

Needs Buildkite, as MetalSprockets has (.buildkite/pipeline.yml, MetalSprockets #544):
1. Create the MetalSprocketsParticles pipeline on Buildkite, pointing at github.com/schwa/MetalSprocketsParticles, on the Metal 4 agent queue (default-queue). Needs a Buildkite account action.
2. Add .buildkite/pipeline.yml: generate with 'xcb ci generate --target buildkite --warnings-as-errors --no-parallel', then add a step with MTL_DEBUG_LAYER=1 and MTL_CAPTURE_ENABLED=1 (Metal reads them once per process, so it is its own step). Share MetalSprockets' concurrency group for GPU tests. Include the demo support package tests and a demo app build.
3. Port Scripts/test-metal-layers.sh and the MetalDebugLayers test support from MetalSprockets, so the same runs work locally.
4. Skip or loosen timing tests (STITCHING_TIMINGS, flocking cost) when a layer is on.

Done when: Buildkite is green on main with the validation + capture step.

---

## 231: Every particle draw calls setTriangleFillMode, flooding API validation with redundant-call warnings

+++
status: new
priority: low
kind: bug
labels: area:rendering, effort:s
created: 2026-10-21T13:53:12Z
+++

Running the demo in Xcode (API validation on) prints, for every emitter draw every frame:

-[MTL4DebugRenderCommandEncoder setTriangleFillMode:], line 710: warning 'Redundant call to setTriangleFillMode. (setTriangleFillMode called with MTLTriangleFillModeFill but triangle fill mode was already set.)'

Two sources:
- DrawPlan.swift encode: the Draw closure calls encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill) on every draw, even when no draw is wireframe.
- MetalSprockets Draw.swift:76 resets setTriangleFillMode(.fill) after each Draw unconditionally (MetalSprockets #472, open, deferred).

The flood hides real validation messages in the console. Fix here: only set the fill mode for wireframe draws (draw.wireframe), and let the encoder default (.fill) stand otherwise; after a wireframe draw, either rely on MetalSprockets' reset or reset once. Fixing #472 upstream removes the other half. Done when a normal demo run under validation prints no setTriangleFillMode warnings.

---
