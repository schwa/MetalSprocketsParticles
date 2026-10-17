#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// PCG hash based RNG.
static uint hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// A cube-edge gradient (one axis zero, the others ±1) chosen by hashing the lattice corner.
static float3 latticeGradient(int3 corner) {
    uint h = hash(uint(corner.x) * 73856093u ^ uint(corner.y) * 19349663u ^ uint(corner.z) * 83492791u);
    float3 gradient = float3((h & 1) ? 1 : -1, (h & 2) ? 1 : -1, (h & 4) ? 1 : -1);
    gradient[(h >> 3) % 3] = 0;
    return gradient;
}

// Gradient noise (quintic) and its analytic derivatives: x = value, yzw = d/dx, d/dy, d/dz.
// After Inigo Quilez, "Gradient Noise Derivatives". Corners: a 000, b 100, c 010, d 110, e 001, f 101, g 011, h 111.
static float4 gradientNoiseWithDerivatives(float3 p) {
    int3 cell = int3(floor(p));
    float3 f = p - floor(p);
    float3 u = f * f * f * (f * (f * 6 - 15) + 10);
    float3 du = 30 * f * f * (f * (f - 2) + 1);

    float3 ga = latticeGradient(cell + int3(0, 0, 0));
    float3 gb = latticeGradient(cell + int3(1, 0, 0));
    float3 gc = latticeGradient(cell + int3(0, 1, 0));
    float3 gd = latticeGradient(cell + int3(1, 1, 0));
    float3 ge = latticeGradient(cell + int3(0, 0, 1));
    float3 gf = latticeGradient(cell + int3(1, 0, 1));
    float3 gg = latticeGradient(cell + int3(0, 1, 1));
    float3 gh = latticeGradient(cell + int3(1, 1, 1));

    float va = dot(ga, f - float3(0, 0, 0));
    float vb = dot(gb, f - float3(1, 0, 0));
    float vc = dot(gc, f - float3(0, 1, 0));
    float vd = dot(gd, f - float3(1, 1, 0));
    float ve = dot(ge, f - float3(0, 0, 1));
    float vf = dot(gf, f - float3(1, 0, 1));
    float vg = dot(gg, f - float3(0, 1, 1));
    float vh = dot(gh, f - float3(1, 1, 1));

    float k0 = va;
    float k1 = vb - va;
    float k2 = vc - va;
    float k3 = ve - va;
    float k4 = va - vb - vc + vd;
    float k5 = va - vc - ve + vg;
    float k6 = va - vb - ve + vf;
    float k7 = -va + vb + vc - vd + ve - vf - vg + vh;

    float3 g0 = ga;
    float3 g1 = gb - ga;
    float3 g2 = gc - ga;
    float3 g3 = ge - ga;
    float3 g4 = ga - gb - gc + gd;
    float3 g5 = ga - gc - ge + gg;
    float3 g6 = ga - gb - ge + gf;
    float3 g7 = -ga + gb + gc - gd + ge - gf - gg + gh;

    float value = k0 + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
    float3 derivatives = g0 + g1 * u.x + g2 * u.y + g3 * u.z + g4 * u.x * u.y + g5 * u.y * u.z + g6 * u.z * u.x + g7 * u.x * u.y * u.z
        + du * float3(
            k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
            k2 + k5 * u.z + k4 * u.x + k7 * u.z * u.x,
            k3 + k6 * u.x + k5 * u.y + k7 * u.x * u.y);
    return float4(value, derivatives);
}

// Curl of a noise vector potential: a divergence-free flow, so particles swirl instead of bunching up. Analytic
// derivatives need three noise samples instead of eighteen for central differences.
static float3 curlNoise(float3 p) {
    const float3 offsetY = float3(31.4, 17.2, 5.9);
    const float3 offsetZ = float3(-11.7, 43.1, 23.3);
    float3 dx = gradientNoiseWithDerivatives(p).yzw;
    float3 dy = gradientNoiseWithDerivatives(p + offsetY).yzw;
    float3 dz = gradientNoiseWithDerivatives(p + offsetZ).yzw;
    // Potential = (noise x, noise y, noise z); curl = (dPz/dy - dPy/dz, dPx/dz - dPz/dx, dPy/dx - dPx/dy).
    return float3(dz.y - dy.z, dx.z - dz.x, dy.x - dx.y);
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

// Draw several values with next2/next3/next4, never float3(next(), next(), next()): C++ leaves argument evaluation
// order unspecified, so the compiler may reorder the draws whenever surrounding code changes.
struct Random {
    uint state;
    float next() { state = hash(state); return float(state) / 4294967295.0; }
    float2 next2() {
        float x = next();
        float y = next();
        return float2(x, y);
    }
    float3 next3() {
        float x = next();
        float y = next();
        float z = next();
        return float3(x, y, z);
    }
    float4 next4() {
        float x = next();
        float y = next();
        float z = next();
        float w = next();
        return float4(x, y, z, w);
    }
    float3 inUnitSphere() {
        for (int i = 0; i < 8; i++) {
            float3 p = next3() * 2.0 - 1.0;
            if (length_squared(p) <= 1.0) { return p; }
        }
        return float3(0);
    }
};

struct ShapeSample {
    float3 position; // Emitter space, relative to the shape center.
    float3 normal;   // Outward unit normal, or a random direction where the shape has none.
};

// A unit direction with azimuth around +Y limited to 0...sweep.
static float3 sweptDirection(thread Random &rng, float sweep) {
    float azimuth = rng.next() * sweep;
    float y = rng.next() * 2 - 1;
    float r = sqrt(max(0.0, 1 - y * y));
    return float3(r * cos(azimuth), y, r * sin(azimuth));
}

static ShapeSample sampleShape(
    thread Random &rng,
    constant SimulationUniforms &uniforms,
    constant EmitterMeshTriangle *triangles,
    constant float4 *vertices
) {
    float4 parameters = uniforms.shapeParameters;
    float sweep = parameters.w;
    bool surface = uniforms.shape.y != ParticleBirthLocationVolume;
    const float twoPi = 6.2831853;
    switch (uniforms.shape.x) {
    case ParticleEmitterShapeKindSphere: {
        float radius = parameters.x;
        if (!surface && sweep >= twoPi) {
            // Same draws as the original sphere emitter, so default results do not change.
            float3 offset = rng.inUnitSphere();
            float length = metal::length(offset);
            return { offset * radius, length > 1e-6 ? offset / length : sweptDirection(rng, twoPi) };
        }
        float3 direction = sweptDirection(rng, sweep);
        float distance = surface ? radius : radius * pow(rng.next(), 1.0 / 3.0);
        return { direction * distance, direction };
    }
    case ParticleEmitterShapeKindBox: {
        float3 halfSize = parameters.xyz * 0.5;
        float3 point = (rng.next3() * 2 - 1) * halfSize;
        if (!surface) {
            return { point, sweptDirection(rng, twoPi) };
        }
        // Pick a face pair by area, then a side, then project onto it.
        float3 areas = float3(halfSize.y * halfSize.z, halfSize.x * halfSize.z, halfSize.x * halfSize.y);
        float pick = rng.next() * (areas.x + areas.y + areas.z);
        int axis = pick < areas.x ? 0 : (pick < areas.x + areas.y ? 1 : 2);
        float side = rng.next() < 0.5 ? -1 : 1;
        float3 normal = 0;
        normal[axis] = side;
        point[axis] = halfSize[axis] * side;
        return { point, normal };
    }
    case ParticleEmitterShapeKindPlane: {
        float2 halfSize = parameters.xy * 0.5;
        float2 point = (rng.next2() * 2 - 1) * halfSize;
        return { float3(point.x, 0, point.y), float3(0, 1, 0) };
    }
    case ParticleEmitterShapeKindDisc: {
        float angle = rng.next() * sweep;
        float distance = surface ? parameters.x : parameters.x * sqrt(rng.next());
        return { float3(cos(angle), 0, sin(angle)) * distance, float3(0, 1, 0) };
    }
    case ParticleEmitterShapeKindCylinder: {
        float angle = rng.next() * sweep;
        float3 radial = float3(cos(angle), 0, sin(angle));
        float distance = surface ? parameters.x : parameters.x * sqrt(rng.next());
        float y = (rng.next() - 0.5) * parameters.y;
        return { radial * distance + float3(0, y, 0), radial };
    }
    case ParticleEmitterShapeKindCone: {
        // Base of radius parameters.x at y = 0, apex at y = parameters.y.
        float radius = parameters.x;
        float height = parameters.y;
        float angle = rng.next() * sweep;
        float3 radial = float3(cos(angle), 0, sin(angle));
        // Cross-section area falls off with height, so sample height with matching density.
        float fraction = surface ? 1 - sqrt(rng.next()) : 1 - pow(rng.next(), 1.0 / 3.0);
        float sliceRadius = radius * (1 - fraction);
        float distance = surface ? sliceRadius : sliceRadius * sqrt(rng.next());
        float3 normal = normalize(radial * height + float3(0, radius, 0));
        return { radial * distance + float3(0, fraction * height, 0), normal };
    }
    case ParticleEmitterShapeKindTorus: {
        float radius = parameters.x;
        float tube = parameters.y;
        float angle = rng.next() * sweep;
        // Rejection-sample the tube angle so points are uniform over the surface, not bunched on the inside.
        float tubeAngle = 0;
        for (int i = 0; i < 8; i++) {
            tubeAngle = rng.next() * twoPi;
            if (rng.next() * (radius + tube) <= radius + tube * cos(tubeAngle)) {
                break;
            }
        }
        float3 radial = float3(cos(angle), 0, sin(angle));
        float3 normal = radial * cos(tubeAngle) + float3(0, sin(tubeAngle), 0);
        float distance = surface ? tube : tube * sqrt(rng.next());
        return { radial * radius + normal * distance, normal };
    }
    case ParticleEmitterShapeKindMesh: {
        uint vertexCount = uniforms.meshCounts.y;
        if (uniforms.shape.y == ParticleBirthLocationVertices && vertexCount > 0) {
            uint index = min(uint(rng.next() * vertexCount), vertexCount - 1);
            return { vertices[index].xyz, sweptDirection(rng, twoPi) };
        }
        uint count = uniforms.meshCounts.x;
        if (count == 0) {
            return { float3(0), sweptDirection(rng, twoPi) };
        }
        // Binary search the cumulative areas. Volume is not supported for meshes and uses the surface.
        float target = rng.next();
        uint low = 0;
        uint high = count - 1;
        while (low < high) {
            uint middle = (low + high) / 2;
            if (triangles[middle].a.w < target) {
                low = middle + 1;
            } else {
                high = middle;
            }
        }
        EmitterMeshTriangle triangle = triangles[low];
        float u = sqrt(rng.next());
        float v = rng.next();
        float3 a = triangle.a.xyz;
        float3 b = triangle.b.xyz;
        float3 c = triangle.c.xyz;
        float3 point = a * (1 - u) + b * (u * (1 - v)) + c * (u * v);
        float3 normal = cross(b - a, c - a);
        float length = metal::length(normal);
        return { point, length > 0 ? normal / length : sweptDirection(rng, twoPi) };
    }
    default:
        return { float3(0), sweptDirection(rng, twoPi) };
    }
}

// Rotates `v` by unit quaternion `q` (xyz = imaginary, w = real).
static float3 rotate(float4 q, float3 v) {
    float3 t = 2 * cross(q.xyz, v);
    return v + q.w * t + cross(q.xyz, t);
}

// Response is computed relative to the collider, so moving colliders push and carry particles.
static void collide(thread float3 &position, thread float3 &velocity, ColliderData c, float3 normal, float penetration, float restitution, float friction, thread bool &hit) {
    hit = true;
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
    constant EmitterMeshTriangle *meshTriangles [[buffer(4)]],
    constant float4 *meshVertices [[buffer(5)]],
    uint localID [[thread_position_in_grid]]
) {
    // Each dispatch covers a window of one emitter's ring, starting at slot random.w and wrapping at its capacity.
    uint capacity = uniforms.random.y;
    uint slot = (uniforms.random.w + localID) % capacity;
    uint id = uniforms.random.z + slot;
    Particle p = particles[id];
    float dt = uniforms.lifetime.w;

    if (uniforms.spawn.w != 0) {
        p.position.w = 0;
        p.velocity.w = 0;
    }

    // Particles spawn into a ring: this step owns `spawn.y` slots starting at the cursor. The oldest particles get
    // recycled first. Randomness comes from the spawn serial, not the slot, so results do not depend on thread order.
    uint offset = (slot + capacity - uniforms.spawn.x) % capacity;
    if (offset < uniforms.spawn.y) {
        Random rng { hash(hash(uniforms.spawn.z + offset) ^ uniforms.random.x) };
        // The default full sphere volume keeps the original expression exactly: rewriting it changes rounding, and
        // tiny differences grow chaotically through collisions.
        bool defaultSphere = uniforms.shape.x == ParticleEmitterShapeKindSphere
            && uniforms.shape.y == ParticleBirthLocationVolume
            && uniforms.shapeParameters.w >= 6.2831853;
        ShapeSample sample;
        float3 position;
        if (defaultSphere) {
            float3 offset = rng.inUnitSphere();
            position = uniforms.emitterPosition.xyz + offset * uniforms.shapeParameters.x;
            float offsetLength = length(offset);
            sample.normal = offsetLength > 1e-6 ? offset / offsetLength : float3(0, 1, 0);
        } else {
            sample = sampleShape(rng, uniforms, meshTriangles, meshVertices);
            position = uniforms.emitterPosition.xyz + sample.position;
        }
        float3 baseVelocity = uniforms.shape.z == ParticleBirthDirectionNormal
            ? sample.normal * length(uniforms.emitterVelocity.xyz)
            : uniforms.emitterVelocity.xyz;
        float3 velocity = baseVelocity + rng.inUnitSphere() * uniforms.emitterVelocity.w;
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
        float4 colorOffset = rng.next4() * 2 - 1;
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

    bool hit = false;
    uint colliderCount = uint(uniforms.collision.z);
    for (uint i = 0; i < colliderCount; i++) {
        ColliderData c = colliders[i];
        int kind = int(c.kind.x);
        if (kind == 1) {
            float distance = dot(position, c.a.xyz) - c.a.w;
            if (distance < 0) { collide(position, velocity, c, c.a.xyz, -distance, restitution, friction, hit); }
        } else if (kind == 2) {
            float3 offset = position - c.a.xyz;
            float distance = length(offset);
            if (distance < c.a.w && distance > 0) {
                collide(position, velocity, c, offset / distance, c.a.w - distance, restitution, friction, hit);
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
                collide(position, velocity, c, rotate(c.rotation, normal), penetration, restitution, friction, hit);
            }
        } else if (kind == 4) {
            float3 start = c.a.xyz;
            float3 axis = c.b.xyz - start;
            float lengthSquared = length_squared(axis);
            float t = lengthSquared > 0 ? saturate(dot(position - start, axis) / lengthSquared) : 0;
            float3 offset = position - (start + axis * t);
            float distance = length(offset);
            if (distance < c.a.w && distance > 0) {
                collide(position, velocity, c, offset / distance, c.a.w - distance, restitution, friction, hit);
            }
        }
    }

    if (hit && uniforms.collision.w != 0) {
        age = lifetime;
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
