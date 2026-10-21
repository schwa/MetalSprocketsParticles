// Helpers shared by Simulation.metal and Rendering.metal (#224); each .metal file compiles on its own.
#pragma once
#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// PCG hash based RNG.
static uint hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Linear lookup into a PARTICLE_CURVE_SAMPLES-entry table covering normalized life 0...1.
template <typename T>
static T sampleCurve(constant T *curve, float t) {
    float x = saturate(t) * (PARTICLE_CURVE_SAMPLES - 1);
    uint index = min(uint(x), uint(PARTICLE_CURVE_SAMPLES - 2));
    return mix(curve[index], curve[index + 1], x - float(index));
}

// The tint packed in properties.w as a color multiplier: 1 when there is none.
static float4 particleTint(Particle p) {
    uint tint = as_type<uint>(p.properties.w);
    return tint == 0 ? float4(1) : unpack_unorm4x8_to_float(tint);
}

// Rotates `v` by `angle` radians about the unit `axis` (Rodrigues).
static float3 rotateAbout(float3 v, float3 axis, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1 - c);
}

// A particle's own tumble axis, the same one mesh particles turn about.
static float3 tumbleAxis(uint index) {
    float3 axis = float3(hash(index * 3u + 1u), hash(index * 3u + 2u), hash(index * 3u + 3u)) / 4294967295.0 * 2 - 1;
    return length_squared(axis) > 1e-6 ? normalize(axis) : float3(0, 1, 0);
}
