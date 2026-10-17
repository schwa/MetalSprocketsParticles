#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// PCG hash based RNG.
static uint hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

struct Random {
    uint state;
    float next() { state = hash(state); return float(state) / 4294967295.0; }
    float3 inUnitSphere() {
        for (int i = 0; i < 8; i++) {
            float3 p = float3(next(), next(), next()) * 2.0 - 1.0;
            if (length_squared(p) <= 1.0) { return p; }
        }
        return float3(0);
    }
};

static void collide(thread float3 &position, thread float3 &velocity, float3 normal, float penetration, float restitution, float friction) {
    position += normal * penetration;
    float vn = dot(velocity, normal);
    if (vn < 0) {
        float3 normalVelocity = normal * vn;
        float3 tangentVelocity = velocity - normalVelocity;
        velocity = tangentVelocity * (1.0 - friction) - normalVelocity * restitution;
    }
}

kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant SimulationUniforms &uniforms [[buffer(1)]],
    constant ColliderData *colliders [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    Particle p = particles[id];
    float dt = uniforms.lifetime.w;
    float age = p.position.w + dt;
    float lifetime = p.velocity.w;

    if (age < 0) {
        p.position.w = age;
        particles[id] = p;
        return;
    }

    if (age >= lifetime) {
        Random rng { hash(hash(id ^ uniforms.random.x) ^ uniforms.random.y) };
        float3 position = uniforms.emitterPosition.xyz + rng.inUnitSphere() * uniforms.emitterPosition.w;
        float3 velocity = uniforms.emitterVelocity.xyz + rng.inUnitSphere() * uniforms.emitterVelocity.w;
        lifetime = mix(uniforms.lifetime.x, uniforms.lifetime.y, rng.next());
        // Carry over the overshoot so emission stays smooth.
        age = lifetime > 0 ? fmod(age - p.velocity.w, lifetime) : 0;
        p.position = float4(position, age);
        p.velocity = float4(velocity, lifetime);
    }

    float3 position = p.position.xyz;
    float3 velocity = p.velocity.xyz;
    velocity += uniforms.gravity.xyz * dt;
    velocity *= max(0.0, 1.0 - uniforms.gravity.w * dt);
    position += velocity * dt;

    float restitution = uniforms.collision.x;
    float friction = uniforms.collision.y;

    uint colliderCount = uint(uniforms.collision.z);
    for (uint i = 0; i < colliderCount; i++) {
        ColliderData c = colliders[i];
        int kind = int(c.kind.x);
        if (kind == 1) {
            float distance = dot(position, c.a.xyz) - c.a.w;
            if (distance < 0) { collide(position, velocity, c.a.xyz, -distance, restitution, friction); }
        } else if (kind == 2) {
            float3 offset = position - c.a.xyz;
            float distance = length(offset);
            if (distance < c.a.w && distance > 0) {
                collide(position, velocity, offset / distance, c.a.w - distance, restitution, friction);
            }
        } else if (kind == 3) {
            float3 local = position - c.a.xyz;
            float3 depth = c.b.xyz - abs(local);
            if (all(depth > 0)) {
                // Push out through the nearest face.
                float3 normal = float3(0);
                float penetration;
                if (depth.x < depth.y && depth.x < depth.z) { normal.x = sign(local.x); penetration = depth.x; }
                else if (depth.y < depth.z) { normal.y = sign(local.y); penetration = depth.y; }
                else { normal.z = sign(local.z); penetration = depth.z; }
                collide(position, velocity, normal, penetration, restitution, friction);
            }
        }
    }

    p.position = float4(position, age);
    p.velocity = float4(velocity, lifetime);
    float t = saturate(age / lifetime);
    p.color = mix(uniforms.colorStart, uniforms.colorEnd, t);
    particles[id] = p;
}

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

vertex VertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]]
) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    Particle p = particles[instanceID];
    VertexOut out;
    float age = p.position.w;
    float lifetime = p.velocity.w;
    if (age < 0 || lifetime <= 0) {
        out.position = float4(0, 0, 0, 0); // Degenerate, clipped.
        out.color = 0;
        out.uv = 0;
        return out;
    }
    float t = saturate(age / lifetime);
    float size = mix(uniforms.size.x, uniforms.size.y, t);
    float2 corner = corners[vertexID];
    float3 world = p.position.xyz + (uniforms.cameraRight.xyz * corner.x + uniforms.cameraUp.xyz * corner.y) * size;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = p.color;
    out.uv = corner;
    return out;
}



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

fragment float4 particleFragment(VertexOut in [[stage_in]]) {
    float falloff = saturate(1.0 - length(in.uv));
    float alpha = in.color.a * falloff * falloff;
    return float4(in.color.rgb * alpha, alpha); // Premultiplied.
}
