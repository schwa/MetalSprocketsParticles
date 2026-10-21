import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

// Rendering in two steps (#221): `planDraws` decides everything about each emitter's draw (kind, shader variants,
// shading function and stage, parameters, blend state), and `encode` binds any plan the same way.

/// What an emitter's particles are drawn as. Decided once per draw; every later choice reads it.
enum DrawKind {
    /// One strip through the live window, in birth order (`ParticleEmitter.ribbon`), drawn instead of anything else.
    case ribbon
    /// A small mesh per particle (`ParticleEmitter.particleMesh`).
    case mesh(buffer: MTLBuffer, vertexCount: Int)
    /// A strip per particle through its recent positions (`ParticleEmitter.trail`).
    case trail
    /// A quad per particle.
    case sprite

    var vertexShaderName: String {
        switch self {
        case .ribbon: "particleRibbonVertex"
        case .mesh: "particleMeshVertex"
        case .trail: "particleTrailVertex"
        case .sprite: "particleVertex"
        }
    }

    var isMesh: Bool {
        if case .mesh = self {
            return true
        }
        return false
    }

    /// Ribbons and trails: strips that never get foil.
    var isStrip: Bool {
        switch self {
        case .ribbon, .trail: true
        case .mesh, .sprite: false
        }
    }
}

extension ParticleSystemRuntime {
    /// Every visible emitter's draw, in drawing order: unsorted emitters in emitter order, then sorted emitters
    /// farthest first. Updates the culling camera.
    func planDraws(projection: simd_float4x4, view: simd_float4x4, sceneDepth: MTLTexture?) throws -> [EmitterDraw] {
        let cameraToWorld = view.inverse
        let cameraPosition = cameraToWorld.columns.3.xyz
        cullingCamera = CullingCamera(position: cameraPosition, viewProjection: projection * view)
        let visible = allEmitters.filter { !$0.isOutsideView(camera: cullingCamera) }
        let unsorted = visible.filter { $0.settings.sortMode == .none }
        let sorted = visible.filter { $0.settings.sortMode != .none }
            .sorted { simd_distance($0.worldCenter, cameraPosition) > simd_distance($1.worldCenter, cameraPosition) }
        let lighting = EmitterDraw.Lighting(ambient: ambientLight, lightCount: min(lights.count, Int(PARTICLE_MAX_LIGHTS)), particleLightCount: particleLightCount)
        return try (unsorted + sorted).map { emitter in
            try planDraw(emitter, projection: projection, view: view, lighting: lighting, hasSceneDepth: sceneDepth != nil)
        }
    }

    private func planDraw(_ emitter: Emitter, projection: simd_float4x4, view: simd_float4x4, lighting: EmitterDraw.Lighting, hasSceneDepth: Bool) throws -> EmitterDraw {
        var draw = EmitterDraw(emitter: emitter, projection: projection, view: view, lighting: lighting, hasSceneDepth: hasSceneDepth)
        let settings = emitter.settings
        let mesh = try settings.particleMesh.flatMap(vertexBuffer(for:))
        if mesh != nil {
            // Solid shapes: the fragment shader's procedural dot is fully covered at the center.
            draw.uniforms.hasTexture = 0
        }
        if let image = settings.colorImage, let texture = colorImageTexture(for: image) {
            draw.colorImage = texture
            draw.uniforms.hasColorImage = 1
            draw.uniforms.colorImageOrigin = image.origin
            draw.uniforms.colorImageU = image.width
            draw.uniforms.colorImageV = image.height
        }
        if debugView != .none {
            draw.uniforms.debugMode = debugView.gpuMode
            draw.uniforms.debugEmitterIndex = UInt32(allEmitters.firstIndex { $0 === emitter } ?? 0)
            draw.uniforms.debugSliceStart = UInt32(emitter.range.lowerBound)
            draw.uniforms.debugCapacity = UInt32(emitter.capacity)
            draw.uniforms.debugRange = [debugRange.lowerBound, debugRange.upperBound]
            if let blendMode = debugView.blendMode {
                draw.blendMode = blendMode
                draw.uniforms.blendMode = blendMode
            }
            draw.wireframe = debugView == .wireframe
        }
        if let ribbon = settings.ribbon {
            let window = emitter.liveWindow
            draw.uniforms.ribbonSliceStart = UInt32(emitter.range.lowerBound)
            draw.uniforms.ribbonCapacity = UInt32(emitter.capacity)
            draw.uniforms.ribbonWindowStart = UInt32(window.start)
            draw.uniforms.ribbonWindowCount = UInt32(window.count)
            draw.uniforms.ribbonTapers = ribbon.tapers ? 1 : 0
        }
        if let trail = settings.trail, trails != nil, trailStride > 0 {
            draw.uniforms.trailPointCount = UInt32(min(trail.clampedPointCount, trailStride))
            draw.uniforms.trailStride = UInt32(trailStride)
            draw.uniforms.trailTapers = trail.tapers ? 1 : 0
            draw.uniforms.trailFades = trail.fades ? 1 : 0
        }
        // A ribbon wins over a mesh, and a mesh over a trail.
        if settings.ribbon != nil {
            draw.kind = .ribbon
        } else if let mesh {
            draw.kind = .mesh(buffer: mesh.buffer, vertexCount: mesh.vertexCount)
        } else if draw.uniforms.trailPointCount > 1 {
            draw.kind = .trail
        }
        let shading = try shading(for: settings, draw: draw)
        // Draws that skip the call use the vertex shader variant without it, and link and bind nothing, so their
        // pipelines are what they were before #172.
        draw.shading = shading.calls ? shading.function : nil
        draw.shadingParameters = shading.calls ? shading.parameters : [.zero]
        draw.shadingStage = shading.perPixel ? .fragment : .vertex
        draw.vertexShader = try vertexShader(draw.kind.vertexShaderName, calls: shading.calls, perPixel: shading.perPixel)
        draw.fragmentShader = try fragmentShader(perPixel: shading.perPixel)
        return draw
    }

    /// Binds and draws `draws`.
    func encode(_ draws: [EmitterDraw], sceneDepth: MTLTexture?) throws -> some Element {
        let builtInShading = try gpuFunctions.builtInShading()
        let depthCompare = depthCompareFunction
        let trailBuffer = trails ?? placeholderMesh.vertices
        let lightData = lights.prefix(Int(PARTICLE_MAX_LIGHTS)).map(ParticleLightData.init)
        let buffer = buffer
        let placeholderTexture = placeholderTexture
        let placeholderSortRecords = placeholderSortRecords
        let particleLightBuffer = particleLightBuffer
        let sampler = sampler
        // Never bind an empty array; lightCount keeps the padding unused.
        let lightValues = lightData.isEmpty ? [ParticleLightData()] : lightData

        // One modifier for all parameters: each .parameter is a modifier the frame walks and copies, and long chains
        // cost CPU time every frame.
        func parameters(_ parameters: inout ShaderParameters, _ draw: EmitterDraw) {
            parameters.set("particles", buffer: buffer)
            parameters.set("colorImage", texture: draw.colorImage ?? placeholderTexture)
            parameters.set("uniforms", value: draw.uniforms)
            parameters.set("colorCurve", values: draw.colorCurve)
            parameters.set("sizeCurve", values: draw.sizeCurve)
            parameters.set("extraColorCurves", values: draw.extraColorCurves)
            parameters.set("spriteSampler", samplerState: sampler)
            parameters.set("lights", values: lightValues)
            parameters.set("particleLights", buffer: particleLightBuffer)
            parameters.set("shadingParameters", values: draw.shadingParameters)
            parameters.set("sceneDepth", texture: sceneDepth ?? placeholderTexture)
            switch draw.kind {
            case .ribbon:
                parameters.set("sprite", texture: draw.texture ?? placeholderTexture)
            case let .mesh(meshBuffer, _):
                parameters.set("meshVertices", buffer: meshBuffer)
                parameters.set("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
                parameters.set("sprite", texture: placeholderTexture)
            case .trail:
                parameters.set("trails", buffer: trailBuffer)
                parameters.set("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
                parameters.set("sprite", texture: draw.texture ?? placeholderTexture)
            case .sprite:
                parameters.set("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
                parameters.set("sprite", texture: draw.texture ?? placeholderTexture)
            }
        }

        func pipeline(_ draw: EmitterDraw) throws -> some Element {
            try RenderPipeline(
                vertexShader: try draw.vertexShader.orThrow(.resourceCreationFailure("Particle vertex shader")),
                fragmentShader: try draw.fragmentShader.orThrow(.resourceCreationFailure("Particle fragment shader"))
            ) {
                Draw { encoder in
                    encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill)
                    draw.drawPrimitives(encoder)
                }
            }
            .parameters { parameters(&$0, draw) }
            .visibleFunctionTable("shadingFunction", functionType: draw.shadingStage, functions: draw.shading.map { [$0] } ?? [])
            .linkedFunctions(draw.shading == nil ? [] : builtInShading.linked(with: draw.shading), functionType: draw.shadingStage)
        }

        return ForEach(Array(draws.indices), id: \.self) { index in
            let draw = draws[index]
            if draw.kind.isMesh {
                // Shapes hide each other; only opaque ones write depth, so blended ones still show what is behind.
                try pipeline(draw)
                    .depthCompare(function: depthCompare, writes: draw.blendMode == .opaque)
                    .renderPipelineDescriptorTransformer { descriptor in
                        if let attachment = descriptor.colorAttachments[0] {
                            draw.blendMode.configure(attachment)
                        }
                    }
            } else {
                try pipeline(draw)
                    .renderPipelineDescriptorTransformer { descriptor in
                        if let attachment = descriptor.colorAttachments[0] {
                            draw.blendMode.configure(attachment)
                        }
                    }
            }
        }
    }
}

extension EmitterDraw {
    /// The draw call for this kind: one strip, or instances over the live window's segments.
    func drawPrimitives(_ encoder: any MTL4RenderCommandEncoder) {
        switch kind {
        case .ribbon:
            let count = Int(uniforms.ribbonWindowCount)
            if count > 1 {
                encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: count * 2, instanceCount: 1, baseInstance: 0)
            }
        case let .mesh(_, vertexCount):
            for segment in segments where segment.count > 0 {
                encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: vertexCount, instanceCount: segment.count, baseInstance: segment.start)
            }
        case .trail:
            for segment in segments where segment.count > 0 {
                encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: Int(uniforms.trailPointCount) * 2, instanceCount: segment.count, baseInstance: segment.start)
            }
        case .sprite:
            for segment in segments where segment.count > 0 {
                encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segment.count, baseInstance: segment.start)
            }
        }
    }
}
