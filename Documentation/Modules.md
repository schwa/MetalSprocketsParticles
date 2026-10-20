# Emitter modules

Design for #178 / #179. An emitter is module stacks per stage instead of one flat settings struct.

## Model

- `EmitterDescription.modules: EmitterModules` is the stored, saved model. It holds three stacks:
  - `spawn`: shape, rate, lifetime, velocity, rotation, variation, color image, spawn function, stitched modules.
  - `update` (physics and events): gravity, drag, flocking, collision, plane constraint, events, sub-emitters, triggers, update/collision/death functions, stitched modules.
  - `render`: sprite (blend, sort, orientation, softness, lighting, minimum size), the appearance modules (color and size over life, color by speed, color by position, image sequence), foil, mesh, trail, ribbon, light, level of detail.
- `categoryMask` and `customAttributeCount` belong to no stage; they sit on `EmitterModules`.
- `ModuleSlot` carries `isEnabled`, so a module can be turned off without losing its settings.
- Each module is a struct conforming to `ParticleModule` (e.g. `GravityModule`): its settings, its `kind`, whether it is required, the instance editors add, `apply(to:)` onto `ParticleEmitter`, and `init?(lifting:)` back from one. `SpawnModule`, `UpdateModule`, and `RenderModule` are enums wrapping a stage's types (`StageModule`), saved as `{"module": {"gravity": {"acceleration": [...]}}}`.
- In code, write an emitter as a list (`EmitterDescription("Flame") { ShapeModule(...); GravityModule(...) }`); each module goes to its stage and missing required ones get defaults.

## Order

Built-in modules run at fixed points; only stitched user modules have an order (their stack order).

- Spawn: the built-in spawn, then the spawn function or stitched spawn modules.
- Update, per step: gravity, force fields, flocking, drag, move, then the update function or stitched update modules in order, then the plane constraint, collisions, the plane constraint again, collision and death functions, events, sub-emitters.
- Render: the appearance modules are evaluated when drawing, from each particle's age, speed, and position; their colors multiply, so their order does not matter.

Why built-ins don't follow stack order (#207, won't do): the appearance modules aren't simulation steps at all; force fields, flocking, and collisions need system data (colliders, fields, textures, events) that stitched modules can't get (#208); that leaves gravity, drag, and the plane constraint, where order hardly matters. Behavior that must run at a specific point can be written as a stitched module.

## Lowering

- `EmitterModules.lowered()` produces `ParticleEmitter`, the internal flat form the runtime reads. It starts from `ParticleEmitter.neutral` (no motion, no color change) and applies each enabled module.
- `EmitterDescription` and `SubEmitter` cache the lowered form when modules change, so reading `settings` every frame is free.
- `EmitterModules(_ emitter:)` lifts flat settings to modules. Every preset lifts and lowers back unchanged (`EmitterModulesTests`).
- `ParticleEmitter`, `EmitterDescription.settings`, `SubEmitter.settings`, and the runtime's flat-settings API are internal (#204). Code outside the library builds modules: the `EmitterModulesBuilder` list, `EmitterModules.standard` / `.default2D`, and `modules[SomeModule.self]` to read or change one module.

## Performance

- Built-in modules lower to kernel uniforms; they cost nothing per module.
- A stage's stitched modules are stitched (`MTLFunctionStitchingGraph`) into one function in the stage's function slot. Calling it costs the same as inline code (#205). Graphs and pipelines are cached by the modules' sources and names, not parameter values. The first frame with a new stack stalls while its pipeline builds (#209).
- Custom attributes (`ParticleState.custom`) are loaded and stored only for emitters whose functions mention them (#206).

## Stitched module ABI

```metal
[[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
```

Read your entries from `parameters` and return `parameters + parameterCount`. The runtime packs each module's parameters (padded to `parameterCount`) in stack order. A stage cannot have both a function and stitched modules; `validateFunctions` reports it.

## Effect files

- Format 3: each layer and sub-emitter has `modules`; appearance modules are in `render`.
- Format 2 (appearance modules in `update`) and format 1 (flat `settings`) still load. Saving writes format 3. `particles-migrate` rewrites files in place.

## Not modules

Colliders, force fields, lights, tracked objects, event bursts, and pointer bindings are system-level.

## Open

- Render-stage stitching (per-pixel shading, #172/#174/#175).
