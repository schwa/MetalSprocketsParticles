# Emitter modules

Design for #178 / #179. An emitter is a stack of modules per stage instead of one flat settings struct.

## Model

- `EmitterDescription.modules: EmitterModules` is the stored, saved model. It holds three ordered stacks:
  - `spawn: [ModuleSlot<SpawnModule>]`: shape, rate, lifetime, velocity, rotation, variation, color image, spawn function, stitched modules.
  - `update: [ModuleSlot<UpdateModule>]`: gravity, drag, flocking, collision, plane constraint, color/size over life, color by speed/position, image sequence, events, sub-emitters, triggers, update/collision/death functions, stitched modules.
  - `render: [ModuleSlot<RenderModule>]`: sprite (blend, sort, orientation, softness, lighting, minimum size), foil, mesh, trail, ribbon, light, level of detail.
- `categoryMask` and `customAttributeCount` belong to no stage; they sit on `EmitterModules`.
- `ModuleSlot` carries `isEnabled`, so a module can be turned off without losing its settings.
- Each module is a struct conforming to `ParticleModule` (e.g. `GravityModule`): its settings, its `kind`, whether it is required, the instance editors add, `apply(to:)` onto `ParticleEmitter`, and `init?(lifting:)` back from one. `SpawnModule`, `UpdateModule`, and `RenderModule` are enums wrapping a stage's types (`StageModule`), saved as `{"module": {"gravity": {"acceleration": [...]}}}`.

## Lowering

- `EmitterModules.lowered()` produces `ParticleEmitter`, the flat form the runtime and kernel read. It starts from `ParticleEmitter.neutral` (no motion, no color change) and applies each enabled module.
- `EmitterModules(_ emitter:)` lifts flat settings to modules. Every preset lifts and lowers back unchanged (`EmitterModulesTests`).
- `EmitterDescription.settings` is a computed view: get lowers, set lifts (keeping disabled modules). Existing code that edits `settings` keeps working.

## Performance rule

The #182 spike measured about 0.07 ms per 1M particles (~22% of simulate) for any user function. #205 found that this is the custom attribute load/store that any function turns on (#206), not the call: a stitched stack costs the same as inline code. So stitching built-ins to honor stack order is viable once #206 is fixed. For now:

- Built-in modules lower to kernel uniforms. They cost nothing per module, and the kernel applies them in its fixed order (gravity, fields, flocking, drag, integrate, user code, constraint, collisions), not stack order.
- Only user modules (`.stitched(StitchedModule)`) run as functions. A stage's stitched modules are stitched (`MTLFunctionStitchingGraph`) into one function in the stage's slot and run in stack order. Graphs and pipelines are cached by the stack's sources and names, not parameter values.

## Stitched module ABI

```metal
[[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
```

Read your entries from `parameters` and return `parameters + parameterCount`. The runtime packs each module's parameters (padded to `parameterCount`) in stack order. A stage cannot have both a `.function` and stitched modules; `validateFunctions` reports it.

## Effect files

- Format 2 (`formatVersion: 2`): each layer has `modules` instead of `settings`.
- Format 1 files (flat `settings`) still load: they lift to modules. Saving writes format 2. `particles-render migrate` rewrites files in place.

## Not modules (unchanged)

Colliders, force fields, lights, tracked objects, event bursts, and pointer bindings are system-level. Sub-emitters keep flat `ParticleEmitter` settings inside the `.subEmitters` module.

## Open

- Render-stage stitching (per-pixel shading, #172/#174/#175) is not done; render modules lower to existing settings.
- Built-in modules cannot be reordered in effect; moving one into a stitched module is the way to change its order.
