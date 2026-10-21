#include "ParticleCommon.h"

// Spawning, forces, collision, and the per-step update kernel.

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

// Steers toward moving along the path at field.speed, pulled onto it at field.strength per second.
static float3 pathAcceleration(ForceFieldData field, constant float4 *pathPoints, float3 position, float3 velocity) {
    uint count = field.pathCount;
    if (count < 2) {
        return float3(0);
    }
    uint segments = field.pathClosed != 0 ? count : count - 1;
    float bestDistanceSquared = INFINITY;
    float3 closest = 0;
    float3 tangent = float3(0, 1, 0);
    for (uint i = 0; i < segments; i++) {
        float3 a = pathPoints[field.pathStart + i].xyz;
        float3 b = pathPoints[field.pathStart + (i + 1) % count].xyz;
        float3 ab = b - a;
        float lengthSquared = dot(ab, ab);
        float t = lengthSquared > 0 ? saturate(dot(position - a, ab) / lengthSquared) : 0;
        float3 point = a + ab * t;
        float3 offset = position - point;
        float distanceSquared = dot(offset, offset);
        if (distanceSquared < bestDistanceSquared && lengthSquared > 0) {
            bestDistanceSquared = distanceSquared;
            closest = point;
            tangent = ab * rsqrt(lengthSquared);
        }
    }
    float falloff = fieldFalloff(sqrt(bestDistanceSquared), field.radius);
    float3 target = tangent * field.speed + (closest - position) * field.strength;
    // Catch up with the target velocity within about a quarter second.
    return (target - velocity) * 4.0 * falloff;
}

static float3 fieldAcceleration(ForceFieldData field, constant float4 *pathPoints, float3 position, float3 velocity, float time) {
    switch (field.kind) {
    case ParticleForceFieldKindPath:
        return pathAcceleration(field, pathPoints, position, velocity);
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
    float4 tint;     // Multiplies the particle's color; zero for none.
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
    case ParticleEmitterShapeKindPoints: {
        uint count = shape.meshVertexCount;
        if (count == 0) {
            return { float3(0), sweptDirection(rng, twoPi) };
        }
        uint index = min(uint(rng.next() * count), count - 1);
        EmitterPointData point = ((constant EmitterPointData *)triangles)[index];
        float3 normal = point.normal.w != 0 ? point.normal.xyz : sweptDirection(rng, twoPi);
        return { point.position.xyz, normal, point.position.w != 0 ? point.color : float4(0) };
    }
    default:
        return { float3(0), sweptDirection(rng, twoPi) };
    }
}

// World position of the scene depth at `pixel`.
static float3 depthWorldPosition(DepthCollisionData d, texture2d<float, access::read> depth, uint2 pixel) {
    float value = depth.read(pixel).r;
    float2 ndc = (float2(pixel) + 0.5) / float2(d.size) * float2(2, -2) + float2(-1, 1);
    float4 world = d.inverseViewProjection * float4(ndc, value, 1);
    return world.xyz / world.w;
}

// Whether `position` is just behind the scene depth (within thickness of the surface there), and if so the surface
// point and its normal, rebuilt from neighboring depth samples and facing the camera.
static bool sceneDepthContact(DepthCollisionData d, texture2d<float, access::read> depth, float3 position, thread float3 &surface, thread float3 &normal) {
    float4 clip = d.viewProjection * float4(position, 1);
    if (clip.w <= 1e-5) {
        return false;
    }
    float3 ndc = clip.xyz / clip.w;
    if (any(abs(ndc.xy) >= 1)) {
        return false;
    }
    uint2 pixel = min(uint2((ndc.xy * float2(0.5, -0.5) + 0.5) * float2(d.size)), d.size - 1);
    float sceneValue = depth.read(pixel).r;
    // The far plane (1, or 0 with reverse Z) means nothing was drawn there; otherwise the particle must be behind the
    // surface (farther: larger depth, or smaller with reverse Z).
    bool empty = d.reverseZ != 0 ? sceneValue <= 0 : sceneValue >= 1;
    bool inFront = d.reverseZ != 0 ? ndc.z >= sceneValue : ndc.z <= sceneValue;
    if (empty || inFront) {
        return false;
    }
    surface = depthWorldPosition(d, depth, pixel);
    if (distance(position, surface) > d.thickness) {
        return false;
    }
    // Neighbors on the side that stays on the same surface (the closer one), so edges do not tilt the normal.
    uint2 right = uint2(min(pixel.x + 1, d.size.x - 1), pixel.y);
    uint2 left = uint2(pixel.x > 0 ? pixel.x - 1 : 0, pixel.y);
    uint2 down = uint2(pixel.x, min(pixel.y + 1, d.size.y - 1));
    uint2 up = uint2(pixel.x, pixel.y > 0 ? pixel.y - 1 : 0);
    float3 r = depthWorldPosition(d, depth, right) - surface;
    float3 l = surface - depthWorldPosition(d, depth, left);
    float3 dn = depthWorldPosition(d, depth, down) - surface;
    float3 u = surface - depthWorldPosition(d, depth, up);
    float3 dx = length_squared(r) < length_squared(l) ? r : l;
    float3 dy = length_squared(dn) < length_squared(u) ? dn : u;
    float3 toCamera = d.cameraPosition - surface;
    float3 n = cross(dx, dy);
    normal = length_squared(n) > 1e-12 ? normalize(n) : normalize(toCamera);
    if (dot(normal, toCamera) < 0) {
        normal = -normal;
    }
    return true;
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

// Signed distance field colliders. Grid samples sit on cell corners, so sample i of n is at texture coordinate
// (i + 0.5) / n; filtering between them is hardware trilinear.
constexpr sampler fieldSampler(coord::normalized, filter::linear, address::clamp_to_edge);

static float3 fieldLocal(ColliderData c, float3 world) {
    return rotate(float4(-c.rotation.xyz, c.rotation.w), world - c.center);
}

// Distance at a local point, grown by c.radius (the particle's collision radius); a large value outside the grid, so
// nothing there collides.
static float fieldDistance(texture3d<float> field, ColliderData c, float3 local) {
    if (any(local < c.fieldMin) || any(local > c.fieldMax)) {
        return INFINITY;
    }
    float3 size = float3(field.get_width(), field.get_height(), field.get_depth());
    float3 uvw = ((local - c.fieldMin) / c.fieldSpacing + 0.5) / size;
    return field.sample(fieldSampler, uvw).r - c.radius;
}

// Outward unit normal in world space, from central differences one sample apart.
static float3 fieldNormal(texture3d<float> field, ColliderData c, float3 local) {
    float3 h = c.fieldSpacing;
    float3 size = float3(field.get_width(), field.get_height(), field.get_depth());
    float3 uvw = ((local - c.fieldMin) / c.fieldSpacing + 0.5) / size;
    float3 step = 1 / size;
    float3 gradient = float3(
        field.sample(fieldSampler, uvw + float3(step.x, 0, 0)).r - field.sample(fieldSampler, uvw - float3(step.x, 0, 0)).r,
        field.sample(fieldSampler, uvw + float3(0, step.y, 0)).r - field.sample(fieldSampler, uvw - float3(0, step.y, 0)).r,
        field.sample(fieldSampler, uvw + float3(0, 0, step.z)).r - field.sample(fieldSampler, uvw - float3(0, 0, step.z)).r
    ) / (2 * h);
    float length = metal::length(gradient);
    return rotate(c.rotation, length > 1e-6 ? gradient / length : float3(0, 1, 0));
}

// Pushes a particle that ends inside the field out along the normal. One that ends outside but crossed the surface
// during the step (`start` to `position`, in the collider's frame now) is caught by sampling along the step, about
// one sample per cell, then refined to the surface: fast particles do not pass through thin walls.
static void fieldContact(texture3d<float> field, ColliderData c, float3 start, thread float3 &position, thread float3 &velocity, float restitution, float friction, thread bool &hit) {
    float3 local = fieldLocal(c, position);
    float3 startLocal = fieldLocal(c, start);
    float distance = fieldDistance(field, c, local);
    if (distance < 0) {
        // Came in this step: respond where the path went in, plus the rest of the step's motion along the surface.
        // Pushing out to the nearest surface from where the step ended can pick a side of a thin part, or its far
        // face, so particles slid off or sank in (#157). Stopping at the entry point alone threw away motion along
        // the surface, so sliding particles (Marble Run's marbles) crawled; the along-surface part is kept, and only
        // the part into the surface is dropped.
        if (fieldDistance(field, c, startLocal) >= 0) {
            float low = 0;
            float high = 1;
            for (int refine = 0; refine < 6; refine++) {
                float middle = (low + high) / 2;
                if (fieldDistance(field, c, mix(startLocal, local, middle)) < 0) { high = middle; } else { low = middle; }
            }
            float3 contact = mix(startLocal, local, low);
            float3 normal = fieldNormal(field, c, contact);
            // Coulomb friction on the carried motion: it holds unless the along-surface part beats friction times the
            // part into the surface. Resting particles stay put (a thin part's tilted normal would otherwise walk them
            // off its edge), and sliding ones keep their speed.
            float3 rest = rotate(c.rotation, local - contact);
            float into = max(-dot(rest, normal), 0.0);
            float3 along = rest - normal * dot(rest, normal);
            float alongLength = length(along);
            float kept = alongLength > 1e-7 ? max(0.0, 1 - friction * into / alongLength) : 0;
            position = c.center + rotate(c.rotation, contact) + along * kept + normal * 1e-4;
            collide(position, velocity, c, normal, 0, restitution, friction, hit);
            return;
        }
        // Started inside too (pushed in by a moving collider, say): out along the normal.
        collide(position, velocity, c, fieldNormal(field, c, local), -distance, restitution, friction, hit);
        return;
    }
    float cells = metal::length((local - startLocal) / c.fieldSpacing);
    if (cells < 1) {
        return;
    }
    int steps = int(min(ceil(cells), 32.0));
    float previous = 0;
    for (int index = 1; index < steps; index++) {
        float t = float(index) / float(steps);
        if (fieldDistance(field, c, mix(startLocal, local, t)) < 0) {
            // Bisect between the last outside sample and this inside one.
            float low = previous;
            float high = t;
            for (int refine = 0; refine < 5; refine++) {
                float middle = (low + high) / 2;
                if (fieldDistance(field, c, mix(startLocal, local, middle)) < 0) { high = middle; } else { low = middle; }
            }
            float3 contact = mix(startLocal, local, low);
            float3 normal = fieldNormal(field, c, contact);
            position = c.center + rotate(c.rotation, contact) + normal * 1e-4;
            collide(position, velocity, c, normal, 0, restitution, friction, hit);
            return;
        }
        previous = t;
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
    thread float &birthAge,
    float orderedBirthAge = -1
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
            sample.tint = float4(0);
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
        // Drawn either way, so later draws are the same; ribbon emitters replace it to keep births in slot order.
        if (orderedBirthAge >= 0) {
            birthAge = orderedBirthAge;
        }
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
        // A set tint never packs to 0 (no tint): transparent black becomes the smallest nonzero value.
        uint tint = all(sample.tint == 0) ? 0u : max(pack_float_to_unorm4x8(saturate(sample.tint)), 1u);
        p.properties = float4(sizeScale, restitutionOffset, frictionOffset, as_type<float>(tint));
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
    float4 color;  // Multiplies the color over life; 1 leaves it alone. Stored as 8 bits per channel.
    float size;    // Multiplies the size over life.
    float4 custom; // Free for user code; kept between steps, zero at birth.
    float4 custom1; // More of the same, when the emitter has customAttributeCount 2 to 4; otherwise not kept.
    float4 custom2;
    float4 custom3;
};


static void setParticleTint(thread Particle &p, float4 color) {
    // A set tint never packs to 0 (no tint): transparent black becomes the smallest nonzero value.
    uint tint = all(color == 1) ? 0u : max(pack_float_to_unorm4x8(saturate(color)), 1u);
    p.properties.w = as_type<float>(tint);
}

// ParticleState.custom through custom3, as kept in the attribute buffer.
struct CustomAttributes {
    float4 values[4];
};

// The particle's `count` attributes from the buffer (stride entries per particle), zero past them.
static CustomAttributes loadAttributes(const device float4 *attributes, uint id, uint stride, uint count, bool present) {
    CustomAttributes custom = {};
    for (uint i = 0; present && i < min(count, stride); i++) {
        custom.values[i] = attributes[id * stride + i];
    }
    return custom;
}

static void storeAttributes(device float4 *attributes, uint id, uint stride, uint count, CustomAttributes custom) {
    for (uint i = 0; i < min(count, stride); i++) {
        attributes[id * stride + i] = custom.values[i];
    }
}

static ParticleState makeState(Particle p, float3 position, float3 velocity, float age, float lifetime, uint id, CustomAttributes custom) {
    return { position, velocity, age, lifetime, id, particleTint(p), p.properties.x,
        custom.values[0], custom.values[1], custom.values[2], custom.values[3] };
}

// Copies back what every slot may change; callers copy age and lifetime where their slot allows it.
static void applyState(ParticleState state, thread Particle &p, thread float3 &position, thread float3 &velocity, thread CustomAttributes &custom) {
    position = state.position;
    velocity = state.velocity;
    custom.values[0] = state.custom;
    custom.values[1] = state.custom1;
    custom.values[2] = state.custom2;
    custom.values[3] = state.custom3;
    p.properties.x = max(state.size, 0.0);
    if (any(state.color != particleTint(p))) {
        setParticleTint(p, state.color);
    }
}
using ParticleUpdateFunction = void(thread ParticleState &, float deltaTime, float time, constant float4 *parameters);

// Stand-ins for missing user functions, one per table: linking one function twice into a pipeline is an error.
[[visible]] void particleNoUpdate(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoSpawn(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoCollision(thread ParticleState &, float, float, constant float4 *) {}
[[visible]] void particleNoDeath(thread ParticleState &, float, float, constant float4 *) {}

// Removes the parts of a world-space position and velocity that leave the emitter's plane.
static void constrainToPlane(thread float3 &position, thread float3 &velocity, constant SimulationUniforms &uniforms) {
    if (uniforms.constrainsToPlane == 0) {
        return;
    }
    float3 normal = uniforms.planeNormal;
    position -= normal * dot(position - uniforms.planePoint, normal);
    velocity -= normal * dot(velocity, normal);
}

// Records `position` at the trail's head. Every step (interval 0), or when `interval` seconds have passed since the head
// was recorded, the trail shifts one point toward the tail first; otherwise the head just follows the particle. Each
// point's w is the age it was recorded at. `reset` fills the trail with `position` at `age`.
static void pushTrail(device float4 *trails, uint base, uint count, float3 position, bool reset, float age, float interval) {
    if (reset) {
        for (uint i = 0; i < count; i++) {
            trails[base + i] = float4(position, age);
        }
        return;
    }
    if (interval > 0 && age - trails[base].w < interval) {
        trails[base].xyz = position;
        return;
    }
    for (uint i = count - 1; i > 0; i--) {
        trails[base + i] = trails[base + i - 1];
    }
    trails[base] = float4(position, age);
}

static void writeEvent(device atomic_uint *cursor, device ParticleEventRecord *events, ParticleEventKind kind, float3 position, float3 velocity, float time, uint emitterIndex, uint colliderIndex) {
    uint sequence = atomic_fetch_add_explicit(cursor, 1u, memory_order_relaxed) + 1;
    device ParticleEventRecord &record = events[(sequence - 1) % PARTICLE_EVENT_CAPACITY];
    record.position = float4(position, time);
    record.velocity = float4(velocity, 0);
    record.kind = kind;
    record.emitterIndex = emitterIndex;
    record.colliderIndex = colliderIndex;
    atomic_thread_fence(mem_flags::mem_device, memory_order_seq_cst, thread_scope_device);
    record.sequence = sequence;
}


// Foil's glint for a face with `normal` (either side), as in foilShade: 0 to 1.
static float glintAt(float3 normal, float3 toCamera, float3 halfway, float shininess) {
    float3 n = dot(normal, toCamera) < 0 ? -normal : normal;
    return pow(max(dot(n, halfway), 0.0), shininess);
}

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
    device float4 *attributes [[buffer(21)]],
    constant uint &attributeCount [[buffer(22)]],
    constant uint &attributeStride [[buffer(30)]],
    device atomic_uint *eventCursor [[buffer(23)]],
    device ParticleEventRecord *events [[buffer(24)]],
    constant float4 *pathPoints [[buffer(25)]],
    constant float4 *birthColorCurve [[buffer(29)]],
    constant DepthCollisionData &depthCollision [[buffer(26)]],
    texture2d<float, access::read> sceneDepth [[texture(0)]],
    array<texture3d<float>, PARTICLE_MAX_SIGNED_DISTANCE_FIELDS> signedDistanceFields [[texture(1)]],
    device float4 *trails [[buffer(27)]],
    const device float4 *steering [[buffer(28)]],
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
    // ParticleState.custom through custom3. The buffer only covers every particle when some emitter has user functions;
    // each particle has attributeStride entries, of which this emitter keeps customAttributeCount (0: none, no traffic).
    uint customCount = uniforms.customAttributeCount;
    bool hasAttributes = id < attributeCount && customCount > 0;
    CustomAttributes custom = loadAttributes(attributes, id, attributeStride, customCount, hasAttributes);

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
        // Later slots are born later in the step, so they live less of it and start nearer the emitter.
        float orderedBirthAge = uniforms.ordersBirths != 0 ? 1 - (float(offset) + 0.5) / float(max(spawn.count, 1u)) : -1;
        p = spawnParticle(rng, uniforms, mesh, float3(0), float3(0), birthAge, orderedBirthAge);
        dt *= birthAge;
        custom = CustomAttributes {};
        if (uniforms.colorsByBirthPosition != 0) {
            // The position gradient, once, where the particle is born; kept in its tint for life.
            float3 born = (uniforms.simulationToWorld * float4(p.position.xyz, 1)).xyz;
            float3 axis = uniforms.birthColorEnd - uniforms.birthColorStart;
            float along = dot(born - uniforms.birthColorStart, axis) / max(dot(axis, axis), 1e-10);
            setParticleTint(p, particleTint(p) * sampleCurve(birthColorCurve, saturate(along)));
        }
        if (uniforms.hasSpawnFunction != 0) {
            // The user sees world space, like the update function; deltaTime is 0 at birth.
            ParticleState state = makeState(p,
                (uniforms.simulationToWorld * float4(p.position.xyz, 1)).xyz,
                (uniforms.simulationToWorld * float4(p.velocity.xyz, 0)).xyz,
                p.position.w, p.velocity.w, id, custom);
            spawnFunction[0](state, 0, uniforms.time, spawnParameters);
            float3 position;
            float3 velocity;
            applyState(state, p, position, velocity, custom);
            p.position.xyz = (uniforms.worldToSimulation * float4(position, 1)).xyz;
            p.velocity.xyz = (uniforms.worldToSimulation * float4(velocity, 0)).xyz;
            p.velocity.w = max(state.lifetime, 1e-4);
        }
    }

    float lifetime = p.velocity.w;
    float age = p.position.w;
    if (lifetime <= 0 || age >= lifetime) {
        particles[id] = p;
        if (hasAttributes) {
            storeAttributes(attributes, id, attributeStride, customCount, custom);
        }
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
        acceleration += fieldAcceleration(forceFields[i], pathPoints, position, velocity, uniforms.time);
    }
    velocity += acceleration * dt;
    if (uniforms.flocks != 0) {
        velocity += (uniforms.simulationToWorld * float4(steering[id].xyz, 0)).xyz * dt;
        float speed = length(velocity);
        float2 range = uniforms.flockSpeedRange;
        if (speed > 1e-5) {
            velocity *= clamp(speed, range.x, range.y) / speed;
        }
    }
    velocity *= max(0.0, 1.0 - uniforms.drag * dt);
    position += velocity * dt;
    if (uniforms.hasUpdateFunction != 0) {
        ParticleState state = makeState(p, position, velocity, age, lifetime, id, custom);
        updateFunction[0](state, dt, uniforms.time, updateParameters);
        applyState(state, p, position, velocity, custom);
    }
    // After spawn spread, fields, turbulence, and user code, before collisions.
    constrainToPlane(position, velocity, uniforms);
    p.rotation.x += p.rotation.y * dt;

    float restitution = max(0.0, uniforms.restitution + p.properties.y);
    float friction = saturate(uniforms.friction + p.properties.z);

    bool hit = false;
    uint firstHitCollider = 0xFFFFFFFFu;
    for (uint i = 0; i < uniforms.colliderCount; i++) {
        // Hits on earlier colliders this step do not count toward this one.
        bool hitBefore = hit;
        hit = false;
        ColliderData c = colliders[i];
        if (uniforms.collisionRadius > 0) {
            // Particles as spheres: grow the collider instead, so every test below (and the sweeps) stays the same.
            float r = uniforms.collisionRadius;
            c.distance += r;
            c.radius += r;
            c.halfExtents += r;
        }
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
        } else if (c.kind == ParticleColliderKindSignedDistanceField) {
            if (c.fieldIndex < PARTICLE_MAX_SIGNED_DISTANCE_FIELDS) {
                // In the collider's frame now: where the particle started, carried along by the collider's motion
                // over the step, its spin included. A particle resting on a turning collider then starts on its
                // surface, not off it.
                texture3d<float> field = signedDistanceFields[c.fieldIndex];
                float3 start = startPosition + (c.velocity + cross(c.angularVelocity, startPosition - c.pivot)) * dt;
                fieldContact(field, c, start, position, velocity, restitution, friction, hit);
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
        if (!hit && c.kind != ParticleColliderKindPlane && c.kind != ParticleColliderKindSignedDistanceField) {
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
        if (hit && firstHitCollider == 0xFFFFFFFFu) {
            firstHitCollider = c.triggerIndex;
        }
        if (hit && uniforms.countsColliderHits != 0 && c.triggerIndex < PARTICLE_TRIGGER_MAX_COLLIDERS) {
            atomic_fetch_add_explicit(&triggerCounters[c.triggerIndex], 1u, memory_order_relaxed);
        }
        hit = hit || hitBefore;
    }
    // The scene depth: whatever the host drew last frame, as a surface particles bounce off.
    if (uniforms.collidesWithSceneDepth != 0 && depthCollision.enabled != 0) {
        float3 surface;
        float3 normal;
        if (sceneDepthContact(depthCollision, sceneDepth, position, surface, normal)) {
            bool depthHit = false;
            ColliderData still = {};
            position = surface + normal * (1e-3 + uniforms.collisionRadius);
            collide(position, velocity, still, normal, 0, restitution, friction, depthHit);
            if (firstHitCollider == 0xFFFFFFFFu) {
                firstHitCollider = PARTICLE_EVENT_SCENE_DEPTH_COLLIDER;
            }
            hit = true;
        }
    }
    // Again after collisions: a curved collider can push a particle off the plane.
    constrainToPlane(position, velocity, uniforms);

    // Trigger volumes count particles that were outside at the start of the step and inside at the end.
    uint volumeCount = min(uniforms.triggerVolumeCount, uint(PARTICLE_TRIGGER_MAX_VOLUMES));
    for (uint i = 0; i < volumeCount; i++) {
        TriggerVolumeData volume = triggerVolumes[i];
        if (volume.contains(position) && !volume.contains(startPosition)) {
            atomic_fetch_add_explicit(&triggerCounters[PARTICLE_TRIGGER_MAX_COLLIDERS + i], 1u, memory_order_relaxed);
        }
    }

    // Contact friction slows spin like it slows sliding, so particles resting on a collider stop turning.
    if (hit) {
        p.rotation.y *= 1.0 - friction;
    }
    if (hit && uniforms.reportsCollisions != 0) {
        writeEvent(eventCursor, events, ParticleEventKindCollision, position, velocity, uniforms.time, uniforms.eventEmitterIndex, firstHitCollider);
    }
    if (hit && uniforms.diesOnCollision != 0) {
        age = lifetime;
    }
    // Event functions may also change age and lifetime: setting age to lifetime kills the particle, and a death
    // function that raises lifetime keeps it alive. Collision runs first, so it can kill.
    if (hit && uniforms.hasCollisionFunction != 0) {
        ParticleState state = makeState(p, position, velocity, age, lifetime, id, custom);
        collisionFunction[0](state, dt, uniforms.time, collisionParameters);
        applyState(state, p, position, velocity, custom);
        age = state.age;
        lifetime = state.lifetime;
    }
    if (age >= lifetime && uniforms.hasDeathFunction != 0) {
        ParticleState state = makeState(p, position, velocity, age, lifetime, id, custom);
        deathFunction[0](state, dt, uniforms.time, deathParameters);
        applyState(state, p, position, velocity, custom);
        age = state.age;
        lifetime = state.lifetime;
    }

    if (age >= lifetime && previousAge < lifetime && uniforms.reportsDeaths != 0) {
        writeEvent(eventCursor, events, ParticleEventKindDeath, position, velocity, uniforms.time, uniforms.eventEmitterIndex, 0xFFFFFFFFu);
    }

    // Sub-emitters: on an event, write children into the slots this particle owns in each child slice. Children live in
    // world space, so they start at this particle's world position.
    // Sub-emitter children this particle writes, for the birth statistics.
    uint childrenWritten = 0;
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
        case ParticleSpawnOccasionGlint: {
            // The glint foil shading draws, from the particle's tumble before and after this step's spin.
            if (uniforms.hasGlintCamera != 0 && !born) {
                float3 axis = tumbleAxis(id);
                float3 toCamera = normalize(uniforms.glintCamera - position);
                float3 toLight = uniforms.glintLight.w > 0 ? normalize(uniforms.glintLight.xyz - position) : uniforms.glintLight.xyz;
                float3 halfway = normalize(toLight + toCamera);
                float before = glintAt(rotateAbout(float3(0, 0, 1), axis, p.rotation.x - p.rotation.y * dt), toCamera, halfway, uniforms.glintShininess);
                float after = glintAt(rotateAbout(float3(0, 0, 1), axis, p.rotation.x), toCamera, halfway, uniforms.glintShininess);
                count = before < interval && interval <= after ? childrenPerEvent : 0;
            }
            break;
        }
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
        childrenWritten += count;
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
            SimulationUniforms childUniforms = subEmitterUniforms[i];
            if (childUniforms.trailPointCount > 1 && childUniforms.trailStride > 0) {
                pushTrail(trails, (sub.childSliceStart + childSlot) * childUniforms.trailStride, childUniforms.trailPointCount, child.position.xyz, true, child.position.w, 0);
            }
            if (sub.childSliceStart + childSlot < attributeCount) {
                storeAttributes(attributes, sub.childSliceStart + childSlot, attributeStride, attributeStride, CustomAttributes {});
            }
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
    if (uniforms.trailPointCount > 1 && uniforms.trailStride > 0) {
        // New particles start with the whole trail at their position, so they do not streak from the slot's last one.
        pushTrail(trails, id * uniforms.trailStride, uniforms.trailPointCount, position, born, age, uniforms.trailPointInterval);
    }
    if (hasAttributes) {
        storeAttributes(attributes, id, attributeStride, customCount, custom);
    }

    // Statistics: one atomic per SIMD group, not per particle. Particles that were already dead returned earlier.
    if (uniforms.countsAlive != 0) {
        uint alive = simd_sum(age < lifetime ? 1u : 0u);
        if (simd_is_first()) {
            atomic_fetch_add_explicit(&aliveCounters[uniforms.aliveCounterSlot], alive, memory_order_relaxed);
        }
    }
    // Births (spawned here, or children written by this particle) and deaths this step, after the live counts.
    uint births = simd_sum((born ? 1u : 0u) + childrenWritten);
    uint deaths = simd_sum(age >= lifetime && previousAge < lifetime ? 1u : 0u);
    if (simd_is_first()) {
        if (births > 0) {
            atomic_fetch_add_explicit(&aliveCounters[PARTICLE_ALIVE_COUNTER_SLOTS + uniforms.aliveCounterSlot], births, memory_order_relaxed);
        }
        if (deaths > 0) {
            atomic_fetch_add_explicit(&aliveCounters[2 * PARTICLE_ALIVE_COUNTER_SLOTS + uniforms.aliveCounterSlot], deaths, memory_order_relaxed);
        }
    }
}

