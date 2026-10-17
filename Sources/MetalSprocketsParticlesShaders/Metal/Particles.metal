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

// Rotates `v` by unit quaternion `q` (xyz = imaginary, w = real).
static float3 rotate(float4 q, float3 v) {
    float3 t = 2 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

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
        float initialFrame = max(0.0, uniforms.imageSequence.x + (rng.next() * 2 - 1) * uniforms.imageSequence.y);
        float frameRate = uniforms.imageSequence.z + (rng.next() * 2 - 1) * uniforms.imageSequence.w;
        p.rotation = float4(angle, angularVelocity, initialFrame, frameRate);
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
            float4 inverse = float4(-c.rotation.xyz, c.rotation.w);
            float3 local = rotate(inverse, position - c.a.xyz);
            float3 depth = c.b.xyz - abs(local);
            if (all(depth > 0)) {
                // Push out through the nearest face.
                float3 normal = float3(0);
                float penetration;
                if (depth.x < depth.y && depth.x < depth.z) { normal.x = sign(local.x); penetration = depth.x; }
                else if (depth.y < depth.z) { normal.y = sign(local.y); penetration = depth.y; }
                else { normal.z = sign(local.z); penetration = depth.z; }
                collide(position, velocity, c, rotate(c.rotation, normal), penetration, restitution, friction);
            }
        } else if (kind == 4) {
            float3 start = c.a.xyz;
            float3 axis = c.b.xyz - start;
            float lengthSquared = length_squared(axis);
            float t = lengthSquared > 0 ? saturate(dot(position - start, axis) / lengthSquared) : 0;
            float3 offset = position - (start + axis * t);
            float distance = length(offset);
            if (distance < c.a.w && distance > 0) {
                collide(position, velocity, c, offset / distance, c.a.w - distance, restitution, friction);
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
    float2 uv;       // Quad corner space, -1...1. Drives the procedural dot.
    float2 texcoord; // Sprite sheet cell coordinates.
};

// Frame index for a particle `age` seconds old.
static uint sequenceFrame(float initialFrame, float frameRate, float age, uint frameCount, uint mode) {
    if (frameCount <= 1) {
        return 0;
    }
    int frame = int(floor(initialFrame + frameRate * age));
    int count = int(frameCount);
    switch (mode) {
    case ParticleImageSequenceModeClamp:
        return uint(clamp(frame, 0, count - 1));
    case ParticleImageSequenceModeAutoReverse: {
        int period = 2 * (count - 1);
        int phase = ((frame % period) + period) % period;
        return uint(phase < count ? phase : period - phase);
    }
    default:
        return uint(((frame % count) + count) % count);
    }
}

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
        out.texcoord = 0;
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
    uint columns = max(uniforms.options.z, 1u);
    uint rows = max(uniforms.options.w, 1u);
    uint frame = sequenceFrame(p.rotation.z, p.rotation.w, age, uniforms.imageSequence.x, uniforms.imageSequence.y);
    float2 cell = float2(frame % columns, frame / columns);
    // Texture v runs down, quad corner y runs up.
    float2 cellUV = float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);
    out.texcoord = (cell + cellUV) / float2(columns, rows);
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

fragment float4 particleFragment(
    VertexOut in [[stage_in]],
    constant RenderUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sprite [[texture(0)]],
    sampler spriteSampler [[sampler(0)]]
) {
    // Premultiplied coverage and color before tinting by the particle color.
    float4 base;
    if (uniforms.options.y != 0) {
        base = sprite.sample(spriteSampler, in.texcoord);
    } else {
        float falloff = saturate(1.0 - length(in.uv));
        float coverage = falloff * falloff;
        base = float4(coverage, coverage, coverage, coverage);
    }
    float alpha = base.a * in.color.a;
    if (uniforms.options.x == ParticleBlendModeOpaque) {
        if (alpha < 0.5) {
            discard_fragment();
        }
        float3 color = base.a > 0 ? base.rgb / base.a : base.rgb;
        return float4(color * in.color.rgb, 1);
    }
    return float4(base.rgb * in.color.rgb * in.color.a, alpha);
}
