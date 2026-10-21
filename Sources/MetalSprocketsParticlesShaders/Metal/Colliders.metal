#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// Debug wireframes and solid colliders.

struct WireframeOut {
    float4 position [[position]];
};

vertex WireframeOut wireframeVertex(
    uint vertexID [[vertex_id]],
    const device float4 *vertices [[buffer(0)]],
    constant WireframeUniforms &uniforms [[buffer(1)]]
) {
    return { uniforms.viewProjection * float4(vertices[vertexID].xyz, 1) };
}

fragment float4 wireframeFragment(constant WireframeUniforms &uniforms [[buffer(0)]]) {
    return uniforms.color;
}

// Solid colliders: triangle lists with interleaved (position, normal) float4 pairs.

struct SolidOut {
    float4 position [[position]];
    float3 normal;
};

vertex SolidOut solidVertex(
    uint vertexID [[vertex_id]],
    const device float4 *vertices [[buffer(0)]],
    constant WireframeUniforms &uniforms [[buffer(1)]]
) {
    return { uniforms.viewProjection * float4(vertices[vertexID * 2].xyz, 1), vertices[vertexID * 2 + 1].xyz };
}

// Simple headlight-free shading: one fixed key light from above plus ambient, so shapes read without scene lights.
fragment float4 solidFragment(SolidOut in [[stage_in]], constant WireframeUniforms &uniforms [[buffer(0)]]) {
    float3 light = normalize(float3(0.4, 1.0, 0.3));
    float diffuse = saturate(dot(normalize(in.normal), light));
    return float4(uniforms.color.rgb * (0.35 + 0.65 * diffuse), 1);
}

// Writes the depth-buffer value as a color, for a scene depth texture the particle fragment shader can read.
fragment float solidDepthFragment(SolidOut in [[stage_in]]) {
    return in.position.z;
}
