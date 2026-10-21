#include "ParticleCommon.h"

// Particle vertex and fragment shaders, shading functions, and particle lights.

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

// Whether the vertex shader calls the shading function (#172). False for draws that skip it (unlit sprites, trails,
// ribbons) and for per-pixel shading: the call compiles out.
constant bool particleHasShading [[function_constant(0)]];
// Per-pixel shading (#174): the vertex shader passes the shading input on and the fragment shader calls the function.
constant bool particleShadesPerPixel [[function_constant(1)]];

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;       // Quad corner space, -1...1. Drives the procedural dot.
    float2 texcoord; // Sprite sheet cell coordinates.
    float viewDepth; // Distance in front of the camera, for soft particles.
    // ShadingInput for per-pixel shading, interpolated; absent otherwise. `color` is the unshaded color.
    float3 shadingPosition [[function_constant(particleShadesPerPixel)]];
    float3 shadingNormal [[function_constant(particleShadesPerPixel)]];
    float3 shadingSphereNormal [[function_constant(particleShadesPerPixel)]];
    float3 shadingToCamera [[function_constant(particleShadesPerPixel)]];
    float shadingAge [[function_constant(particleShadesPerPixel)]];
    float shadingLifetime [[function_constant(particleShadesPerPixel)]];
    uint shadingID [[flat, function_constant(particleShadesPerPixel)]];
    uint shadingIsMesh [[flat, function_constant(particleShadesPerPixel)]];
};

// Diffuse light at a quad corner. The quad is shaded like a small sphere: the normal leans from the camera direction
// toward the corner, so lit particles get a soft gradient instead of a flat tint.
static float3 diffuseLight(ParticleLightData source, float3 center, float3 normal) {
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
    return source.color * max(0.0, dot(normal, toLight)) * attenuation;
}

// MARK: - Shading (#172)

// The shading-function ABI, mirrored by ShadingFunction.prelude in Swift. One call per vertex returns the vertex color.
struct ShadingInput {
    float3 position;     // World space: the particle's center (sprites, trails, ribbons) or the vertex (meshes).
    float3 normal;       // The quad's plane (sprites), toward the camera (trails, ribbons), or the mesh normal.
    float3 sphereNormal; // Sprites shaded like a small sphere: leaning from the camera toward the corner. Meshes: normal.
    float3 toCamera;     // Unit length.
    float4 color;        // The color before shading: curves, variation, and tint.
    float age;
    float lifetime;
    uint id;
    uint isMesh;
    float2 uv; // Sprites: quad corner space, -1...1 (per pixel, the pixel's spot on the quad). Trails and ribbons: along, across.
};

struct ShadingScene {
    float3 ambient;
    uint lightCount;         // Scene lights in `lights`.
    uint particleLightCount; // Lights from emitting particles in `particleLights`.
};

using ShadingFunction = float4(ShadingInput, ShadingScene, constant ParticleLightData *, const device ParticleLightData *, constant float4 *);

static ShadingScene shadingScene(constant RenderUniforms &uniforms) {
    return { uniforms.ambientLight, min(uniforms.lightCount, uint(PARTICLE_MAX_LIGHTS)), min(uniforms.particleLightCount, uint(PARTICLE_MAX_PARTICLE_LIGHTS)) };
}

// The sphere normal particleLight uses: from the camera direction toward the corner.
static float3 sphereNormal(constant RenderUniforms &uniforms, float3 center, float3 cornerDirection) {
    float3 toCamera = normalize(uniforms.cameraPosition - center);
    return normalize(cornerDirection + toCamera);
}

// Reflective foil (#175). Metal has no matte color of its own: it shows what it reflects, tinted by the metal. The view
// direction reflects off the facet and samples a procedural environment (a sky band brightest near the horizon, a dark
// floor, a few soft bright patches) plus the scene and particle lights as hot spots. Dark when it reflects nothing,
// bright and saturated when it does; white only at the hottest core. `foil` is (glint, shininess, iridescence): glint
// scales the bright patches and lights, shininess tightens them, iridescence shifts the tint's hue with angle.
static float foilEnvironment(float3 r, float3 foil, ShadingScene scene, constant ParticleLightData *lights, const device ParticleLightData *particleLights, float3 position) {
    float horizon = smoothstep(-0.15, 0.1, r.y);
    float sky = mix(0.25, 0.7, 1 - saturate(r.y));
    float environment = mix(0.02, sky, horizon);
    float highlights = 0;
    const float3 patches[3] = { float3(0.53, 0.66, 0.53), float3(-0.79, 0.4, 0.46), float3(0.1, 0.24, -0.97) };
    for (uint i = 0; i < 3; i++) {
        highlights += pow(max(dot(r, patches[i]), 0.0), max(foil.y * 0.25, 2.0));
    }
    for (uint i = 0; i < scene.lightCount; i++) {
        float3 toLight = lights[i].kind == ParticleLightKindPoint ? normalize(lights[i].position - position) : -lights[i].direction;
        highlights += pow(max(dot(r, toLight), 0.0), foil.y) * max(max(lights[i].color.r, lights[i].color.g), lights[i].color.b) * 2;
    }
    for (uint i = 0; i < scene.particleLightCount; i++) {
        float3 toLight = normalize(particleLights[i].position - position);
        highlights += pow(max(dot(r, toLight), 0.0), foil.y) * max(max(particleLights[i].color.r, particleLights[i].color.g), particleLights[i].color.b) * 2;
    }
    return environment + highlights * foil.x * 0.5;
}

static float3 foilShade(float3 foil, ShadingScene scene, constant ParticleLightData *lights, const device ParticleLightData *particleLights, float3 position, float3 normal, float3 toCamera, float3 base) {
    // Two-sided: the face toward the camera reflects.
    float3 n = dot(normal, toCamera) < 0 ? -normal : normal;
    float3 r = reflect(-toCamera, n);
    float environment = foilEnvironment(r, foil, scene, lights, particleLights, position);
    float cosine = abs(dot(n, toCamera));
    float3 film = 0.5 + 0.5 * cos(6.2831853 * ((1 - cosine) * 1.5 + float3(0, 0.33, 0.67)));
    // The metal's color; brightened so a mid-tone base still reads as a bright metal.
    float3 tint = saturate(base * mix(float3(1), film, saturate(foil.z)) * 1.6);
    // Keep the hue when it gets bright: scale by the largest channel instead of clipping each one, then whiten only the
    // hottest core.
    float3 color = tint * environment;
    float peak = max(max(color.r, color.g), color.b);
    if (peak > 1) {
        color /= peak;
    }
    return color + saturate((environment - 4) * 0.08);
}

// Crinkled foil: a grid of small facets, each tilted its own way, so a card breaks into patches that catch the
// environment differently. Per pixel only (`uv` is the pixel's spot on the card).
static float3 foilCrinkle(float3 normal, float2 uv, uint id) {
    // An odd count, so the card's center sits mid-facet rather than on an edge.
    float2 facet = floor((uv * 0.5 + 0.5) * 21);
    uint h = hash(hash(id * 7u + 11u) ^ (uint(facet.x) * 73856093u) ^ (uint(facet.y) * 19349663u));
    // Small tilts: the card's overall facing sets its brightness; facets only break it into patches.
    float2 tilt = (float2(h & 0xFFFFu, h >> 16) / 65535.0 - 0.5) * 0.25;
    float3 tangent = normalize(cross(normal, abs(normal.y) < 0.9 ? float3(0, 1, 0) : float3(1, 0, 0)));
    float3 bitangent = cross(normal, tangent);
    return normalize(normal + tangent * tilt.x + bitangent * tilt.y);
}

// The built-in shading models. Unlit leaves sprites alone (and is not called for them); meshes get a little shading
// toward the camera so the shape reads, both sides of a face counting.
[[visible]] float4 particleShadeUnlit(ShadingInput in, ShadingScene, constant ParticleLightData *, const device ParticleLightData *, constant float4 *) {
    if (in.isMesh != 0) {
        in.color.rgb *= 0.55 + 0.45 * abs(dot(in.normal, in.toCamera));
    }
    return in.color;
}

// Ambient plus each light's diffuse light on the sphere normal.
[[visible]] float4 particleShadeLit(ShadingInput in, ShadingScene scene, constant ParticleLightData *lights, const device ParticleLightData *particleLights, constant float4 *) {
    float3 light = scene.ambient;
    for (uint i = 0; i < scene.lightCount; i++) {
        light += diffuseLight(lights[i], in.position, in.sphereNormal);
    }
    for (uint i = 0; i < scene.particleLightCount; i++) {
        light += diffuseLight(particleLights[i], in.position, in.sphereNormal);
    }
    in.color.rgb *= light;
    return in.color;
}

// parameters[0] is (glint, shininess, iridescence). Sprites run per pixel and crinkle; meshes run per vertex.
[[visible]] float4 particleShadeFoil(ShadingInput in, ShadingScene scene, constant ParticleLightData *lights, const device ParticleLightData *particleLights, constant float4 *parameters) {
    float3 normal = in.isMesh == 0 ? foilCrinkle(in.normal, in.uv, in.id) : in.normal;
    in.color.rgb = foilShade(parameters[0].xyz, scene, lights, particleLights, in.position, normal, in.toCamera, in.color.rgb);
    return in.color;
}

// The emitter's shading function for `in`. Callers check particleHasShading first, so unlit sprites skip building the
// input.
static float4 callShading(constant RenderUniforms &uniforms, visible_function_table<ShadingFunction> table, constant float4 *parameters, constant ParticleLightData *lights, const device ParticleLightData *particleLights, ShadingInput in) {
    return table[0](in, shadingScene(uniforms), lights, particleLights, parameters);
}

// Trails and ribbons: shaded at `position`, facing the camera.
static ShadingInput facingInput(constant RenderUniforms &uniforms, float3 position, float4 color, Particle p, uint index) {
    float3 normal = sphereNormal(uniforms, position, float3(0));
    return { position, normal, normal, normalize(uniforms.cameraPosition - position), color, p.position.w, p.velocity.w, index, 0, float2(0) };
}

// Per pixel: hands `in` to the fragment shader instead of calling the function here.
static void storeShading(thread VertexOut &out, ShadingInput in) {
    if (particleShadesPerPixel) {
        out.shadingPosition = in.position;
        out.shadingNormal = in.normal;
        out.shadingSphereNormal = in.sphereNormal;
        out.shadingToCamera = in.toCamera;
        out.shadingAge = in.age;
        out.shadingLifetime = in.lifetime;
        out.shadingID = in.id;
        out.shadingIsMesh = in.isMesh;
    }
}

// One thread per light: the first live particle in this light's stretch of the slice becomes a point light, dimming
// as it ages. No live particle there means a black light.
kernel void gatherParticleLights(
    const device Particle *particles [[buffer(0)]],
    constant ParticleLightGatherData &gather [[buffer(1)]],
    device ParticleLightData *particleLights [[buffer(2)]],
    constant float4 *colorCurve [[buffer(3)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= gather.count) {
        return;
    }
    float brightest = -1;
    // Stretches cover the live window, where the live particles are, not the whole ring.
    // Proportional split, so every stretch is nonempty whenever the window has at least as many slots as lights.
    uint first = index * gather.windowCount / gather.count;
    uint last = (index + 1) * gather.windowCount / gather.count;
    ParticleLightData light;
    light.kind = ParticleLightKindPoint;
    light.range = gather.range;
    light.direction = float3(0, -1, 0);
    light.position = float3(0);
    light.color = float3(0);
    for (uint offset = first; offset < last; offset++) {
        Particle p = particles[gather.sliceStart + (gather.windowStart + offset) % gather.capacity];
        if (p.velocity.w > 0 && p.position.w < p.velocity.w) {
            float brightness = 0;
            if (gather.picksBrightest != 0) {
                // Luminance of the particle's color (opacity included) at its age, times its tint.
                float4 color = sampleCurve(colorCurve, p.position.w / p.velocity.w) * particleTint(p);
                brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722)) * color.a;
                if (brightness <= brightest) {
                    continue;
                }
            }
            brightest = brightness;
            light.position = (gather.simulationToWorld * float4(p.position.xyz, 1)).xyz;
            light.color = gather.color * (1 - p.position.w / p.velocity.w);
            if (gather.picksBrightest == 0) {
                break;
            }
        }
    }
    particleLights[gather.firstLight + index] = light;
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

static float4 particleBaseColor(constant RenderUniforms &uniforms, constant float4 *colorCurve, constant float4 *extraColorCurves, texture2d<float> colorImage, Particle p, uint index, float t, float3 center);

// Blue, cyan, green, yellow, red for 0...1.
static float3 heatColor(float t) {
    t = saturate(t);
    return saturate(float3(1.5 - abs(4 * t - 3), 1.5 - abs(4 * t - 2), 1.5 - abs(4 * t - 1)));
}

// The debug view's color for a particle, or `color` when there is no debug view.
static float4 debugColor(constant RenderUniforms &uniforms, float4 color, Particle p, uint index, float t) {
    switch (uniforms.debugMode) {
    case ParticleDebugModeWireframe:
        return float4(0.3, 1, 0.4, 1);
    case ParticleDebugModeEmitter: {
        float hue = fract(float(uniforms.debugEmitterIndex) * 0.618034);
        float3 rgb = saturate(abs(fract(hue + float3(0, 2.0 / 3.0, 1.0 / 3.0)) * 6 - 3) - 1);
        return float4(rgb, 1);
    }
    case ParticleDebugModeAge:
        return float4(heatColor(t), 1);
    case ParticleDebugModeSpeed: {
        float speed = length((uniforms.model * float4(p.velocity.xyz, 0)).xyz);
        float2 range = uniforms.debugRange;
        return float4(heatColor((speed - range.x) / max(range.y - range.x, 1e-5)), 1);
    }
    case ParticleDebugModeLifeRemaining:
        return float4(heatColor(1 - (p.velocity.w - p.position.w) / max(uniforms.debugRange.y, 1e-5)), 1);
    case ParticleDebugModeSlot:
        return float4(heatColor(float(index - uniforms.debugSliceStart) / float(max(uniforms.debugCapacity, 1u))), 1);
    case ParticleDebugModeOverdraw:
        return float4(0.08, 0.04, 0.02, 1);
    default:
        return color;
    }
}

// Setup shared by the four particle vertex shaders (#224).

// The particle an instance draws: sorted emitters draw instance i as the i-th farthest particle.
static uint particleIndex(constant RenderUniforms &uniforms, const device uint2 *sortRecords, uint instanceID) {
    return uniforms.readsSortRecords != 0 ? sortRecords[instanceID].y : instanceID;
}

static bool isDead(Particle p) {
    return p.velocity.w <= 0 || p.position.w >= p.velocity.w;
}

// A degenerate vertex, clipped, for a dead particle.
static VertexOut deadVertex() {
    VertexOut out = {};
    out.position = float4(0);
    return out;
}

// The unshaded color: color over life and the extra gradients, the particle's variation, then its tint.
static float4 particleColor(constant RenderUniforms &uniforms, constant float4 *colorCurve, constant float4 *extraColorCurves, texture2d<float> colorImage, Particle p, uint index, float t, float3 center) {
    return applyColorVariation(particleBaseColor(uniforms, colorCurve, extraColorCurves, colorImage, p, index, t, center), p.color) * particleTint(p);
}

// Shades `out.color` now or passes `input` on for per-pixel shading, applies the debug view, and sets the view depth.
static void finishVertex(
    thread VertexOut &out, ShadingInput input, float3 world, Particle p, uint index, float t, constant RenderUniforms &uniforms,
    visible_function_table<ShadingFunction> shadingFunction, constant float4 *shadingParameters,
    constant ParticleLightData *lights, const device ParticleLightData *particleLights
) {
    if (particleHasShading) {
        out.color = callShading(uniforms, shadingFunction, shadingParameters, lights, particleLights, input);
    } else if (particleShadesPerPixel) {
        storeShading(out, input);
    }
    out.color = debugColor(uniforms, out.color, p, index, t);
    out.viewDepth = dot(world - uniforms.cameraPosition, uniforms.cameraForward);
}

// ParticleEmitter.trail: each particle's recent positions as a camera-facing ribbon, two vertices per point, head first.
vertex VertexOut particleTrailVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]],
    constant float4 *colorCurve [[buffer(2)]],
    constant float *sizeCurve [[buffer(3)]],
    const device uint2 *sortRecords [[buffer(4)]],
    constant ParticleLightData *lights [[buffer(5)]],
    const device ParticleLightData *particleLights [[buffer(6)]],
    visible_function_table<ShadingFunction> shadingFunction [[buffer(12)]],
    constant float4 *shadingParameters [[buffer(13)]],
    constant float4 *extraColorCurves [[buffer(8)]],
    const device float4 *trails [[buffer(9)]],
    texture2d<float> colorImage [[texture(2)]]
) {
    uint index = particleIndex(uniforms, sortRecords, instanceID);
    Particle p = particles[index];
    uint count = uniforms.trailPointCount;
    if (isDead(p) || count < 2) {
        return deadVertex();
    }
    VertexOut out = {};
    float age = p.position.w;
    float lifetime = p.velocity.w;
    uint point = min(vertexID / 2, count - 1);
    float side = (vertexID & 1) != 0 ? 1.0 : -1.0;
    uint base = index * uniforms.trailStride;
    float3 here = (uniforms.model * float4(trails[base + point].xyz, 1)).xyz;
    float3 toward = (uniforms.model * float4(trails[base + (point > 0 ? point - 1 : point)].xyz, 1)).xyz;
    float3 away = (uniforms.model * float4(trails[base + min(point + 1, count - 1)].xyz, 1)).xyz;
    float3 tangent = toward - away;
    float3 toCamera = uniforms.cameraPosition - here;
    float3 across = cross(tangent, toCamera);
    across = length_squared(across) > 1e-12 ? normalize(across) : uniforms.cameraRight;
    float t = saturate(age / lifetime);
    float along = float(point) / float(count - 1);
    float width = sampleCurve(sizeCurve, t) * p.properties.x * (uniforms.trailTapers != 0 ? 1 - along : 1);
    float3 world = here + across * side * width;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = particleColor(uniforms, colorCurve, extraColorCurves, colorImage, p, index, t, here);
    if (uniforms.trailFades != 0) {
        out.color *= 1 - along;
    }
    finishVertex(out, facingInput(uniforms, here, out.color, p, index), world, p, index, t, uniforms, shadingFunction, shadingParameters, lights, particleLights);
    // Soft edges across the ribbon; textures run along it.
    out.uv = float2(0, side);
    out.texcoord = float2(along, side * 0.5 + 0.5);
    return out;
}

// `size` at world position `center` after the emitter's size adjustments; unchanged when they are off.
static float adjustedSize(constant RenderUniforms &uniforms, float size, float3 center) {
    if (uniforms.sizeScale != 1) {
        size *= uniforms.sizeScale;
    }
    if (uniforms.minimumScreenSize > 0) {
        // On screen, a half-size s at view depth d covers s * projectionScaleY / d of the half view height.
        float depth = max(dot(center - uniforms.cameraPosition, uniforms.cameraForward), 1e-4);
        size = max(size, uniforms.minimumScreenSize * 2 * depth / max(uniforms.projectionScaleY, 1e-6));
    }
    return size;
}

static bool isLive(Particle p) {
    return p.velocity.w > 0 && p.position.w < p.velocity.w;
}

// ParticleEmitter.ribbon: one camera-facing strip through the emitter's live particles in birth order (its live window,
// oldest first), two vertices per particle. Width is each particle's size and color its own color. A dead particle in
// the window becomes a zero-width, transparent point, so the ribbon breaks there instead of reaching to a stale spot.
vertex VertexOut particleRibbonVertex(
    uint vertexID [[vertex_id]],
    const device Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]],
    constant float4 *colorCurve [[buffer(2)]],
    constant float *sizeCurve [[buffer(3)]],
    constant ParticleLightData *lights [[buffer(5)]],
    const device ParticleLightData *particleLights [[buffer(6)]],
    visible_function_table<ShadingFunction> shadingFunction [[buffer(12)]],
    constant float4 *shadingParameters [[buffer(13)]],
    constant float4 *extraColorCurves [[buffer(8)]],
    texture2d<float> colorImage [[texture(2)]]
) {
    uint count = uniforms.ribbonWindowCount;
    uint offset = min(vertexID / 2, max(count, 1u) - 1);
    float side = (vertexID & 1) != 0 ? 1.0 : -1.0;
    auto slotIndex = [&](uint o) {
        return uniforms.ribbonSliceStart + (uniforms.ribbonWindowStart + o) % max(uniforms.ribbonCapacity, 1u);
    };
    uint index = slotIndex(offset);
    Particle p = particles[index];
    VertexOut out = {};
    out.uv = float2(0, side);
    out.texcoord = 0;
    // Neighbors along the ribbon, skipping dead ones a few slots each way.
    uint olderOffset = offset;
    for (uint i = 1; i <= 4 && offset >= i; i++) {
        if (isLive(particles[slotIndex(offset - i)])) {
            olderOffset = offset - i;
            break;
        }
    }
    uint newerOffset = offset;
    for (uint i = 1; i <= 4 && offset + i < count; i++) {
        if (isLive(particles[slotIndex(offset + i)])) {
            newerOffset = offset + i;
            break;
        }
    }
    if (!isLive(p)) {
        // Sit on a live neighbor with no width or color, so the gap closes cleanly.
        uint neighbor = olderOffset != offset ? olderOffset : newerOffset;
        Particle other = particles[slotIndex(neighbor)];
        float3 at = (uniforms.model * float4(other.position.xyz, 1)).xyz;
        out.position = isLive(other) ? uniforms.viewProjection * float4(at, 1) : float4(0);
        out.color = 0;
        out.viewDepth = dot(at - uniforms.cameraPosition, uniforms.cameraForward);
        return out;
    }
    float3 here = (uniforms.model * float4(p.position.xyz, 1)).xyz;
    float3 older = (uniforms.model * float4(particles[slotIndex(olderOffset)].position.xyz, 1)).xyz;
    float3 newer = (uniforms.model * float4(particles[slotIndex(newerOffset)].position.xyz, 1)).xyz;
    float3 tangent = newer - older;
    float3 toCamera = uniforms.cameraPosition - here;
    float3 across = cross(tangent, toCamera);
    across = length_squared(across) > 1e-12 ? normalize(across) : uniforms.cameraRight;
    float t = saturate(p.position.w / p.velocity.w);
    // 0 at the oldest (tail), 1 at the newest (head).
    float along = count > 1 ? float(offset) / float(count - 1) : 1;
    float width = sampleCurve(sizeCurve, t) * p.properties.x * (uniforms.ribbonTapers != 0 ? along : 1);
    float3 world = here + across * side * width;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = particleColor(uniforms, colorCurve, extraColorCurves, colorImage, p, index, t, here);
    finishVertex(out, facingInput(uniforms, here, out.color, p, index), world, p, index, t, uniforms, shadingFunction, shadingParameters, lights, particleLights);
    out.texcoord = float2(along, side * 0.5 + 0.5);
    return out;
}

// The color over life, with the extra gradients applied. `center` is the particle's world position; `index` its slot.
static float4 particleBaseColor(constant RenderUniforms &uniforms, constant float4 *colorCurve, constant float4 *extraColorCurves, texture2d<float> colorImage, Particle p, uint index, float t, float3 center) {
    float4 color = sampleCurve(colorCurve, t);
    if (uniforms.hasColorImage != 0) {
        // The image under the particle now: its position in the image rectangle, with v running down the image.
        constexpr sampler imageSampler(filter::linear, address::clamp_to_edge);
        float3 offset = center - uniforms.colorImageOrigin;
        float3 u = uniforms.colorImageU;
        float3 v = uniforms.colorImageV;
        float2 uv = float2(dot(offset, u) / max(dot(u, u), 1e-10), 1 - dot(offset, v) / max(dot(v, v), 1e-10));
        color *= colorImage.sample(imageSampler, uv, level(0));
    }
    if (uniforms.hasAlternateColor != 0) {
        float pick = float(hash(index * 7u + 5u)) / 4294967295.0;
        color = mix(color, sampleCurve(extraColorCurves + PARTICLE_CURVE_SAMPLES, t), pick);
    }
    if (uniforms.hasSpeedColor != 0) {
        float speed = length((uniforms.model * float4(p.velocity.xyz, 0)).xyz);
        float2 range = uniforms.speedColorRange;
        color *= sampleCurve(extraColorCurves, saturate((speed - range.x) / max(range.y - range.x, 1e-5)));
    }
    if (uniforms.hasPositionColor != 0) {
        float3 axis = uniforms.positionColorEnd - uniforms.positionColorStart;
        float along = dot(center - uniforms.positionColorStart, axis) / max(dot(axis, axis), 1e-10);
        color *= sampleCurve(extraColorCurves + 2 * PARTICLE_CURVE_SAMPLES, saturate(along));
    }
    return color;
}

vertex VertexOut particleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]],
    constant float4 *colorCurve [[buffer(2)]],
    constant float *sizeCurve [[buffer(3)]],
    const device uint2 *sortRecords [[buffer(4)]],
    constant ParticleLightData *lights [[buffer(5)]],
    const device ParticleLightData *particleLights [[buffer(6)]],
    visible_function_table<ShadingFunction> shadingFunction [[buffer(12)]],
    constant float4 *shadingParameters [[buffer(13)]],
    constant float4 *extraColorCurves [[buffer(8)]],
    texture2d<float> colorImage [[texture(2)]]
) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    uint index = particleIndex(uniforms, sortRecords, instanceID);
    Particle p = particles[index];
    if (isDead(p)) {
        return deadVertex();
    }
    VertexOut out = {};
    float age = p.position.w;
    float lifetime = p.velocity.w;
    float t = saturate(age / lifetime);
    float size = sampleCurve(sizeCurve, t) * p.properties.x;
    float2 corner = corners[vertexID];

    // The quad's right and up axes in world space.
    float3 right = uniforms.cameraRight;
    float3 up = uniforms.cameraUp;
    float stretch = 1;
    float3 center = (uniforms.model * float4(p.position.xyz, 1)).xyz;
    size = adjustedSize(uniforms, size, center);
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
    case ParticleOrientationModeTumbling: {
        // A world-space card turned about the particle's own axis; the spin is the tumble, not an in-plane turn.
        float3 axis = tumbleAxis(index);
        right = rotateAbout(float3(1, 0, 0), axis, p.rotation.x);
        up = rotateAbout(float3(0, 1, 0), axis, p.rotation.x);
        break;
    }
    default:
        break;
    }

    // Rotate the quad, not the UVs, so textures spin with it. Tumbling cards already turned.
    float spin = uniforms.orientationMode == ParticleOrientationModeTumbling ? 0 : p.rotation.x;
    float s = sin(spin);
    float c = cos(spin);
    float2 stretched = float2(corner.x, corner.y * stretch);
    float2 offset = float2(c * stretched.x - s * stretched.y, s * stretched.x + c * stretched.y);
    float3 world = center + (right * offset.x + up * offset.y) * size;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = particleColor(uniforms, colorCurve, extraColorCurves, colorImage, p, index, t, center);
    // The quad's own plane: a tumbling card's real facing, a billboard's camera-facing one. Unused, and compiled out,
    // when the draw does not shade.
    float3 normal = normalize(cross(right, up));
    ShadingInput input = { center, normal, sphereNormal(uniforms, center, right * offset.x + up * offset.y), normalize(toCamera), out.color, age, lifetime, index, 0, corner };
    finishVertex(out, input, world, p, index, t, uniforms, shadingFunction, shadingParameters, lights, particleLights);
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

// Mesh particles (MeshModule): instanced triangles. Each particle tumbles about its own random axis (hashed from its
// slot) by its rotation angle, scaled by its size, at its position.
vertex VertexOut particleMeshVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device Particle *particles [[buffer(0)]],
    constant RenderUniforms &uniforms [[buffer(1)]],
    constant float4 *colorCurve [[buffer(2)]],
    constant float *sizeCurve [[buffer(3)]],
    const device uint2 *sortRecords [[buffer(4)]],
    constant ParticleLightData *lights [[buffer(5)]],
    const device ParticleLightData *particleLights [[buffer(6)]],
    visible_function_table<ShadingFunction> shadingFunction [[buffer(12)]],
    constant float4 *shadingParameters [[buffer(13)]],
    const device float4 *meshVertices [[buffer(7)]],
    constant float4 *extraColorCurves [[buffer(8)]],
    texture2d<float> colorImage [[texture(2)]]
) {
    uint index = particleIndex(uniforms, sortRecords, instanceID);
    Particle p = particles[index];
    if (isDead(p)) {
        return deadVertex();
    }
    VertexOut out = {};
    float age = p.position.w;
    float lifetime = p.velocity.w;
    float t = saturate(age / lifetime);
    float size = sampleCurve(sizeCurve, t) * p.properties.x;
    float3 axis = tumbleAxis(index);
    float3 center = (uniforms.model * float4(p.position.xyz, 1)).xyz;
    size = adjustedSize(uniforms, size, center);
    float3 local = rotateAbout(meshVertices[vertexID * 2].xyz, axis, p.rotation.x) * size;
    float3 normal = rotateAbout(meshVertices[vertexID * 2 + 1].xyz, axis, p.rotation.x);
    float3 world = center + local;
    out.position = uniforms.viewProjection * float4(world, 1);
    out.color = particleColor(uniforms, colorCurve, extraColorCurves, colorImage, p, index, t, center);
    // Meshes always shade, per vertex or per pixel: even unlit ones shade toward the camera.
    ShadingInput input = { world, normal, normal, normalize(uniforms.cameraPosition - world), out.color, age, lifetime, index, 1, float2(0) };
    finishVertex(out, input, world, p, index, t, uniforms, shadingFunction, shadingParameters, lights, particleLights);
    return out;
}

fragment float4 particleFragment(
    VertexOut in [[stage_in]],
    constant RenderUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sprite [[texture(0)]],
    sampler spriteSampler [[sampler(0)]],
    texture2d<float, access::read> sceneDepth [[texture(1)]],
    constant ParticleLightData *lights [[buffer(5)]],
    const device ParticleLightData *particleLights [[buffer(6)]],
    visible_function_table<ShadingFunction> shadingFunction [[buffer(12)]],
    constant float4 *shadingParameters [[buffer(13)]]
) {
    float4 color = in.color;
    if (particleShadesPerPixel) {
        ShadingInput input = {
            in.shadingPosition, normalize(in.shadingNormal), normalize(in.shadingSphereNormal), normalize(in.shadingToCamera),
            in.color, in.shadingAge, in.shadingLifetime, in.shadingID, in.shadingIsMesh, in.uv
        };
        color = shadingFunction[0](input, shadingScene(uniforms), lights, particleLights, shadingParameters);
    }
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
    // Wireframe lines run along the quad's edges, where the soft dot is transparent: draw them solid.
    if (uniforms.debugMode == ParticleDebugModeWireframe) {
        base = float4(1);
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
