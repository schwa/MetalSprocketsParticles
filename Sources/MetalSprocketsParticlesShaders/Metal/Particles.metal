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

// Response is computed relative to the collider, so moving colliders push and carry particles.
static void collide(thread float3 &position, thread float3 &velocity, ColliderData c, float3 normal, float penetration, float restitution, float friction) {
    position += normal * penetration;
    float3 colliderVelocity = c.velocity.xyz;
    float3 relative = velocity - colliderVelocity;
    float vn = dot(relative, normal);
    if (vn < 0) {
        float3 normalVelocity = normal * vn;
        float3 tangentVelocity = relative - normalVelocity;
        velocity = colliderVelocity + tangentVelocity * (1.0 - friction) - normalVelocity * restitution;
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
    uint capacity = uniforms.random.y;

    if (uniforms.spawn.w != 0) {
        p.position.w = 0;
        p.velocity.w = 0;
    }

    // Particles spawn into a ring: this step owns `spawn.y` slots starting at the cursor. The oldest particles get
    // recycled first. Randomness comes from the spawn serial, not the slot, so results do not depend on thread order.
    uint offset = (id + capacity - uniforms.spawn.x) % capacity;
    if (offset < uniforms.spawn.y) {
        Random rng { hash(hash(uniforms.spawn.z + offset) ^ uniforms.random.x) };
        float3 position = uniforms.emitterPosition.xyz + rng.inUnitSphere() * uniforms.emitterPosition.w;
        float3 velocity = uniforms.emitterVelocity.xyz + rng.inUnitSphere() * uniforms.emitterVelocity.w;
        float lifetime = mix(uniforms.lifetime.x, uniforms.lifetime.y, rng.next());
        // Spread births across the step so particles born in the same step do not move as one sheet.
        dt *= rng.next();
        // Drawn after the values above so adding rotation did not change existing random streams.
        float angle = uniforms.rotation.x + (rng.next() * 2 - 1) * uniforms.rotation.y;
        float angularVelocity = uniforms.rotation.z + (rng.next() * 2 - 1) * uniforms.rotation.w;
        p.position = float4(position, 0);
        p.velocity = float4(velocity, lifetime);
        p.rotation = float4(angle, angularVelocity, 0, 0);
    }

    float lifetime = p.velocity.w;
    float age = p.position.w;
    if (lifetime <= 0 || age >= lifetime) {
        particles[id] = p;
        return;
    }
    age += dt;

    float3 position = p.position.xyz;
    float3 velocity = p.velocity.xyz;
    velocity += uniforms.gravity.xyz * dt;
    velocity *= max(0.0, 1.0 - uniforms.gravity.w * dt);
    position += velocity * dt;
    p.rotation.x += p.rotation.y * dt;

    float restitution = uniforms.collision.x;
    float friction = uniforms.collision.y;

    uint colliderCount = uint(uniforms.collision.z);
    for (uint i = 0; i < colliderCount; i++) {
        ColliderData c = colliders[i];
        int kind = int(c.kind.x);
        if (kind == 1) {
            float distance = dot(position, c.a.xyz) - c.a.w;
            if (distance < 0) { collide(position, velocity, c, c.a.xyz, -distance, restitution, friction); }
        } else if (kind == 2) {
            float3 offset = position - c.a.xyz;
            float distance = length(offset);
            if (distance < c.a.w && distance > 0) {
                collide(position, velocity, c, offset / distance, c.a.w - distance, restitution, friction);
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
                collide(position, velocity, c, normal, penetration, restitution, friction);
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
    if (lifetime <= 0 || age >= lifetime) {
        out.position = float4(0, 0, 0, 0); // Degenerate, clipped.
        out.color = 0;
        out.uv = 0;
        return out;
    }
    float t = saturate(age / lifetime);
    float size = mix(uniforms.size.x, uniforms.size.y, t);
    float2 corner = corners[vertexID];
    // Rotate the quad, not the UVs, so textures spin with it.
    float s = sin(p.rotation.x);
    float c = cos(p.rotation.x);
    float2 offset = float2(c * corner.x - s * corner.y, s * corner.x + c * corner.y);
    float3 world = p.position.xyz + (uniforms.cameraRight.xyz * offset.x + uniforms.cameraUp.xyz * offset.y) * size;
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

fragment float4 particleFragment(VertexOut in [[stage_in]], constant RenderUniforms &uniforms [[buffer(0)]]) {
    float falloff = saturate(1.0 - length(in.uv));
    float alpha = in.color.a * falloff * falloff;
    if (uniforms.options.x == ParticleBlendModeOpaque) {
        if (alpha < 0.5) {
            discard_fragment();
        }
        return float4(in.color.rgb, 1);
    }
    return float4(in.color.rgb * alpha, alpha); // Premultiplied.
}
