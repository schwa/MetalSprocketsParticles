#pragma once

#import <simd/simd.h>
#import "MetalSprocketsShaders.h"

typedef MS_ENUM(uint32_t, ParticleOrientationMode) {
    ParticleOrientationModeBillboard = 0,
    ParticleOrientationModeYAligned = 1,
    ParticleOrientationModeVelocityAligned = 2,
    ParticleOrientationModeFixed = 3,
};

typedef MS_ENUM(uint32_t, ParticleEmitterShapeKind) {
    ParticleEmitterShapeKindPoint = 0,
    ParticleEmitterShapeKindSphere = 1,
    ParticleEmitterShapeKindBox = 2,
    ParticleEmitterShapeKindPlane = 3,
    ParticleEmitterShapeKindDisc = 4,
    ParticleEmitterShapeKindCylinder = 5,
    ParticleEmitterShapeKindCone = 6,
    ParticleEmitterShapeKindTorus = 7,
    ParticleEmitterShapeKindMesh = 8,
    ParticleEmitterShapeKindPoints = 9,
};

typedef MS_ENUM(uint32_t, ParticleBirthLocation) {
    ParticleBirthLocationVolume = 0,
    ParticleBirthLocationSurface = 1,
    /// Mesh vertices. Other shapes treat it as surface.
    ParticleBirthLocationVertices = 2,
};

typedef MS_ENUM(uint32_t, ParticleBirthDirection) {
    /// `emitterVelocity`, plus spread.
    ParticleBirthDirectionVelocity = 0,
    /// Outward from the shape at the birth point, at the speed of `emitterVelocity`, plus spread.
    ParticleBirthDirectionNormal = 1,
    /// Around the shape's +Y axis (counterclockwise looking down +Y), at the speed of `emitterVelocity`, plus spread. Sparks
    /// thrown off a spinning wheel.
    ParticleBirthDirectionTangent = 2,
};

/// One mesh triangle in emitter space. a.w is the cumulative surface area up to and including this triangle, as a
/// fraction of the total, for area-weighted sampling.
typedef struct {
    simd_float4 a;
    simd_float4 b;
    simd_float4 c;
} EmitterMeshTriangle;

/// One point of a point cache, stored in the mesh triangle buffer (same size). position.w = 1 when `color` is set;
/// normal.w = 1 when `normal` is set.
typedef struct {
    simd_float4 position;
    simd_float4 normal;
    simd_float4 color;
} EmitterPointData;

typedef MS_ENUM(uint32_t, ParticleSpawnOccasion) {
    ParticleSpawnOccasionBirth = 0,
    ParticleSpawnOccasionDeath = 1,
    ParticleSpawnOccasionCollision = 2,
    ParticleSpawnOccasionWhileAlive = 3,
    /// Once, when the parent's age reaches `interval` seconds.
    ParticleSpawnOccasionAge = 4,
    /// When the parent moves into `volume` during a step.
    ParticleSpawnOccasionEnterVolume = 5,
};

/// Trigger counters: one per collider, then one per trigger volume. Monotonic; the CPU diffs them between frames.
#define PARTICLE_TRIGGER_MAX_COLLIDERS 64
#define PARTICLE_TRIGGER_MAX_VOLUMES 64

/// Mirrored by the Swift TriggerVolume.
typedef MS_ENUM(uint32_t, ParticleTriggerVolumeKind) {
    ParticleTriggerVolumeKindSphere = 1,
    ParticleTriggerVolumeKindBox = 2,
};

/// A volume that counts particles entering it. World space.
struct TriggerVolumeData {
    ParticleTriggerVolumeKind kind;
    float radius;            // Sphere.
    simd_float3 center;
    simd_float3 halfExtents; // Box.

#if defined(__METAL_VERSION__)
    bool contains(float3 point) const {
        if (kind == ParticleTriggerVolumeKindSphere) {
            return metal::distance(point, center) < radius;
        }
        return metal::all(metal::abs(point - center) < halfExtents);
    }
#endif
};
typedef struct TriggerVolumeData TriggerVolumeData;

/// A sub-emitter as the parent's kernel sees it. Each parent slot owns `countPerEvent` child slots in the child's
/// slice. Mirrored by the Swift SubEmitter.
typedef struct {
    ParticleSpawnOccasion occasion;
    uint32_t countPerEvent;
    uint32_t childSliceStart; // In the shared particle buffer.
    uint32_t childCapacity;
    float velocityFactor;     // Fraction of the parent's velocity children inherit.
    float interval;           // Seconds between children for ParticleSpawnOccasionWhileAlive; the age for Age.
    uint32_t replacesParent;  // Nonzero: the parent dies when it spawns children, so it turns into them.
    uint32_t continuesParentLife; // Nonzero: children take the parent's age and lifetime instead of starting at 0.
    TriggerVolumeData volume; // For ParticleSpawnOccasionEnterVolume.
} SubEmitterData;

/// Builds back-to-front sort records for one emitter's live window. Records are uint2(key, particle index).
typedef struct {
    simd_float3 cameraPosition; // World space.
    simd_float3 cameraForward;  // World space, unit length.
    simd_float4x4 model;        // Simulation space to world, as in RenderUniforms.
    uint32_t firstSlot;         // First live slot in the emitter's ring.
    uint32_t liveCount;
    uint32_t capacity;          // Emitter capacity (ring size).
    uint32_t sliceStart;        // Emitter slice start in the shared buffer.
} ParticleSortKeyParams;

/// One LSD radix pass over 8 bits of the key.
typedef struct {
    uint32_t numElements;
    uint32_t numTiles;
    uint32_t elementsPerTile;
    uint32_t shift;
} ParticleRadixParams;

/// Samples per over-life lookup table (color, size).
#define PARTICLE_CURVE_SAMPLES 64

typedef MS_ENUM(uint32_t, ParticleBlendMode) {
    /// Premultiplied alpha over the destination.
    ParticleBlendModeAlpha = 0,
    /// Adds light. Order independent; good for fire, sparks, and glow.
    ParticleBlendModeAdditive = 1,
    /// Brightens like additive but never exceeds white.
    ParticleBlendModeScreen = 2,
    /// No blending. Fragments below half coverage are discarded.
    ParticleBlendModeOpaque = 3,
};

/// Debug views that replace particle colors (ParticleSystemRuntime.debugView).
typedef MS_ENUM(uint32_t, ParticleDebugMode) {
    ParticleDebugModeNone = 0,
    /// Geometry as lines, solid color.
    ParticleDebugModeWireframe = 1,
    /// A distinct color per emitter.
    ParticleDebugModeEmitter = 2,
    /// Age as a fraction of lifetime, blue (born) to red (dying).
    ParticleDebugModeAge = 3,
    /// Speed through debugSpeedRange, blue (slow) to red (fast).
    ParticleDebugModeSpeed = 4,
    /// Seconds of life left, through debugSpeedRange.y seconds, red (none) to blue (plenty).
    ParticleDebugModeLifeRemaining = 5,
    /// Position in the emitter's ring of slots, blue (first) to red (last).
    ParticleDebugModeSlot = 6,
    /// A dim additive color, so bright areas show where many particles overlap.
    ParticleDebugModeOverdraw = 7,
};

typedef MS_ENUM(uint32_t, ParticleImageSequenceMode) {
    /// Wraps to the first frame after the last.
    ParticleImageSequenceModeRepeat = 0,
    /// Holds the last frame.
    ParticleImageSequenceModeClamp = 1,
    /// Plays forward, then backward.
    ParticleImageSequenceModeAutoReverse = 2,
};

// Per-particle storage, packed into float4s to keep particles small. Everything else uses named fields.
typedef struct {
    simd_float4 position; // xyz, w = age
    simd_float4 velocity; // xyz, w = lifetime (0 = never spawned). Dead when age >= lifetime.
    simd_float4 color;      // Per-particle hue, saturation, brightness, alpha offsets applied to the color-over-life curve.
    simd_float4 rotation;   // x = angle (radians), y = angular velocity (radians per second), z = initial frame, w = frame rate
    simd_float4 properties; // x = size scale, y = restitution offset, z = friction offset, w = tint (RGBA8 bits; 0 = none)
} Particle;

/// Where newborn particles are placed, in emitter space. Mirrored by the Swift EmitterShape plus the birth settings on
/// ParticleEmitter. Fields a kind does not use are zero.
typedef struct {
    ParticleEmitterShapeKind kind;
    ParticleBirthLocation birthLocation;
    ParticleBirthDirection birthDirection;
    float sweep;                // Radians of azimuth around +Y that emit.
    simd_float3 center;         // ParticleEmitter.position.
    simd_float3 size;           // Box: full size. Plane: full size in x and z.
    float radius;               // Sphere, disc, cylinder, cone, torus.
    float height;               // Cylinder, cone.
    float tubeRadius;           // Torus.
    uint32_t meshTriangleCount; // Mesh.
    uint32_t meshVertexCount;   // Mesh.
    // Mesh with deformed positions (morphing, skinning): packed float3 at offset + stride * vertex in the deformed
    // buffer, read through the triangle indices. Stride 0 uses the rest positions.
    uint32_t deformedPositionOffset;
    uint32_t deformedPositionStride;
} ParticleShapeData;

/// Per-particle random offsets at birth: each value is drawn from -range...+range.
typedef struct {
    float size;        // Fraction of the size.
    float restitution;
    float friction;
    float speed;
    simd_float4 color; // Hue (turns), saturation, brightness, alpha.
    float angle;
    float angularSpeed;
    float initialFrame;
    float frameRate;
} ParticleVariationData;

/// Which part of the shared buffer an emitter owns and which of its slots a step touches.
typedef struct {
    uint32_t seed;
    uint32_t capacity;   // Slots in the emitter's ring.
    uint32_t sliceStart; // Ring start in the shared buffer.
    uint32_t firstSlot;  // First ring slot this dispatch covers.
    uint32_t cursor;     // First slot to spawn into.
    uint32_t count;      // Particles to spawn this step.
    uint32_t serial;     // Spawn serial of the first spawned particle.
    uint32_t kill;       // Nonzero to kill every particle before this step.
} ParticleSpawnData;

// One emitter's settings for one simulation step. Each emitter owns a slice of the shared particle buffer.
typedef struct {
    // Emitter-local to simulation space at the end of this step. Identity when simulating in local space.
    simd_float4x4 emitterTransform;
    // Gravity, force fields, and colliders are in world space. These convert particles to world space for that part of
    // the step and back. Identity for world-space emitters.
    simd_float4x4 simulationToWorld;
    simd_float4x4 worldToSimulation;
    // Simulation-space translation of the emitter at the start of the step, so births within the step can be placed
    // along the emitter's path.
    simd_float3 previousEmitterOrigin;
    // Added to every newborn particle (inherited emitter velocity), in simulation space.
    simd_float3 inheritedVelocity;
    // The emitter's rotation over this step, from the previous transform to the current one: unit axis and angle. Births
    // earlier in the step are rotated back along it. Angle 0 means no rotation.
    simd_float3 spinAxis;
    float spinAngle;
    // Angular velocity (axis times radians per second) times inheritVelocity: newborns get its cross product with their
    // offset from the emitter origin.
    simd_float3 inheritedAngularVelocity;
    ParticleShapeData shape;
    simd_float3 velocity; // Base birth velocity, emitter space.
    float velocitySpread;
    simd_float3 gravity;  // World space.
    float drag;
    float lifetimeMinimum;
    float lifetimeMaximum;
    float deltaTime;
    float time;           // Emitter clock in seconds; drives turbulence.
    float restitution;
    float friction;
    uint32_t diesOnCollision;
    uint32_t countsColliderHits; // Nonzero to add collider hits to the trigger counters.
    float angle;
    float angularSpeed;
    float initialFrame;
    float frameRate;
    ParticleVariationData variation;
    // Colliders and force fields bound for this dispatch: only those whose category matches the emitter's masks.
    uint32_t colliderCount;
    uint32_t forceFieldCount;
    uint32_t subEmitterCount;
    uint32_t triggerVolumeCount;
    ParticleSpawnData spawn;
    // Live-particle counting for statistics: nonzero on each emitter's last dispatch of a frame, which adds its live
    // particles to aliveCounters[aliveCounterSlot].
    uint32_t countsAlive;
    uint32_t aliveCounterSlot;
    // Nonzero to call the emitter's user update function (updateFunction[0]) each step.
    uint32_t hasUpdateFunction;
    // Nonzero to call the emitter's user spawn function (spawnFunction[0]) for each new particle.
    uint32_t hasSpawnFunction;
    // Nonzero to call collisionFunction[0] when a particle hits a collider, and deathFunction[0] when it dies.
    uint32_t hasCollisionFunction;
    uint32_t hasDeathFunction;
    // Nonzero: keep particles on the plane through planePoint with planeNormal (world space, unit length).
    uint32_t constrainsToPlane;
    simd_float3 planePoint;
    simd_float3 planeNormal;
    // Nonzero to write ParticleEventRecords for collisions and deaths. eventEmitterIndex goes in each record.
    uint32_t reportsCollisions;
    uint32_t reportsDeaths;
    uint32_t eventEmitterIndex;
    // Nonzero to collide with the scene depth texture (DepthCollisionData).
    uint32_t collidesWithSceneDepth;
    // Trails: keep the last trailPointCount positions (simulation space) of each particle at trails[id * trailStride].
    // 0 for emitters without trails.
    uint32_t trailPointCount;
    uint32_t trailStride;
    // Seconds between recorded trail points; 0 records one every step. Each point's w is the age it was recorded at.
    float trailPointInterval;
    // Flocking: add steering[id].xyz (from the flocking pass) to velocity, then keep speed in flockSpeedRange.
    uint32_t flocks;
    simd_float2 flockSpeedRange;
    // Particles collide as spheres of this radius: colliders are inflated by it. 0 keeps them points.
    float collisionRadius;
    // Nonzero: particles born in one step get birth ages in slot order, not at random, so slot order matches order along
    // the emitter's path (ribbons join particles in slot order).
    uint32_t ordersBirths;
    // Nonzero: at birth, sample the birth color curve along birthColorStart...birthColorEnd (world space) at the spawn
    // position and multiply it into the particle's tint (ParticleEmitter.colorByPositionAtBirth).
    // ParticleState custom attributes this emitter keeps, 1 to 4.
    uint32_t customAttributeCount;
    uint32_t colorsByBirthPosition;
    simd_float3 birthColorStart;
    simd_float3 birthColorEnd;
} SimulationUniforms;

/// Cells in the flocking spatial hash. Neighbor cells that hash to the same entry are searched once.
#define PARTICLE_FLOCK_TABLE_SIZE 16384

/// One emitter's flocking pass: its live window (windowCount ring slots from windowStart, wrapping at capacity),
/// neighbor radius (also the grid cell size), and the boids weights.
typedef struct {
    uint32_t sliceStart;
    uint32_t capacity;
    uint32_t windowStart;
    uint32_t windowCount;
    float radius;
    float separationRadius;
    float separation;
    float alignment;
    float cohesion;
    uint32_t maxNeighbors;
} FlockData;

/// The scene depth the simulation collides with: last frame's SceneDepth texture and the camera that drew it.
typedef struct {
    simd_float4x4 viewProjection;
    simd_float4x4 inverseViewProjection;
    simd_float3 cameraPosition;
    simd_uint2 size;
    // Particles more than this far behind the surface are taken to be behind the object, not inside it.
    float thickness;
    uint32_t enabled;
} DepthCollisionData;

/// ParticleEventRecord.colliderIndex for hits on the scene depth.
#define PARTICLE_EVENT_SCENE_DEPTH_COLLIDER 0xFFFFFFFEu

/// Records kept in the event ring; older ones are overwritten if the CPU falls behind.
#define PARTICLE_EVENT_CAPACITY 4096

typedef MS_ENUM(uint32_t, ParticleEventKind) {
    ParticleEventKindCollision = 1,
    ParticleEventKindDeath = 2,
};

/// One event, in world space. Written to slot (sequence - 1) % PARTICLE_EVENT_CAPACITY; `sequence` is written last so
/// the CPU can tell a finished record from one still being written.
typedef struct {
    simd_float4 position;     // xyz, w = simulation time
    simd_float4 velocity;     // xyz
    ParticleEventKind kind;
    uint32_t emitterIndex;
    uint32_t colliderIndex;   // Collisions: index in the system's colliders. Deaths: UINT32_MAX.
    uint32_t sequence;
} ParticleEventRecord;

/// Most lights gathered from particles (ParticleEmitter.light) across the whole system.
#define PARTICLE_MAX_PARTICLE_LIGHTS 16

/// One emitter's light gathering: `count` lights, each from the first live particle in its stretch of the live window
/// (`windowCount` ring slots from `windowStart`, wrapping at `capacity`), written from `firstLight` in the particle
/// light buffer.
typedef struct {
    uint32_t sliceStart;
    uint32_t capacity;
    uint32_t windowStart;
    uint32_t windowCount;
    uint32_t count;
    uint32_t firstLight;
    simd_float3 color; // Color times intensity, at full remaining life.
    float range;
    simd_float4x4 simulationToWorld;
} ParticleLightGatherData;

/// Frames of live-particle counters kept so the CPU can read a finished frame's count while others are in flight. The
/// counter buffer holds three runs of slots: live particles, then births, then deaths.
#define PARTICLE_ALIVE_COUNTER_SLOTS 5

/// Mirrored by the Swift Collider.
typedef MS_ENUM(uint32_t, ParticleColliderKind) {
    ParticleColliderKindPlane = 1,
    ParticleColliderKindSphere = 2,
    ParticleColliderKindBox = 3,
    ParticleColliderKindCapsule = 4,
};

// World space. Fields a kind does not use are zero.
typedef struct {
    ParticleColliderKind kind;
    float radius;            // Sphere, capsule.
    float distance;          // Plane: offset along the normal.
    simd_float3 normal;      // Plane, unit length.
    simd_float3 center;      // Sphere, box. Capsule: start.
    simd_float3 end;         // Capsule.
    simd_float3 halfExtents; // Box.
    simd_float4 rotation;    // Box orientation quaternion (xyz = imaginary, w = real).
    simd_float3 velocity;    // Collider velocity this step.
    uint32_t triggerIndex;   // Index in ParticleSystemRuntime.colliders, for collider-hit trigger counters.
    // Rotation speed (axis times radians per second) about `pivot`: a contact point moves at
    // velocity + angularVelocity x (point - pivot).
    simd_float3 angularVelocity;
    simd_float3 pivot;
} ColliderData;

/// Mirrored by the Swift ForceField.
typedef MS_ENUM(uint32_t, ParticleForceFieldKind) {
    ParticleForceFieldKindWind = 1,
    ParticleForceFieldKindAttractor = 2,
    ParticleForceFieldKindVortex = 3,
    ParticleForceFieldKindTurbulence = 4,
    ParticleForceFieldKindPath = 5,
};

// World space. Fields a kind does not use are zero.
typedef struct {
    ParticleForceFieldKind kind;
    float strength;
    float radius;         // Attractor, vortex. 0 means unlimited range.
    float scale;          // Turbulence: noise frequency per world unit.
    float speed;          // Turbulence: how fast the pattern changes.
    simd_float3 velocity; // Wind.
    simd_float3 center;   // Attractor, vortex.
    simd_float3 axis;     // Vortex, unit length.
    // Path: a polyline of pathCount points from pathStart in the path point buffer; closed loops back to the start.
    // speed is along the path, strength pulls onto it (per second), radius limits the range.
    uint32_t pathStart;
    uint32_t pathCount;
    uint32_t pathClosed;
} ForceFieldData;

/// Lights for emitters with lighting on. Mirrored by the Swift ParticleLight.
#define PARTICLE_MAX_LIGHTS 8

typedef MS_ENUM(uint32_t, ParticleLightKind) {
    ParticleLightKindDirectional = 1,
    ParticleLightKindPoint = 2,
};

// World space. Fields a kind does not use are zero.
typedef struct {
    ParticleLightKind kind;
    float range;           // Point: light fades to zero at this distance. 0 means no falloff.
    simd_float3 color;     // Color times intensity.
    simd_float3 direction; // Directional: the direction light travels, unit length.
    simd_float3 position;  // Point.
} ParticleLightData;

typedef struct {
    simd_float4x4 viewProjection;
    // Simulation space to world. The emitter transform when simulating in local space, otherwise identity.
    simd_float4x4 model;
    simd_float3 cameraRight;
    simd_float3 cameraUp;
    simd_float3 cameraPosition;
    simd_float3 fixedNormal; // ParticleOrientationModeFixed: plane normal, unit length.
    float velocityStretch;   // ParticleOrientationModeVelocityAligned.
    ParticleOrientationMode orientationMode;
    ParticleBlendMode blendMode;
    uint32_t hasTexture;
    uint32_t sheetColumns;
    uint32_t sheetRows;
    uint32_t frameCount;
    ParticleImageSequenceMode sequenceMode;
    uint32_t readsSortRecords; // Nonzero to read particles through the sort records.
    simd_float3 cameraForward; // World space, unit length.
    // Lighting, when isLit is nonzero: color times (ambientLight + the lights' diffuse light).
    simd_float3 ambientLight;
    uint32_t isLit;
    uint32_t lightCount;
    uint32_t particleLightCount; // Lights gathered from emitting particles, after the scene lights.
    // Soft particles, when softness > 0 and hasSceneDepth is nonzero: fade out over `softness` world units in front of
    // the scene depth. depthUnproject (a, b, c) turns a depth-buffer value d into view distance: -b / (d * c - a).
    float softness;
    uint32_t hasSceneDepth;
    simd_float3 depthUnproject;
    // Extra gradients, in the extra color curve table (PARTICLE_CURVE_SAMPLES each): by speed (multiplies; speed mapped
    // from speedColorRange to 0...1), an alternate over-life gradient (each particle blends toward it by a fixed random
    // amount), and by position (multiplies; from positionColorStart to positionColorEnd).
    uint32_t hasSpeedColor;
    uint32_t hasAlternateColor;
    uint32_t hasPositionColor;
    simd_float2 speedColorRange;
    simd_float3 positionColorStart;
    simd_float3 positionColorEnd;
    // Ribbons (ParticleEmitter.trail): points per trail, the stride between particles' trails, and whether width
    // tapers and opacity fades toward the tail.
    uint32_t trailPointCount;
    uint32_t trailStride;
    uint32_t trailTapers;
    uint32_t trailFades;
    // Debug view: the mode, the emitter's index (for per-emitter colors), its slice, and ranges for speed (x...y) and
    // remaining life (0...y seconds).
    ParticleDebugMode debugMode;
    uint32_t debugEmitterIndex;
    uint32_t debugSliceStart;
    uint32_t debugCapacity;
    simd_float2 debugRange;
    // Emitter ribbons (ParticleEmitter.ribbon): the live window, oldest first, as ring slots of the emitter's slice.
    uint32_t ribbonSliceStart;
    uint32_t ribbonCapacity;
    uint32_t ribbonWindowStart;
    uint32_t ribbonWindowCount;
    uint32_t ribbonTapers;
    // Size adjustments, off at 1 and 0: sizeScale multiplies every particle (distance LOD compensation), and particles
    // are never smaller on screen than minimumScreenSize (half-size as a fraction of the view height). projectionScaleY
    // is projection[1][1], to turn sizes at a distance into screen fractions.
    float sizeScale;
    float minimumScreenSize;
    float projectionScaleY;
} RenderUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 color;
} WireframeUniforms;
