#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// PCG hash based RNG.
static uint hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Gradient noise in -1...1, smooth (quintic) in each axis.
static float gradientNoise(float3 p) {
    float3 cell = floor(p);
    float3 f = p - cell;
    float3 u = f * f * f * (f * (f * 6 - 15) + 10);
    float result = 0;
    float weights[2][2][2];
    for (int z = 0; z < 2; z++) {
        for (int y = 0; y < 2; y++) {
            for (int x = 0; x < 2; x++) {
                int3 corner = int3(cell) + int3(x, y, z);
                uint h = hash(uint(corner.x) * 73856093u ^ uint(corner.y) * 19349663u ^ uint(corner.z) * 83492791u);
                // One of 12 cube-edge gradients.
                const float3 gradients[12] = {
                    float3(1, 1, 0), float3(-1, 1, 0), float3(1, -1, 0), float3(-1, -1, 0),
                    float3(1, 0, 1), float3(-1, 0, 1), float3(1, 0, -1), float3(-1, 0, -1),
                    float3(0, 1, 1), float3(0, -1, 1), float3(0, 1, -1), float3(0, -1, -1),
                };
                weights[z][y][x] = dot(gradients[h % 12], f - float3(x, y, z));
            }
        }
    }
    for (int z = 0; z < 2; z++) {
        float a = mix(weights[z][0][0], weights[z][0][1], u.x);
        float b = mix(weights[z][1][0], weights[z][1][1], u.x);
        result += (z == 0 ? 1 - u.z : u.z) * mix(a, b, u.y);
    }
    return result;
}

// Curl of a noise vector potential: a divergence-free flow, so particles swirl instead of bunching up.
static float3 curlNoise(float3 p) {
    const float e = 0.01;
    const float3 offsetY = float3(31.4, 17.2, 5.9);
    const float3 offsetZ = float3(-11.7, 43.1, 23.3);
    auto potential = [&](float3 q) {
        return float3(gradientNoise(q), gradientNoise(q + offsetY), gradientNoise(q + offsetZ));
    };
    float3 dx = potential(p + float3(e, 0, 0)) - potential(p - float3(e, 0, 0));
    float3 dy = potential(p + float3(0, e, 0)) - potential(p - float3(0, e, 0));
    float3 dz = potential(p + float3(0, 0, e)) - potential(p - float3(0, 0, e));
    return float3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2 * e);
}

// 1 inside half the radius, easing to 0 at the radius. A radius of 0 means unlimited range.
static float fieldFalloff(float distance, float radius) {
    return radius > 0 ? 1 - smoothstep(radius * 0.5, radius, distance) : 1;
}

static float3 fieldAcceleration(ForceFieldData field, float3 position, float3 velocity, float time) {
    int kind = int(field.kind.x);
    if (kind == 1) {
        return (field.a.xyz - velocity) * field.a.w;
    }
    if (kind == 2) {
        float3 offset = field.a.xyz - position;
        float distance = length(offset);
        return distance > 1e-4 ? offset / distance * field.a.w * fieldFalloff(distance, field.b.x) : float3(0);
    }
    if (kind == 3) {
        float3 axis = normalize(field.b.xyz);
        float3 offset = position - field.a.xyz;
        float3 radial = offset - axis * dot(offset, axis);
        float distance = length(radial);
        return distance > 1e-4 ? cross(axis, radial / distance) * field.a.w * fieldFalloff(distance, field.b.w) : float3(0);
    }
    if (kind == 4) {
        float3 sample = position * field.a.y + float3(0, 0, time * field.a.z);
        return curlNoise(sample) * field.a.x;
    }
    return float3(0);
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
    constant ForceFieldData *forceFields [[buffer(3)]],
    uint localID [[thread_position_in_grid]]
) {
    // Each dispatch covers one emitter's slice of the shared buffer.
    uint id = uniforms.random.z + localID;
    Particle p = particles[id];
    float dt = uniforms.lifetime.w;
    uint capacity = uniforms.random.y;

    if (uniforms.spawn.w != 0) {
        p.position.w = 0;
        p.velocity.w = 0;
    }

    // Particles spawn into a ring: this step owns `spawn.y` slots starting at the cursor. The oldest particles get
    // recycled first. Randomness comes from the spawn serial, not the slot, so results do not depend on thread order.
    uint offset = (localID + capacity - uniforms.spawn.x) % capacity;
    if (offset < uniforms.spawn.y) {
        Random rng { hash(hash(uniforms.spawn.z + offset) ^ uniforms.random.x) };
        float3 position = uniforms.emitterPosition.xyz + rng.inUnitSphere() * uniforms.emitterPosition.w;
        float3 velocity = uniforms.emitterVelocity.xyz + rng.inUnitSphere() * uniforms.emitterVelocity.w;
        float lifetime = mix(uniforms.lifetime.x, uniforms.lifetime.y, rng.next());
        // Spread births across the step so particles born in the same step do not move as one sheet.
        float birthAge = rng.next();
        dt *= birthAge;
        // New draws go after existing ones, so adding a property does not change earlier random streams.
        float angle = uniforms.rotation.x + (rng.next() * 2 - 1) * uniforms.rotation.y;
        float angularVelocity = uniforms.rotation.z + (rng.next() * 2 - 1) * uniforms.rotation.w;
        float initialFrame = max(0.0, uniforms.imageSequence.x + (rng.next() * 2 - 1) * uniforms.imageSequence.y);
        float frameRate = uniforms.imageSequence.z + (rng.next() * 2 - 1) * uniforms.imageSequence.w;
        float4 variation = uniforms.variation;
        float sizeScale = max(0.0, 1 + (rng.next() * 2 - 1) * variation.x);
        float restitutionOffset = (rng.next() * 2 - 1) * variation.y;
        float frictionOffset = (rng.next() * 2 - 1) * variation.z;
        float speedOffset = (rng.next() * 2 - 1) * variation.w;
        float speed = length(velocity);
        if (speed > 1e-6) {
            velocity *= max(0.0, speed + speedOffset) / speed;
        }
        float4 colorOffset = float4(rng.next(), rng.next(), rng.next(), rng.next()) * 2 - 1;
        // Emitter-local to simulation space. Particles born earlier in the step start further back along the
        // emitter's path, so fast-moving emitters leave continuous trails instead of clumps.
        position = (uniforms.emitterTransform * float4(position, 1)).xyz;
        position += (uniforms.previousEmitterOrigin.xyz - uniforms.emitterTransform[3].xyz) * birthAge;
        velocity = (uniforms.emitterTransform * float4(velocity, 0)).xyz + uniforms.inheritedVelocity.xyz;
        p.position = float4(position, 0);
        p.velocity = float4(velocity, lifetime);
        p.rotation = float4(angle, angularVelocity, initialFrame, frameRate);
        p.color = colorOffset * uniforms.colorVariation;
        p.properties = float4(sizeScale, restitutionOffset, frictionOffset, 0);
    }

    float lifetime = p.velocity.w;
    float age = p.position.w;
    if (lifetime <= 0 || age >= lifetime) {
        particles[id] = p;
        return;
    }
    age += dt;

    // Gravity, force fields, and colliders are in world space.
    float3 position = (uniforms.simulationToWorld * float4(p.position.xyz, 1)).xyz;
    float3 velocity = (uniforms.simulationToWorld * float4(p.velocity.xyz, 0)).xyz;
    velocity += uniforms.gravity.xyz * dt;
    uint fieldCount = uint(uniforms.fields.x);
    float3 acceleration = 0;
    for (uint i = 0; i < fieldCount; i++) {
        acceleration += fieldAcceleration(forceFields[i], position, velocity, uniforms.fields.y);
    }
    velocity += acceleration * dt;
    velocity *= max(0.0, 1.0 - uniforms.gravity.w * dt);
    position += velocity * dt;
    p.rotation.x += p.rotation.y * dt;

    float restitution = max(0.0, uniforms.collision.x + p.properties.y);
    float friction = saturate(uniforms.collision.y + p.properties.z);

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

    position = (uniforms.worldToSimulation * float4(position, 1)).xyz;
    velocity = (uniforms.worldToSimulation * float4(velocity, 0)).xyz;
    p.position = float4(position, age);
    p.velocity = float4(velocity, lifetime);
    particles[id] = p;
}

// Linear lookup into a PARTICLE_CURVE_SAMPLES-entry table covering normalized life 0...1.
template <typename T>
static T sampleCurve(constant T *curve, float t) {
    float x = saturate(t) * (PARTICLE_CURVE_SAMPLES - 1);
    uint index = min(uint(x), uint(PARTICLE_CURVE_SAMPLES - 2));
    return mix(curve[index], curve[index + 1], x - float(index));
}

static float3 rgbToHSV(float3 c) {
    float4 k = float4(0, -1.0 / 3.0, 2.0 / 3.0, -1);
    float4 p = c.g < c.b ? float4(c.bg, k.wz) : float4(c.gb, k.xy);
    float4 q = c.r < p.x ? float4(p.xyw, c.r) : float4(c.r, p.yzx);
    float d = q.x - min(q.w, q.y);
    return float3(abs(q.z + (q.w - q.y) / (6 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

static float3 hsvToRGB(float3 c) {
    float3 p = abs(fract(c.xxx + float3(1, 2.0 / 3.0, 1.0 / 3.0)) * 6 - 3);
    return c.z * mix(float3(1), saturate(p - 1), c.y);
}

// Shifts hue (wrapping), saturation, brightness, and alpha by the particle's offsets.
static float4 applyColorVariation(float4 color, float4 offset) {
    if (all(offset == 0)) {
        return color;
    }
    float3 hsv = rgbToHSV(color.rgb);
    hsv.x = fract(hsv.x + offset.x);
    hsv.y = saturate(hsv.y + offset.y);
    hsv.z = max(0.0, hsv.z + offset.z);
    return float4(hsvToRGB(hsv), saturate(color.a + offset.w));
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
    constant RenderUniforms &uniforms [[buffer(1)]],
    constant float4 *colorCurve [[buffer(2)]],
    constant float *sizeCurve [[buffer(3)]]
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
    float size = sampleCurve(sizeCurve, t) * p.properties.x;
    float2 corner = corners[vertexID];

    // The quad's right and up axes in world space.
    float3 right = uniforms.cameraRight.xyz;
    float3 up = uniforms.cameraUp.xyz;
    float stretch = 1;
    float3 center = (uniforms.model * float4(p.position.xyz, 1)).xyz;
    float3 toCamera = uniforms.cameraPosition.xyz - center;
    switch (uniforms.orientationMode.x) {
    case ParticleOrientationModeYAligned: {
        float3 side = cross(float3(0, 1, 0), toCamera);
        if (length_squared(side) > 1e-8) {
            right = normalize(side);
            up = float3(0, 1, 0);
        }
        break;
    }
    case ParticleOrientationModeVelocityAligned: {
        float3 velocity = (uniforms.model * float4(p.velocity.xyz, 0)).xyz;
        float speed = length(velocity);
        float3 side = cross(velocity, toCamera);
        // Moving straight at the camera, or not moving: fall back to a billboard.
        if (speed > 1e-4 && length_squared(side) > 1e-8) {
            up = velocity / speed;
            right = normalize(side);
            stretch = 1 + uniforms.orientation.w * speed;
        }
        break;
    }
    case ParticleOrientationModeFixed: {
        float3 normal = normalize(uniforms.orientation.xyz);
        float3 helper = abs(normal.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0);
        right = normalize(cross(helper, normal));
        up = cross(normal, right);
        break;
    }
    default:
        break;
    }

    // Rotate the quad, not the UVs, so textures spin with it.
    float s = sin(p.rotation.x);
    float c = cos(p.rotation.x);
    float2 stretched = float2(corner.x, corner.y * stretch);
    float2 offset = float2(c * stretched.x - s * stretched.y, s * stretched.x + c * stretched.y);
    float3 world = center + (right * offset.x + up * offset.y) * size;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = applyColorVariation(sampleCurve(colorCurve, t), p.color);
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
