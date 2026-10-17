#pragma once

#import <simd/simd.h>

// Shared between Swift and Metal. Only 16-byte vector types, so layouts match without padding rules.

typedef struct {
    simd_float4 position; // xyz, w = age (negative = waiting to spawn)
    simd_float4 velocity; // xyz, w = lifetime (0 = never spawned)
    simd_float4 color;
} Particle;

typedef struct {
    simd_float4 emitterPosition; // xyz, w = emitter radius
    simd_float4 emitterVelocity; // xyz = base velocity, w = spread
    simd_float4 gravity;         // xyz, w = drag
    simd_float4 lifetime;        // x = min, y = max, w = deltaTime
    simd_float4 colorStart;
    simd_float4 colorEnd;
    simd_float4 collision;       // x = restitution, y = friction, z = collider count
    simd_uint4 random;           // x = seed, y = step
} SimulationUniforms;

// kind.x: 0 = none, 1 = plane (a = normal, distance), 2 = sphere (a = center, radius), 3 = box (a = center, b = half extents).
typedef struct {
    simd_float4 kind;
    simd_float4 a;
    simd_float4 b;
} ColliderData;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 cameraRight;
    simd_float4 cameraUp;
    simd_float4 size; // x = start size, y = end size
} RenderUniforms;

typedef struct {
    simd_float4x4 viewProjection;
    simd_float4 color;
} WireframeUniforms;
