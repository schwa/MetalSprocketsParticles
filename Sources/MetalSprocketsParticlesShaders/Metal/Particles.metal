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
    switch (field.kind) {
    case ParticleForceFieldKindWind:
        return (field.velocity - velocity) * field.strength;
    case ParticleForceFieldKindAttractor: {
        float3 offset = field.center - position;
        float distance = length(offset);
        return distance > 1e-4 ? offset / distance * field.strength * fieldFalloff(distance, field.radius) : float3(0);
    }
    case ParticleForceFieldKindVortex: {
        float3 axis = normalize(field.axis);
        float3 offset = position - field.center;
        float3 radial = offset - axis * dot(offset, axis);
        float distance = length(radial);
        return distance > 1e-4 ? cross(axis, radial / distance) * field.strength * fieldFalloff(distance, field.radius) : float3(0);
    }
    case ParticleForceFieldKindTurbulence: {
        float3 sample = position * field.scale + float3(0, 0, time * field.speed);
        return curlNoise(sample) * field.strength;
    }
    default:
        return float3(0);
    }
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

// An emitter mesh: rest-pose triangles with cumulative areas, rest vertices, triangle indices, and optional deformed
// positions that replace the rest ones.
struct EmitterMeshInput {
    constant EmitterMeshTriangle *triangles;
    constant float4 *vertices;
    constant uint *indices;
    const device uchar *deformedPositions;
};

static float3 deformedPosition(EmitterMeshInput mesh, ParticleShapeData shape, uint vertexIndex) {
    return float3(*(const device packed_float3 *)(mesh.deformedPositions + shape.deformedPositionOffset + shape.deformedPositionStride * vertexIndex));
}

static ShapeSample sampleShape(
    thread Random &rng,
    constant SimulationUniforms &uniforms,
    EmitterMeshInput mesh
) {
    constant EmitterMeshTriangle *triangles = mesh.triangles;
    constant float4 *vertices = mesh.vertices;
    ParticleShapeData shape = uniforms.shape;
    float sweep = shape.sweep;
    bool surface = shape.birthLocation != ParticleBirthLocationVolume;
    const float twoPi = 6.2831853;
    switch (shape.kind) {
    case ParticleEmitterShapeKindSphere: {
        float radius = shape.radius;
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
        float3 halfSize = shape.size * 0.5;
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
        float2 halfSize = shape.size.xz * 0.5;
        float2 point = (rng.next2() * 2 - 1) * halfSize;
        return { float3(point.x, 0, point.y), float3(0, 1, 0) };
    }
    case ParticleEmitterShapeKindDisc: {
        float angle = rng.next() * sweep;
        float distance = surface ? shape.radius : shape.radius * sqrt(rng.next());
        return { float3(cos(angle), 0, sin(angle)) * distance, float3(0, 1, 0) };
    }
    case ParticleEmitterShapeKindCylinder: {
        float angle = rng.next() * sweep;
        float3 radial = float3(cos(angle), 0, sin(angle));
        float distance = surface ? shape.radius : shape.radius * sqrt(rng.next());
        float y = (rng.next() - 0.5) * shape.height;
        return { radial * distance + float3(0, y, 0), radial };
    }
    case ParticleEmitterShapeKindCone: {
        // Base at y = 0, apex at y = height.
        float radius = shape.radius;
        float height = shape.height;
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
        float radius = shape.radius;
        float tube = shape.tubeRadius;
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
        uint vertexCount = shape.meshVertexCount;
        if (shape.birthLocation == ParticleBirthLocationVertices && vertexCount > 0) {
            uint index = min(uint(rng.next() * vertexCount), vertexCount - 1);
            float3 position = shape.deformedPositionStride != 0 ? deformedPosition(mesh, shape, index) : vertices[index].xyz;
            return { position, sweptDirection(rng, twoPi) };
        }
        uint count = shape.meshTriangleCount;
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
        if (shape.deformedPositionStride != 0) {
            // Chosen by rest-pose area, placed on the deformed triangle.
            a = deformedPosition(mesh, shape, mesh.indices[low * 3]);
            b = deformedPosition(mesh, shape, mesh.indices[low * 3 + 1]);
            c = deformedPosition(mesh, shape, mesh.indices[low * 3 + 2]);
        }
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
    // The contact point's velocity: rotating colliders fling particles. Exactly c.velocity when not rotating.
    float3 colliderVelocity = c.velocity + cross(c.angularVelocity, position - c.pivot);
    float3 relative = velocity - colliderVelocity;
    float vn = dot(relative, normal);
    if (vn < 0) {
        float3 normalVelocity = normal * vn;
        float3 tangentVelocity = relative - normalVelocity;
        velocity = colliderVelocity + tangentVelocity * (1.0 - friction) - normalVelocity * restitution;
    }
}

// Swept tests for a particle that ended a step outside a collider but crossed it during the step (fast particles, thin
// or fast colliders). `start` is the particle's start in the collider's current frame. On a hit, `t` is the fraction of
// the step at entry and `normal` the outward normal there. Planes are half-spaces and never need this.
static bool sweepSphere(float3 start, float3 end, float3 center, float radius, thread float &t, thread float3 &normal) {
    float3 d = end - start;
    float3 m = start - center;
    float a = dot(d, d);
    float b = dot(m, d);
    float c = dot(m, m) - radius * radius;
    if (a < 1e-12 || c <= 0 || b >= 0) {
        return false;
    }
    float discriminant = b * b - a * c;
    if (discriminant < 0) {
        return false;
    }
    t = (-b - sqrt(discriminant)) / a;
    if (t < 0 || t > 1) {
        return false;
    }
    normal = normalize(m + d * t);
    return true;
}

static bool sweepBox(float3 start, float3 end, ColliderData c, thread float &t, thread float3 &normal) {
    float4 inverse = float4(-c.rotation.xyz, c.rotation.w);
    float3 s = rotate(inverse, start - c.center);
    float3 d = rotate(inverse, end - c.center) - s;
    float enter = 0;
    float exit = 1;
    int axis = -1;
    for (int i = 0; i < 3; i++) {
        if (abs(d[i]) < 1e-9) {
            if (abs(s[i]) > c.halfExtents[i]) {
                return false;
            }
            continue;
        }
        float t0 = (-c.halfExtents[i] - s[i]) / d[i];
        float t1 = (c.halfExtents[i] - s[i]) / d[i];
        if (t0 > t1) {
            float swap = t0;
            t0 = t1;
            t1 = swap;
        }
        if (t0 > enter) {
            enter = t0;
            axis = i;
        }
        exit = min(exit, t1);
        if (enter > exit) {
            return false;
        }
    }
    if (axis < 0) {
        return false; // Started inside: the penetration test handles it.
    }
    t = enter;
    float3 local = float3(0);
    local[axis] = d[axis] > 0 ? -1 : 1;
    normal = rotate(c.rotation, local);
    return true;
}

// Approximate: the closest approach between the particle's path and the capsule's axis.
static bool sweepCapsule(float3 start, float3 end, ColliderData c, thread float &t, thread float3 &normal) {
    float3 d1 = end - start;
    float3 d2 = c.end - c.center;
    float3 r = start - c.center;
    float a = dot(d1, d1);
    float e = dot(d2, d2);
    float f = dot(d2, r);
    if (a < 1e-12) {
        return false;
    }
    float s;
    float u;
    float cc = dot(d1, r);
    if (e < 1e-12) {
        s = saturate(-cc / a);
        u = 0;
    } else {
        float b = dot(d1, d2);
        float denominator = a * e - b * b;
        s = denominator > 1e-12 ? saturate((b * f - cc * e) / denominator) : 0;
        u = (b * s + f) / e;
        if (u < 0) {
            u = 0;
            s = saturate(-cc / a);
        } else if (u > 1) {
            u = 1;
            s = saturate((b - cc) / a);
        }
    }
    float3 onPath = start + d1 * s;
    float3 onAxis = c.center + d2 * u;
    float3 offset = onPath - onAxis;
    float distance = length(offset);
    if (distance >= c.radius) {
        return false;
    }
    // Back up to where the path first came within the radius, approximately.
    float back = (c.radius - distance) / max(length(d1), 1e-6);
    t = max(0.0, s - back);
    normal = distance > 1e-6 ? offset / distance : -normalize(d1);
    return true;
}

// A newborn particle from an emitter's settings. `origin` is added to its position and `extraVelocity` to its velocity,
// both in the emitter's simulation space; sub-emitters use them to start children at their parent. `birthAge` returns
// the fraction of the step the particle lives through.
static Particle spawnParticle(
    thread Random &rng,
    constant SimulationUniforms &uniforms,
    EmitterMeshInput mesh,
    float3 origin,
    float3 extraVelocity,
    thread float &birthAge
) {
    Particle p;
    {
        // The default full sphere volume keeps the original expression exactly: rewriting it changes rounding, and
        // tiny differences grow chaotically through collisions.
        bool defaultSphere = uniforms.shape.kind == ParticleEmitterShapeKindSphere
            && uniforms.shape.birthLocation == ParticleBirthLocationVolume
            && uniforms.shape.sweep >= 6.2831853;
        ShapeSample sample;
        float3 position;
        if (defaultSphere) {
            float3 offset = rng.inUnitSphere();
            position = uniforms.shape.center + offset * uniforms.shape.radius;
            float offsetLength = length(offset);
            sample.normal = offsetLength > 1e-6 ? offset / offsetLength : float3(0, 1, 0);
        } else {
            sample = sampleShape(rng, uniforms, mesh);
            position = uniforms.shape.center + sample.position;
        }
        float baseSpeed = length(uniforms.velocity);
        float3 baseVelocity = uniforms.velocity;
        if (uniforms.shape.birthDirection == ParticleBirthDirectionNormal) {
            baseVelocity = sample.normal * baseSpeed;
        } else if (uniforms.shape.birthDirection == ParticleBirthDirectionTangent) {
            // Around +Y through the shape center. On the axis itself there is no tangent; use the normal.
            float3 around = cross(float3(0, 1, 0), position - uniforms.shape.center);
            float aroundLength = length(around);
            baseVelocity = (aroundLength > 1e-6 ? around / aroundLength : sample.normal) * baseSpeed;
        }
        float3 velocity = baseVelocity + rng.inUnitSphere() * uniforms.velocitySpread;
        float lifetime = mix(uniforms.lifetimeMinimum, uniforms.lifetimeMaximum, rng.next());
        // Spread births across the step so particles born in the same step do not move as one sheet.
        birthAge = rng.next();
        // New draws go after existing ones, so adding a property does not change earlier random streams.
        ParticleVariationData variation = uniforms.variation;
        float angle = uniforms.angle + (rng.next() * 2 - 1) * variation.angle;
        float angularVelocity = uniforms.angularSpeed + (rng.next() * 2 - 1) * variation.angularSpeed;
        float initialFrame = max(0.0, uniforms.initialFrame + (rng.next() * 2 - 1) * variation.initialFrame);
        float frameRate = uniforms.frameRate + (rng.next() * 2 - 1) * variation.frameRate;
        float sizeScale = max(0.0, 1 + (rng.next() * 2 - 1) * variation.size);
        float restitutionOffset = (rng.next() * 2 - 1) * variation.restitution;
        float frictionOffset = (rng.next() * 2 - 1) * variation.friction;
        float speedOffset = (rng.next() * 2 - 1) * variation.speed;
        float speed = length(velocity);
        if (speed > 1e-6) {
            velocity *= max(0.0, speed + speedOffset) / speed;
        }
        float4 colorOffset = rng.next4() * 2 - 1;
        // Emitter-local to simulation space. Particles born earlier in the step start further back along the
        // emitter's path, so fast-moving emitters leave continuous trails instead of clumps.
        if (uniforms.spinAngle != 0) {
            // A rotating emitter: sweep this birth's offset and velocity back along the step's rotation too, so fast
            // spins leave a continuous arc instead of one clump per frame.
            float3 origin = uniforms.emitterTransform[3].xyz;
            float halfAngle = -birthAge * uniforms.spinAngle * 0.5;
            float4 back = float4(uniforms.spinAxis * sin(halfAngle), cos(halfAngle));
            float3 offset = rotate(back, (uniforms.emitterTransform * float4(position, 0)).xyz);
            position = origin + offset + (uniforms.previousEmitterOrigin - origin) * birthAge;
            velocity = rotate(back, (uniforms.emitterTransform * float4(velocity, 0)).xyz) + uniforms.inheritedVelocity
                + cross(uniforms.inheritedAngularVelocity, offset);
        } else {
            // Unchanged expressions for emitters that do not rotate, so their results stay bit-identical.
            position = (uniforms.emitterTransform * float4(position, 1)).xyz;
            position += (uniforms.previousEmitterOrigin - uniforms.emitterTransform[3].xyz) * birthAge;
            velocity = (uniforms.emitterTransform * float4(velocity, 0)).xyz + uniforms.inheritedVelocity;
        }
        p.position = float4(position + origin, 0);
        p.velocity = float4(velocity + extraVelocity, lifetime);
        p.rotation = float4(angle, angularVelocity, initialFrame, frameRate);
        p.color = colorOffset * variation.color;
        p.properties = float4(sizeScale, restitutionOffset, frictionOffset, 0);
    }
    return p;
}

// The user-function ABI, mirrored by ParticleFunction.prelude in Swift. Plain Metal types only, so user source needs no
// project headers and Particle's packing can change freely.
struct ParticleState {
    float3 position;
    float3 velocity;
    float age;
    float lifetime;
    uint id;
};
using ParticleUpdateFunction = void(thread ParticleState &, float deltaTime, float time, constant float4 *parameters);

// Stand-ins for missing user functions, one per table: linking one function twice into a pipeline is an error.
[[visible]] void particleNoUpdate(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoSpawn(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoCollision(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoDeath(thread ParticleState &, float, float, constant float4 *) {}

kernel void updateParticles(
    device Particle *particles [[buffer(0)]],
    constant SimulationUniforms &uniforms [[buffer(1)]],
    constant ColliderData *colliders [[buffer(2)]],
    constant ForceFieldData *forceFields [[buffer(3)]],
    constant EmitterMeshTriangle *meshTriangles [[buffer(4)]],
    constant float4 *meshVertices [[buffer(5)]],
    constant uint *meshIndices [[buffer(10)]],
    const device uchar *meshDeformedPositions [[buffer(11)]],
    device atomic_uint *aliveCounters [[buffer(12)]],
    constant SubEmitterData *subEmitters [[buffer(6)]],
    constant SimulationUniforms *subEmitterUniforms [[buffer(7)]],
    device atomic_uint *triggerCounters [[buffer(8)]],
    constant TriggerVolumeData *triggerVolumes [[buffer(9)]],
    visible_function_table<ParticleUpdateFunction> updateFunction [[buffer(13)]],
    constant float4 *updateParameters [[buffer(14)]],
    visible_function_table<ParticleUpdateFunction> spawnFunction [[buffer(15)]],
    constant float4 *spawnParameters [[buffer(16)]],
    visible_function_table<ParticleUpdateFunction> collisionFunction [[buffer(17)]],
    constant float4 *collisionParameters [[buffer(18)]],
    visible_function_table<ParticleUpdateFunction> deathFunction [[buffer(19)]],
    constant float4 *deathParameters [[buffer(20)]],
    uint localID [[thread_position_in_grid]]
) {
    EmitterMeshInput mesh { meshTriangles, meshVertices, meshIndices, meshDeformedPositions };
    // Each dispatch covers a window of one emitter's ring, starting at spawn.firstSlot and wrapping at its capacity.
    ParticleSpawnData spawn = uniforms.spawn;
    uint capacity = spawn.capacity;
    uint slot = (spawn.firstSlot + localID) % capacity;
    uint id = spawn.sliceStart + slot;
    Particle p = particles[id];
    float dt = uniforms.deltaTime;

    if (spawn.kill != 0) {
        p.position.w = 0;
        p.velocity.w = 0;
    }

    // Particles spawn into a ring: this step owns `spawn.count` slots starting at the cursor. The oldest particles get
    // recycled first. Randomness comes from the spawn serial, not the slot, so results do not depend on thread order.
    uint offset = (slot + capacity - spawn.cursor) % capacity;
    bool born = offset < spawn.count;
    if (born) {
        Random rng { hash(hash(spawn.serial + offset) ^ spawn.seed) };
        float birthAge;
        p = spawnParticle(rng, uniforms, mesh, float3(0), float3(0), birthAge);
        dt *= birthAge;
        if (uniforms.hasSpawnFunction != 0) {
            // The user sees world space, like the update function; deltaTime is 0 at birth.
            ParticleState state {
                (uniforms.simulationToWorld * float4(p.position.xyz, 1)).xyz,
                (uniforms.simulationToWorld * float4(p.velocity.xyz, 0)).xyz,
                p.position.w, p.velocity.w, id
            };
            spawnFunction[0](state, 0, uniforms.time, spawnParameters);
            p.position.xyz = (uniforms.worldToSimulation * float4(state.position, 1)).xyz;
            p.velocity.xyz = (uniforms.worldToSimulation * float4(state.velocity, 0)).xyz;
            p.velocity.w = max(state.lifetime, 1e-4);
        }
    }

    float lifetime = p.velocity.w;
    float age = p.position.w;
    if (lifetime <= 0 || age >= lifetime) {
        particles[id] = p;
        return;
    }
    float previousAge = age;
    age += dt;

    // Gravity, force fields, and colliders are in world space.
    float3 position = (uniforms.simulationToWorld * float4(p.position.xyz, 1)).xyz;
    float3 velocity = (uniforms.simulationToWorld * float4(p.velocity.xyz, 0)).xyz;
    float3 startPosition = position;
    velocity += uniforms.gravity * dt;
    float3 acceleration = 0;
    for (uint i = 0; i < uniforms.forceFieldCount; i++) {
        acceleration += fieldAcceleration(forceFields[i], position, velocity, uniforms.time);
    }
    velocity += acceleration * dt;
    velocity *= max(0.0, 1.0 - uniforms.drag * dt);
    position += velocity * dt;
    if (uniforms.hasUpdateFunction != 0) {
        ParticleState state { position, velocity, age, lifetime, id };
        updateFunction[0](state, dt, uniforms.time, updateParameters);
        position = state.position;
        velocity = state.velocity;
    }
    p.rotation.x += p.rotation.y * dt;

    float restitution = max(0.0, uniforms.restitution + p.properties.y);
    float friction = saturate(uniforms.friction + p.properties.z);

    bool hit = false;
    for (uint i = 0; i < uniforms.colliderCount; i++) {
        // Hits on earlier colliders this step do not count toward this one.
        bool hitBefore = hit;
        hit = false;
        ColliderData c = colliders[i];
        if (c.kind == ParticleColliderKindPlane) {
            float distance = dot(position, c.normal) - c.distance;
            if (distance < 0) { collide(position, velocity, c, c.normal, -distance, restitution, friction, hit); }
        } else if (c.kind == ParticleColliderKindSphere) {
            float3 offset = position - c.center;
            float distance = length(offset);
            if (distance < c.radius && distance > 0) {
                collide(position, velocity, c, offset / distance, c.radius - distance, restitution, friction, hit);
            }
        } else if (c.kind == ParticleColliderKindBox) {
            float4 inverse = float4(-c.rotation.xyz, c.rotation.w);
            float3 local = rotate(inverse, position - c.center);
            float3 depth = c.halfExtents - abs(local);
            if (all(depth > 0)) {
                // Push out through the nearest face.
                float3 normal = float3(0);
                float penetration;
                if (depth.x < depth.y && depth.x < depth.z) { normal.x = sign(local.x); penetration = depth.x; }
                else if (depth.y < depth.z) { normal.y = sign(local.y); penetration = depth.y; }
                else { normal.z = sign(local.z); penetration = depth.z; }
                collide(position, velocity, c, rotate(c.rotation, normal), penetration, restitution, friction, hit);
            }
        } else if (c.kind == ParticleColliderKindCapsule) {
            float3 start = c.center;
            float3 axis = c.end - start;
            float lengthSquared = length_squared(axis);
            float t = lengthSquared > 0 ? saturate(dot(position - start, axis) / lengthSquared) : 0;
            float3 offset = position - (start + axis * t);
            float distance = length(offset);
            if (distance < c.radius && distance > 0) {
                collide(position, velocity, c, offset / distance, c.radius - distance, restitution, friction, hit);
            }
        }
        if (!hit && c.kind != ParticleColliderKindPlane) {
            // Crossed during the step? Test in the collider's current frame: where the particle started, relative to
            // where the collider is now (the collider moved by velocity * dt, so the start is shifted the same way).
            float3 start = startPosition + c.velocity * dt;
            float t;
            float3 normal;
            bool crossed = c.kind == ParticleColliderKindSphere ? sweepSphere(start, position, c.center, c.radius, t, normal)
                : c.kind == ParticleColliderKindBox ? sweepBox(start, position, c, t, normal)
                : sweepCapsule(start, position, c, t, normal);
            if (crossed) {
                position = start + (position - start) * t + normal * 1e-4;
                collide(position, velocity, c, normal, 0, restitution, friction, hit);
            }
        }
        if (hit && uniforms.countsColliderHits != 0 && c.triggerIndex < PARTICLE_TRIGGER_MAX_COLLIDERS) {
            atomic_fetch_add_explicit(&triggerCounters[c.triggerIndex], 1u, memory_order_relaxed);
        }
        hit = hit || hitBefore;
    }

    // Trigger volumes count particles that were outside at the start of the step and inside at the end.
    uint volumeCount = min(uniforms.triggerVolumeCount, uint(PARTICLE_TRIGGER_MAX_VOLUMES));
    for (uint i = 0; i < volumeCount; i++) {
        TriggerVolumeData volume = triggerVolumes[i];
        if (volume.contains(position) && !volume.contains(startPosition)) {
            atomic_fetch_add_explicit(&triggerCounters[PARTICLE_TRIGGER_MAX_COLLIDERS + i], 1u, memory_order_relaxed);
        }
    }

    if (hit && uniforms.diesOnCollision != 0) {
        age = lifetime;
    }
    // Event functions may also change age and lifetime: setting age to lifetime kills the particle, and a death
    // function that raises lifetime keeps it alive. Collision runs first, so it can kill.
    if (hit && uniforms.hasCollisionFunction != 0) {
        ParticleState state { position, velocity, age, lifetime, id };
        collisionFunction[0](state, dt, uniforms.time, collisionParameters);
        position = state.position;
        velocity = state.velocity;
        age = state.age;
        lifetime = state.lifetime;
    }
    if (age >= lifetime && uniforms.hasDeathFunction != 0) {
        ParticleState state { position, velocity, age, lifetime, id };
        deathFunction[0](state, dt, uniforms.time, deathParameters);
        position = state.position;
        velocity = state.velocity;
        age = state.age;
        lifetime = state.lifetime;
    }

    // Sub-emitters: on an event, write children into the slots this particle owns in each child slice. Children live in
    // world space, so they start at this particle's world position.
    for (uint i = 0; i < uniforms.subEmitterCount; i++) {
        SubEmitterData sub = subEmitters[i];
        uint childrenPerEvent = sub.countPerEvent;
        float interval = sub.interval;
        uint first = 0;
        uint count = 0;
        switch (sub.occasion) {
        case ParticleSpawnOccasionBirth:
            count = born ? childrenPerEvent : 0;
            break;
        case ParticleSpawnOccasionDeath:
            count = age >= lifetime ? childrenPerEvent : 0;
            break;
        case ParticleSpawnOccasionCollision:
            count = hit ? childrenPerEvent : 0;
            break;
        case ParticleSpawnOccasionEnterVolume:
            count = sub.volume.contains(position) && !sub.volume.contains(startPosition) ? childrenPerEvent : 0;
            break;
        case ParticleSpawnOccasionAge:
            count = (born ? interval <= age : previousAge < interval && interval <= age) ? childrenPerEvent : 0;
            break;
        case ParticleSpawnOccasionWhileAlive: {
            // One child each time the age crosses a multiple of the interval, into a ring of the owned slots.
            float tick = floor(age / max(interval, 1e-4));
            if (born || tick != floor(previousAge / max(interval, 1e-4))) {
                first = uint(tick) % max(childrenPerEvent, 1u);
                count = 1;
            }
            break;
        }
        default:
            break;
        }
        for (uint k = 0; k < count; k++) {
            uint childSlot = slot * childrenPerEvent + (first + k) % childrenPerEvent;
            // Keyed by parent slot, child slot, and parent age, so results do not depend on thread order.
            Random childRandom { hash(hash(childSlot ^ subEmitterUniforms[i].spawn.seed) ^ as_type<uint>(age)) };
            float childBirthAge;
            Particle child = spawnParticle(
                childRandom, subEmitterUniforms[i], mesh, position, velocity * sub.velocityFactor, childBirthAge);
            if (sub.continuesParentLife != 0) {
                child.position.w = age;
                child.velocity.w = lifetime;
            }
            particles[sub.childSliceStart + childSlot] = child;
        }
        // A transition: the parent turns into its children. On-death sub-emitters listed after this one fire too.
        if (count > 0 && sub.replacesParent != 0) {
            age = lifetime;
        }
    }

    position = (uniforms.worldToSimulation * float4(position, 1)).xyz;
    velocity = (uniforms.worldToSimulation * float4(velocity, 0)).xyz;
    p.position = float4(position, age);
    p.velocity = float4(velocity, lifetime);
    particles[id] = p;

    // Statistics: one atomic per SIMD group, not per particle. Particles that were already dead returned earlier.
    if (uniforms.countsAlive != 0) {
        uint alive = simd_sum(age < lifetime ? 1u : 0u);
        if (simd_is_first()) {
            atomic_fetch_add_explicit(&aliveCounters[uniforms.aliveCounterSlot], alive, memory_order_relaxed);
        }
    }
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
    float viewDepth; // Distance in front of the camera, for soft particles.
};

// Diffuse light at a quad corner. The quad is shaded like a small sphere: the normal leans from the camera direction
// toward the corner, so lit particles get a soft gradient instead of a flat tint.
static float3 particleLight(constant RenderUniforms &uniforms, constant ParticleLightData *lights, float3 center, float3 cornerDirection) {
    float3 toCamera = normalize(uniforms.cameraPosition - center);
    float3 normal = normalize(cornerDirection + toCamera);
    float3 light = uniforms.ambientLight;
    for (uint i = 0; i < min(uniforms.lightCount, uint(PARTICLE_MAX_LIGHTS)); i++) {
        ParticleLightData source = lights[i];
        float3 toLight;
        float attenuation = 1;
        if (source.kind == ParticleLightKindPoint) {
            float3 offset = source.position - center;
            float distance = length(offset);
            toLight = distance > 1e-5 ? offset / distance : normal;
            if (source.range > 0) {
                float falloff = saturate(1 - distance / source.range);
                attenuation = falloff * falloff;
            }
        } else {
            toLight = -source.direction;
        }
        light += source.color * max(0.0, dot(normal, toLight)) * attenuation;
    }
    return light;
}

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
    constant float *sizeCurve [[buffer(3)]],
    const device uint2 *sortRecords [[buffer(4)]],
    constant ParticleLightData *lights [[buffer(5)]]
) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    // Sorted emitters draw instance i as the i-th farthest particle.
    Particle p = particles[uniforms.readsSortRecords != 0 ? sortRecords[instanceID].y : instanceID];
    VertexOut out;
    float age = p.position.w;
    float lifetime = p.velocity.w;
    if (lifetime <= 0 || age >= lifetime) {
        out.position = float4(0, 0, 0, 0); // Degenerate, clipped.
        out.color = 0;
        out.uv = 0;
        out.texcoord = 0;
        out.viewDepth = 0;
        return out;
    }
    float t = saturate(age / lifetime);
    float size = sampleCurve(sizeCurve, t) * p.properties.x;
    float2 corner = corners[vertexID];

    // The quad's right and up axes in world space.
    float3 right = uniforms.cameraRight;
    float3 up = uniforms.cameraUp;
    float stretch = 1;
    float3 center = (uniforms.model * float4(p.position.xyz, 1)).xyz;
    float3 toCamera = uniforms.cameraPosition - center;
    switch (uniforms.orientationMode) {
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
            stretch = 1 + uniforms.velocityStretch * speed;
        }
        break;
    }
    case ParticleOrientationModeFixed: {
        float3 normal = normalize(uniforms.fixedNormal);
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
    if (uniforms.isLit != 0) {
        out.color.rgb *= particleLight(uniforms, lights, center, right * offset.x + up * offset.y);
    }
    out.viewDepth = dot(world - uniforms.cameraPosition, uniforms.cameraForward);
    out.uv = corner;
    uint columns = max(uniforms.sheetColumns, 1u);
    uint rows = max(uniforms.sheetRows, 1u);
    uint frame = sequenceFrame(p.rotation.z, p.rotation.w, age, uniforms.frameCount, uniforms.sequenceMode);
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

fragment float4 particleFragment(
    VertexOut in [[stage_in]],
    constant RenderUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sprite [[texture(0)]],
    sampler spriteSampler [[sampler(0)]],
    texture2d<float, access::read> sceneDepth [[texture(1)]]
) {
    float4 color = in.color;
    // Soft particles: fade out where the particle comes within `softness` of the scene behind it.
    if (uniforms.hasSceneDepth != 0 && uniforms.softness > 0) {
        uint2 pixel = uint2(in.position.xy);
        if (pixel.x < sceneDepth.get_width() && pixel.y < sceneDepth.get_height()) {
            float depth = sceneDepth.read(pixel).r;
            float3 unproject = uniforms.depthUnproject;
            float sceneDistance = -unproject.y / (depth * unproject.z - unproject.x);
            color.a *= saturate((sceneDistance - in.viewDepth) / uniforms.softness);
        }
    }
    // Premultiplied coverage and color before tinting by the particle color.
    float4 base;
    if (uniforms.hasTexture != 0) {
        base = sprite.sample(spriteSampler, in.texcoord);
    } else {
        float falloff = saturate(1.0 - length(in.uv));
        float coverage = falloff * falloff;
        base = float4(coverage, coverage, coverage, coverage);
    }
    float alpha = base.a * color.a;
    if (uniforms.blendMode == ParticleBlendModeOpaque) {
        if (alpha < 0.5) {
            discard_fragment();
        }
        float3 unpremultiplied = base.a > 0 ? base.rgb / base.a : base.rgb;
        return float4(unpremultiplied * color.rgb, 1);
    }
    return float4(base.rgb * color.rgb * color.a, alpha);
}
