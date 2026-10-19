import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

/// A depth texture that particle shaders can read, for soft particles. Fill it each frame with
/// `ParticleSystemRuntime.renderSceneDepth(into:projection:view:)`, then pass `texture` to
/// `ParticleSystemRuntime.render(projection:view:sceneDepth:)`. It must be the same size as the render target.
public final class SceneDepth {
    /// Depth-buffer values as `r32Float` colors, readable by the particle fragment shader.
    public let texture: MTLTexture
    /// The depth attachment the depth pass tests against.
    let depthAttachment: MTLTexture

    public var width: Int { texture.width }
    public var height: Int { texture.height }

    public init(device: MTLDevice, width: Int, height: Int) throws {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: max(width, 1), height: max(height, 1), mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: max(width, 1), height: max(height, 1), mipmapped: false)
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: colorDescriptor), let depthAttachment = device.makeTexture(descriptor: depthDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        texture.label = "Scene Depth"
        depthAttachment.label = "Scene Depth Attachment"
        self.texture = texture
        self.depthAttachment = depthAttachment
    }
}

/// A scene depth and the camera that drew it, for `ParticleEmitter.collidesWithSceneDepth`.
public struct SceneDepthCollision {
    public var depth: SceneDepth
    public var projection: simd_float4x4
    public var view: simd_float4x4
    /// Particles more than this far behind a surface count as behind the object, not inside it. Thinner than your
    /// thinnest object, thicker than particles move in a step.
    public var thickness: Float

    public init(depth: SceneDepth, projection: simd_float4x4, view: simd_float4x4, thickness: Float = 0.5) {
        self.depth = depth
        self.projection = projection
        self.view = view
        self.thickness = thickness
    }

    var data: DepthCollisionData {
        let viewProjection = projection * view
        return DepthCollisionData(
            viewProjection: viewProjection,
            inverseViewProjection: viewProjection.inverse,
            cameraPosition: view.inverse.columns.3.xyz,
            size: [UInt32(depth.width), UInt32(depth.height)],
            thickness: max(thickness, 0),
            enabled: 1
        )
    }
}

extension ParticleSystemRuntime {
    /// The colliders' solid triangles, made again only when the colliders change. Tessellating spheres and capsules
    /// is too slow to do for every pass of every frame (#130).
    func colliderSolidVertices(planeExtent: Float) -> [SIMD4<Float>] {
        if let cached = solidVertexCache, cached.colliders == colliders, cached.planeExtent == planeExtent {
            return cached.vertices
        }
        let vertices = colliders.flatMap { $0.solidVertices(planeExtent: planeExtent) }
        solidVertexCache = (colliders, planeExtent, vertices)
        return vertices
    }
}

public extension ParticleSystemRuntime {
    /// Draws the colliders as shaded solids, depth-tested and writing depth. Place inside a `RenderPass` that has a
    /// depth attachment, before `render`. Planes are drawn as squares `planeExtent` units from their closest point to
    /// the origin.
    func renderColliderSolids(projection: simd_float4x4, view: simd_float4x4, color: SIMD3<Float> = [0.1, 0.11, 0.13], planeExtent: Float = 6) throws -> some Element {
        let vertices = colliderSolidVertices(planeExtent: planeExtent)
        return try solids(vertices, fragmentShader: library.solidFragment, uniforms: WireframeUniforms(viewProjection: projection * view, color: SIMD4(color, 1)))
            .depthCompare(function: .less, writes: true)
    }

    /// A whole frame after `simulate`: with `sceneDepth`, a pass that fills it and solid colliders; then wireframes if
    /// asked; then the particles. Place at the top level of a frame, not inside a `RenderPass`.
    func renderScene(projection: simd_float4x4, view: simd_float4x4, sceneDepth: SceneDepth? = nil, wireframes: Bool = false) throws -> some Element {
        try Group {
            if let sceneDepth {
                try renderSceneDepth(into: sceneDepth, projection: projection, view: view)
            }
            try RenderPass {
                if sceneDepth != nil {
                    try renderColliderSolids(projection: projection, view: view)
                }
                if wireframes {
                    try renderWireframes(projection: projection, view: view)
                }
                try render(projection: projection, view: view, sceneDepth: sceneDepth?.texture)
            }
        }
    }

    /// A complete render pass that draws the colliders' depth into `sceneDepth`. Run it before the pass that draws the
    /// particles, with the same `projection` and `view`.
    func renderSceneDepth(into sceneDepth: SceneDepth, projection: simd_float4x4, view: simd_float4x4, planeExtent: Float = 6) throws -> some Element {
        // The next simulate collides with this depth (one frame late).
        collisionDepth = SceneDepthCollision(depth: sceneDepth, projection: projection, view: view, thickness: collisionDepth?.thickness ?? 0.5)
        let vertices = colliderSolidVertices(planeExtent: planeExtent)
        let uniforms = WireframeUniforms(viewProjection: projection * view, color: .one)
        return try RenderPass(label: "Scene Depth") {
            try solids(vertices, fragmentShader: library.solidDepthFragment, uniforms: uniforms)
                .depthCompare(function: .less, writes: true)
        }
        .renderPassDescriptorModifier { descriptor in
            for index in 1..<8 {
                descriptor.colorAttachments[index]?.texture = nil
            }
            descriptor.colorAttachments[0]?.texture = sceneDepth.texture
            descriptor.colorAttachments[0]?.resolveTexture = nil
            descriptor.colorAttachments[0]?.loadAction = .clear
            // Depth 1 is the far plane: nothing in front, so particles there are not softened.
            descriptor.colorAttachments[0]?.clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
            descriptor.colorAttachments[0]?.storeAction = .store
            descriptor.depthAttachment.texture = sceneDepth.depthAttachment
            descriptor.depthAttachment.resolveTexture = nil
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.clearDepth = 1
            descriptor.depthAttachment.storeAction = .dontCare
            descriptor.stencilAttachment.texture = nil
        }
    }
}

extension ParticleSystemRuntime {
    /// Draws interleaved (position, normal) triangle-list `vertices`.
    func solids(_ vertices: [SIMD4<Float>], fragmentShader: FragmentShader, uniforms: WireframeUniforms) throws -> some Element {
        try RenderPipeline(vertexShader: library.solidVertex, fragmentShader: fragmentShader) {
            Draw { encoder in
                if !vertices.isEmpty {
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: vertices.count / 2)
                }
            }
        }
        .parameter("vertices", values: vertices.isEmpty ? [.zero, .zero] : vertices)
        .parameter("uniforms", value: uniforms)
    }
}

extension Collider {
    /// Triangle-list vertices as interleaved (position, normal) pairs.
    func solidVertices(planeExtent: Float) -> [SIMD4<Float>] {
        var builder = SolidBuilder()
        switch shape {
        case let .plane(normal, distance):
            let n = simd_normalize(normal)
            let helper: SIMD3<Float> = abs(n.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(helper, n)) * planeExtent
            let v = simd_cross(n, simd_normalize(u)) * planeExtent
            let origin = n * distance
            builder.quad(origin - u - v, origin + u - v, origin + u + v, origin - u + v, normal: n)
        case let .sphere(center, radius):
            builder.sphere(center: center, radius: radius)
        case let .box(center, halfExtents, rotation):
            for axis in 0..<3 {
                for sign in [Float(-1), 1] {
                    var normal = SIMD3<Float>.zero
                    normal[axis] = sign
                    let a = (axis + 1) % 3
                    let b = (axis + 2) % 3
                    func corner(_ x: Float, _ y: Float) -> SIMD3<Float> {
                        var local = SIMD3<Float>.zero
                        local[axis] = sign * halfExtents[axis]
                        local[a] = x * halfExtents[a]
                        local[b] = y * halfExtents[b]
                        return center + rotation.act(local)
                    }
                    builder.quad(corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1), normal: rotation.act(normal))
                }
            }
        case let .capsule(start, end, radius):
            builder.sphere(center: start, radius: radius)
            builder.sphere(center: end, radius: radius)
            builder.cylinder(from: start, to: end, radius: radius)
        }
        return builder.vertices
    }
}

/// Collects triangles. Winding is not used: solids draw without culling.
struct SolidBuilder {
    var vertices: [SIMD4<Float>] = []

    mutating func triangle(_ points: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        for (point, normal) in zip(points, normals) {
            vertices.append(SIMD4(point, 1))
            vertices.append(SIMD4(normal, 0))
        }
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal: SIMD3<Float>) {
        triangle([a, b, c], normals: [normal, normal, normal])
        triangle([a, c, d], normals: [normal, normal, normal])
    }

    mutating func sphere(center: SIMD3<Float>, radius: Float, rings: Int = 16, segments: Int = 32) {
        func point(_ ring: Int, _ segment: Int) -> SIMD3<Float> {
            let theta = Float(ring) / Float(rings) * .pi
            let phi = Float(segment) / Float(segments) * 2 * .pi
            return [sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)]
        }
        for ring in 0..<rings {
            for segment in 0..<segments {
                let normals = [point(ring, segment), point(ring + 1, segment), point(ring + 1, segment + 1), point(ring, segment + 1)]
                let points = normals.map { center + $0 * radius }
                triangle([points[0], points[1], points[2]], normals: [normals[0], normals[1], normals[2]])
                triangle([points[0], points[2], points[3]], normals: [normals[0], normals[2], normals[3]])
            }
        }
    }

    mutating func cylinder(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, segments: Int = 32) {
        let axis = end - start
        guard simd_length(axis) > 0 else {
            return
        }
        let direction = simd_normalize(axis)
        let helper: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = simd_normalize(simd_cross(helper, direction))
        let v = simd_cross(direction, u)
        func normal(_ segment: Int) -> SIMD3<Float> {
            let angle = Float(segment) / Float(segments) * 2 * .pi
            return u * cos(angle) + v * sin(angle)
        }
        for segment in 0..<segments {
            let (n0, n1) = (normal(segment), normal(segment + 1))
            let points = [start + n0 * radius, end + n0 * radius, end + n1 * radius, start + n1 * radius]
            triangle([points[0], points[1], points[2]], normals: [n0, n0, n1])
            triangle([points[0], points[2], points[3]], normals: [n0, n1, n1])
        }
    }
}
