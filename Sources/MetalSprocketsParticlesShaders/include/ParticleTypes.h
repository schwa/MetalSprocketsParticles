#pragma once

#import <simd/simd.h>
#import "MetalSprocketsShaders.h"

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
    simd_float4 color;    // Per-particle tint, multiplied with the color-over-life curve.
    simd_float4 rotation; // x = angle (radians), y = angular velocity (radians per second), z = initial frame, w = frame rate
} Particle;

typedef struct {
    simd_float4 emitterPosition; // xyz, w = emitter radius
    simd_float4 emitterVelocity; // xyz = base velocity, w = spread
    simd_float4 gravity;         // xyz, w = drag
    simd_float4 lifetime;        // x = min, y = max, w = deltaTime
    simd_float4 collision;       // x = restitution, y = friction, z = collider count
    simd_float4 rotation;        // x = angle, y = angle variation, z = angular speed, w = angular speed variation
    simd_float4 imageSequence;   // x = initial frame, y = initial frame variation, z = frame rate, w = frame rate variation
    simd_float4 fields;          // x = force field count, y = simulation time (seconds)
    simd_uint4 random;           // x = seed, y = capacity
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
    simd_float4 cameraRight;
    simd_float4 cameraUp;
    simd_uint4 options; // x = ParticleBlendMode, y = has texture, z = sheet columns, w = sheet rows
    simd_uint4 imageSequence; // x = frame count, y = ParticleImageSequenceMode
} RenderUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 color;
} WireframeUniforms;
