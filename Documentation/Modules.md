# Emitter modules

Design for #178 / #179. An emitter is module stacks per stage instead of one flat settings struct.

## Model

- `EmitterDescription.modules: EmitterModules` is the stored, saved model. It holds three stacks:
  - `spawn`: shape, rate, lifetime, velocity, rotation, variation, color image, spawn function, stitched modules.
  - `update` (physics and events): gravity, drag, flocking, collision, plane constraint, events, sub-emitters, triggers, update/collision/death functions, stitched modules.
  - `render`: sprite (blend, sort, orientation, softness, minimum size), the appearance modules (color and size over life, color by speed, color by position, image sequence), shading, mesh, trail, ribbon, light, level of detail.
- `categoryMask` and `customAttributeCount` belong to no stage; they sit on `EmitterModules`.
- `ModuleSlot` carries `isEnabled`, so a module can be turned off without losing its settings.
- Each module is a struct conforming to `ParticleModule` (e.g. `GravityModule`): its settings, its `kind`, whether it is required, the instance editors add, and its part of the GPU uniforms (`contribute`). `SpawnModule`, `UpdateModule`, and `RenderModule` are enums wrapping a stage's types (`StageModule`), saved as `{"module": {"gravity": {"acceleration": [...]}}}`.
- In code, write an emitter as a list (`EmitterDescription("Flame") { ShapeModule(...); GravityModule(...) }`); each module goes to its stage and missing required ones get defaults.

## Order

Built-in modules run at fixed points; only stitched user modules have an order (their stack order).

- Spawn: the built-in spawn, then the spawn function or stitched spawn modules.
- Update, per step: gravity, force fields, flocking, drag, move, then the update function or stitched update modules in order, then the plane constraint, collisions, the plane constraint again, collision and death functions, events, sub-emitters.
- Render: the appearance modules are evaluated when drawing, from each particle's age, speed, and position; their colors multiply, so their order does not matter.

Why built-ins don't follow stack order (#207, won't do): the appearance modules aren't simulation steps at all; force fields, flocking, and collisions need system data (colliders, fields, textures, events) that stitched modules can't get (#208); that leaves gravity, drag, and the plane constraint, where order hardly matters. Behavior that must run at a specific point can be written as a stitched module.

## How the runtime reads modules

- Modules are the only representation (#223): there is no flat settings type. Each module writes its own part of the GPU uniforms (`SimulationModules.swift`, `DrawModules.swift`, #226); a missing module leaves its `NeutralModules` value (no motion, no color change).
- CPU-side values (emission rate, LOD, sub-emitters, triggers, function slots) come from `ResolvedModules`: one pass over the enabled modules, cached per runtime emitter until its modules change (#227).
- Code outside the library builds modules: the `EmitterModulesBuilder` list, `EmitterModules.standard` / `.default2D`, and `modules[SomeModule.self]` to read or change one module.

## Performance

- Built-in modules lower to kernel uniforms; they cost nothing per module.
- A stage's stitched modules are stitched (`MTLFunctionStitchingGraph`) into one function in the stage's function slot. Calling it costs the same as inline code (#205). Graphs and pipelines are cached by the modules' sources and names, not parameter values. The first frame with a new stack stalls while its pipeline builds (#209).
- Custom attributes (`ParticleState.custom`) are loaded and stored only for emitters whose functions mention them (#206).

## Stitched module ABI

```metal
[[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
```

Read your entries from `parameters` and return `parameters + parameterCount`. The runtime packs each module's parameters (padded to `parameterCount`) in stack order. A stage cannot have both a function and stitched modules; `validateFunctions` reports it.

## Shading (#172)

Every emitter has a `ShadingModule` with a model: `.unlit`, `.lit`, `.foil(settings:)`, or `.custom(function:)`. Each particle vertex shader calls the model's `[[visible]]` function once per vertex with a `ShadingInput` (position, normal, sphere normal for sprites, direction to the camera, color, age, lifetime, id, whether it is a mesh), the scene's lights, and a parameters buffer; the function returns the vertex color.

- The built-ins (`particleShadeUnlit`, `particleShadeLit`, `particleShadeFoil`) hold the shading math that was inline before; golden images are unchanged. They are linked into every pipeline that calls a function, so switching between them never compiles a new pipeline.
- Unlit sprites, trails, and ribbons do not call a function: their vertex shaders are compiled with `particleHasShading` false, so the call compiles out. Meshes always call one (unlit meshes shade toward the camera).
- `ShadingModule.perPixel` (#174) calls the function in the fragment shader instead, with the input interpolated (function-constant varyings, absent from other pipelines). Foil sprites always shade per pixel, for their crinkle (#175).
- Foil (#175) reflects a procedural environment and the lights in the metal's color; see `ParticleFoil`.
- Custom functions compile after `ShadingModule.prelude`, which declares `ShadingInput`, `ShadingScene`, and `ShadingLight`.

## Effect files

- Format 4: each layer and sub-emitter has `modules`; appearance modules are in `render`; a shading module replaces the foil module and the sprite's `isLit`.
- Only format 4 loads (#218). Older effects (format 1 flat `settings`, 2 appearance modules in `update`, 3 foil module and `isLit`, and files with no `formatVersion`) fail with an error naming the format.

## Not modules

Colliders, force fields, lights, tracked objects, event bursts, and pointer bindings are system-level.

## Open

- Nothing left from the module refactor besides #209 (first-frame pipeline stall, MetalSprockets #534).
