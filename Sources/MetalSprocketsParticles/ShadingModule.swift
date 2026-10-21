import Metal
import MetalSprockets

/// How particles are shaded (#172): one function per emitter, called per vertex.
public enum ShadingModel: Sendable, Equatable, Codable {
    /// Sprites, trails, and ribbons as they are; meshes shade a little toward the camera so their shape reads.
    case unlit
    /// Ambient light plus each scene and particle light's diffuse light. Sprites are shaded like small spheres.
    case lit
    /// Metallic foil: color shifts with angle, darkens edge-on, and glints. Sprites glint per pixel.
    case foil(settings: ParticleFoil)
    /// Your own `[[visible]]` function; see `ShadingModule.prelude`.
    case custom(function: ParticleFunction)
}

/// Shading for the emitter's particles. Every emitter has one; unlit by default.
///
/// A custom function has this signature, compiled after `ShadingModule.prelude`:
///
/// ```metal
/// [[visible]] float4 name(ShadingInput input, ShadingScene scene, constant ShadingLight *lights,
///                         const device ShadingLight *particleLights, constant float4 *parameters)
/// ```
///
/// Return the vertex's color. `input.color` is the color before shading. `lights` holds `scene.lightCount` scene
/// lights, and `particleLights` `scene.particleLightCount` lights from emitting particles.
public struct ShadingModule: LoweredModule {
    public static let kind = "shading"
    public static let isRequired = true
    public var model: ShadingModel
    /// Call the function per pixel instead of per vertex (#174): smooth highlights across large faces, at the cost of a
    /// call per pixel. The input is interpolated; `uv` is the pixel's spot on the quad.
    public var perPixel: Bool

    public init(model: ShadingModel = .unlit, perPixel: Bool = false) {
        self.model = model
        self.perPixel = perPixel
    }

    private enum CodingKeys: String, CodingKey {
        case model, perPixel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(ShadingModel.self, forKey: .model)
        perPixel = try container.decodeIfPresent(Bool.self, forKey: .perPixel) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        if perPixel {
            try container.encode(perPixel, forKey: .perPixel)
        }
    }

    init?(lifting emitter: ParticleEmitter) {
        perPixel = emitter.shadesPerPixel
        if let function = emitter.shadingFunction {
            model = .custom(function: function)
        } else if let foil = emitter.foil {
            model = .foil(settings: foil)
        } else {
            model = emitter.isLit ? .lit : .unlit
        }
    }

    func apply(to emitter: inout ParticleEmitter) {
        emitter.isLit = false
        emitter.foil = nil
        emitter.shadingFunction = nil
        emitter.shadesPerPixel = perPixel
        switch model {
        case .unlit: break
        case .lit: emitter.isLit = true
        case let .foil(foil): emitter.foil = foil
        case let .custom(function): emitter.shadingFunction = function
        }
    }

    /// Put before a custom function's source. Mirrors the shader's ShadingInput, ShadingScene, and ParticleLightData.
    public static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct ShadingInput {
        float3 position;     // World space: the particle's center (sprites, trails, ribbons) or the vertex (meshes).
        float3 normal;       // The quad's plane (sprites), toward the camera (trails, ribbons), or the mesh normal.
        float3 sphereNormal; // Sprites shaded like a small sphere: leaning from the camera toward the corner.
        float3 toCamera;     // Unit length.
        float4 color;        // The color before shading: curves, variation, and tint.
        float age;
        float lifetime;
        uint id;
        uint isMesh;
        float2 uv;           // Sprites: the quad's corner space, -1...1 (per pixel: the pixel's spot). Trails, ribbons: along, across.
    };

    struct ShadingScene {
        float3 ambient;
        uint lightCount;
        uint particleLightCount;
    };

    struct ShadingLight {
        uint kind;        // 1 directional, 2 point.
        float range;      // Point: light fades to zero at this distance. 0 means no falloff.
        float3 color;     // Color times intensity.
        float3 direction; // Directional: the direction light travels, unit length.
        float3 position;  // Point.
    };

    """

    /// A custom function that compiles as is: lit from the first light with a rim toward the edges.
    public static var template: ParticleFunction {
        ParticleFunction(source: """
        [[visible]] float4 rimLight(ShadingInput input, ShadingScene scene, constant ShadingLight *lights, const device ShadingLight *particleLights, constant float4 *parameters) {
            float3 light = scene.ambient;
            if (scene.lightCount > 0) {
                float3 toLight = lights[0].kind == 2 ? normalize(lights[0].position - input.position) : -lights[0].direction;
                light += lights[0].color * max(0.0, dot(input.sphereNormal, toLight));
            }
            // parameters[0].x: how strong the rim is.
            float rim = pow(1 - abs(dot(input.normal, input.toCamera)), 3) * parameters[0].x;
            return float4(input.color.rgb * light + rim, input.color.a);
        }
        """, name: "rimLight", parameters: [[1, 0, 0, 0]])
    }
}

/// The built-in shading models' visible functions: unlit, lit, foil. Linked into every particle render pipeline, so
/// switching between them never compiles a new pipeline.
struct BuiltInShading {
    var unlit: VisibleFunction
    var lit: VisibleFunction
    var foil: VisibleFunction

    var all: [VisibleFunction] { [unlit, lit, foil] }

    subscript(index: Int) -> VisibleFunction { all[index] }

    /// The built-ins plus `custom`, for a pipeline's linked functions.
    func linked(with custom: VisibleFunction?) -> [VisibleFunction] {
        guard let custom, !all.contains(where: { $0.reference == custom.reference }) else {
            return all
        }
        return all + [custom]
    }
}

extension ParticleSystemRuntime {
    /// A particle vertex shader that calls the shading function per vertex, hands it on per pixel, or neither.
    func vertexShader(_ name: String, calls: Bool, perPixel: Bool) throws -> VertexShader {
        var constants = FunctionConstants()
        constants["particleHasShading"] = .bool(calls && !perPixel)
        constants["particleShadesPerPixel"] = .bool(calls && perPixel)
        return try library.function(type: VertexShader.self, named: name, constants: constants)
    }

    /// The particle fragment shader, calling the shading function per pixel or not.
    func fragmentShader(perPixel: Bool) throws -> FragmentShader {
        var constants = FunctionConstants()
        constants["particleShadesPerPixel"] = .bool(perPixel)
        return try library.function(type: FragmentShader.self, named: "particleFragment", constants: constants)
    }

    /// The function `draw` calls per vertex, its parameters, and whether it is called at all. Matches the shading
    /// before #172: foil only when it glints or shifts color, and never on trails and ribbons; unlit sprites, trails,
    /// and ribbons skip the call.
    func shading(for module: ShadingModule?, draw: EmitterDraw) throws -> (function: VisibleFunction, parameters: [SIMD4<Float>], calls: Bool, perPixel: Bool) {
        let shading: (function: VisibleFunction, parameters: [SIMD4<Float>], calls: Bool) = try shadingPerVertex(for: module?.model ?? .unlit, draw: draw)
        // Foil sprites always shade per pixel, so their crinkle breaks the card into facets (#175); foil meshes per vertex.
        let isFoilSprite = shading.function.reference == (try gpuFunctions.builtInShading()).foil.reference && !draw.kind.isMesh
        return (shading.function, shading.parameters, shading.calls, shading.calls && (module?.perPixel == true || isFoilSprite))
    }

    private func shadingPerVertex(for model: ShadingModel, draw: EmitterDraw) throws -> (function: VisibleFunction, parameters: [SIMD4<Float>], calls: Bool) {
        let builtIn = try gpuFunctions.builtInShading()
        let isMesh = draw.kind.isMesh
        let isStrip = draw.kind.isStrip
        switch model {
        case let .custom(function):
            return (try gpuFunctions.shading(function), Self.padded(function.parameters), true)
        case let .foil(foil) where (foil.glint > 0 || foil.iridescence > 0) && !isStrip:
            let parameters: [SIMD4<Float>] = [[max(foil.glint, 0), max(foil.shininess, 1), max(foil.iridescence, 0), 0]]
            return (builtIn.foil, Self.padded(parameters), true)
        case .lit:
            return (builtIn.lit, Self.padded([]), true)
        case .unlit, .foil:
            return (builtIn.unlit, Self.padded([]), isMesh)
        }
    }

    /// At least `ParticleFunction.minimumParameterCount` entries, so functions can read a few past what they were given.
    private static func padded(_ parameters: [SIMD4<Float>]) -> [SIMD4<Float>] {
        parameters + Array(repeating: .zero, count: max(ParticleFunction.minimumParameterCount - parameters.count, 0))
    }
}

public extension ParticleFunction {
    /// Compiles the function as a custom shading function (after `ShadingModule.prelude`).
    func validateShading(device: MTLDevice) throws {
        _ = try GPUFunctions.compileShading(self, device: device)
    }
}
