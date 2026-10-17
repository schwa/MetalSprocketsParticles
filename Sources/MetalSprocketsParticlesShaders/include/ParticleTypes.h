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
};

/// One mesh triangle in emitter space. a.w is the cumulative surface area up to and including this triangle, as a
/// fraction of the total, for area-weighted sampling.
typedef struct {
    simd_float4 a;
    simd_float4 b;
    simd_float4 c;
} EmitterMeshTriangle;

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

typedef MS_ENUM(uint32_t, ParticleImageSequenceMode) {
    /// Wraps to the first frame after the last.
    ParticleImageSequenceModeRepeat = 0,
    /// Holds the last frame.
    ParticleImageSequenceModeClamp = 1,
    /// Plays forward, then backward.
    ParticleImageSequenceModeAutoReverse = 2,
};

// Shared between Swift and Metal. Only 16-byte vector types, so layouts match without padding rules.

typedef struct {
    simd_float4 position; // xyz, w = age
    simd_float4 velocity; // xyz, w = lifetime (0 = never spawned). Dead when age >= lifetime.
    simd_float4 color;      // Per-particle hue, saturation, brightness, alpha offsets applied to the color-over-life curve.
    simd_float4 rotation;   // x = angle (radians), y = angular velocity (radians per second), z = initial frame, w = frame rate
    simd_float4 properties; // x = size scale, y = restitution offset, z = friction offset
} Particle;

// One emitter's settings for one simulation step. Each emitter owns a slice of the shared particle buffer.
typedef struct {
    // Emitter-local to simulation space at the end of this step. Identity when simulating in local space.
    simd_float4x4 emitterTransform;
    // Gravity, force fields, and colliders are in world space. These convert particles to world space for that part of
    // the step and back. Identity for world-space emitters.
    simd_float4x4 simulationToWorld;
    simd_float4x4 worldToSimulation;
    // xyz = simulation-space translation of the emitter at the start of the step, so births within the step can be
    // placed along the emitter's path. w unused.
    simd_float4 previousEmitterOrigin;
    // xyz = velocity added to every newborn particle (inherited emitter velocity), in simulation space.
    simd_float4 inheritedVelocity;
    simd_float4 emitterPosition; // xyz = shape center, w unused
    simd_uint4 shape;            // x = ParticleEmitterShapeKind, y = ParticleBirthLocation, z = ParticleBirthDirection
    simd_float4 shapeParameters; // per kind: sphere x = radius; box xyz = size; plane xy = size; disc x = radius;
                                 // cylinder/cone x = radius, y = height; torus x = radius, y = tube radius. w = sweep
    simd_uint4 meshCounts;       // x = triangle count, y = vertex count
    simd_float4 emitterVelocity; // xyz = base velocity, w = spread
    simd_float4 gravity;         // xyz (world space), w = drag
    simd_float4 lifetime;        // x = min, y = max, w = deltaTime
    simd_float4 collision;       // x = restitution, y = friction, z = collider count, w = nonzero to die on contact
    simd_float4 rotation;        // x = angle, y = angle variation, z = angular speed, w = angular speed variation
    simd_float4 imageSequence;   // x = initial frame, y = initial frame variation, z = frame rate, w = frame rate variation
    simd_float4 fields;          // x = force field count, y = simulation time (seconds)
    simd_float4 variation;       // +/- ranges: x = size (fraction), y = restitution, z = friction, w = speed
    simd_float4 colorVariation;  // +/- ranges: hue (turns), saturation, brightness, alpha
    simd_uint4 random;           // x = seed, y = slice capacity, z = slice start in the shared buffer
    // x = ring cursor (first slot to spawn into), y = spawn count, z = spawn serial of the first spawned particle,
    // w = nonzero to kill all particles before this step.
    simd_uint4 spawn;
} SimulationUniforms;

// kind.x: 0 = none, 1 = plane (a = normal, distance), 2 = sphere (a = center, radius),
// 3 = box (a = center, b = half extents, rotation = orientation), 4 = capsule (a = start, radius; b = end).
typedef struct {
    simd_float4 kind;
    simd_float4 a;
    simd_float4 b;
    simd_float4 velocity; // xyz = collider velocity this step
    simd_float4 rotation; // quaternion (xyz = imaginary, w = real)
} ColliderData;

// kind.x: 1 = wind (a = velocity, strength), 2 = attractor (a = center, strength; b.x = radius),
// 3 = vortex (a = center, strength; b = axis, radius), 4 = turbulence (a.x = strength, a.y = scale, a.z = speed).
typedef struct {
    simd_float4 kind;
    simd_float4 a;
    simd_float4 b;
} ForceFieldData;

typedef struct {
    simd_float4x4 viewProjection;
    // Simulation space to world. The emitter transform when simulating in local space, otherwise identity.
    simd_float4x4 model;
    simd_float4 cameraRight;
    simd_float4 cameraUp;
    simd_uint4 options; // x = ParticleBlendMode, y = has texture, z = sheet columns, w = sheet rows
    simd_uint4 imageSequence; // x = frame count, y = ParticleImageSequenceMode
    simd_float4 cameraPosition;
    simd_float4 orientation;  // xyz = fixed plane normal, w = velocity stretch factor
    simd_uint4 orientationMode; // x = ParticleOrientationMode
} RenderUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 color;
} WireframeUniforms;
