import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

/// Collects line-list vertices (pairs) for debug wireframes.
struct WireframeBuilder {
    var vertices: [SIMD4<Float>] = []
    /// Applied to every point added.
    var transform = matrix_identity_float4x4

    mutating func line(_ start: SIMD3<Float>, _ end: SIMD3<Float>) {
        vertices.append(transform * SIMD4(start, 1))
        vertices.append(transform * SIMD4(end, 1))
    }

    /// A circle around `center` in the plane spanned by unit vectors `u` and `v`.
    mutating func circle(_ center: SIMD3<Float>, radius: Float, u: SIMD3<Float> = [1, 0, 0], v: SIMD3<Float> = [0, 0, 1], segments: Int = 48) {
        for index in 0..<segments {
            let a = Float(index) / Float(segments) * 2 * .pi
            let b = Float(index + 1) / Float(segments) * 2 * .pi
            line(center + (u * cos(a) + v * sin(a)) * radius, center + (u * cos(b) + v * sin(b)) * radius)
        }
    }

    /// Three great circles.
    mutating func sphere(_ center: SIMD3<Float>, radius: Float) {
        circle(center, radius: radius, u: [1, 0, 0], v: [0, 1, 0])
        circle(center, radius: radius, u: [1, 0, 0], v: [0, 0, 1])
        circle(center, radius: radius, u: [0, 1, 0], v: [0, 0, 1])
    }

    mutating func box(_ center: SIMD3<Float>, halfExtents: SIMD3<Float>) {
        let corners = (0..<8).map { index in
            center + halfExtents * SIMD3<Float>(index & 1 == 0 ? -1 : 1, index & 2 == 0 ? -1 : 1, index & 4 == 0 ? -1 : 1)
        }
        // Corners differing in exactly one bit share an edge.
        for a in 0..<8 {
            for bit in [1, 2, 4] where a & bit == 0 {
                line(corners[a], corners[a | bit])
            }
        }
    }

    /// A line with a small two-feathered head at `end`.
    mutating func arrow(_ start: SIMD3<Float>, _ end: SIMD3<Float>) {
        line(start, end)
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0 else {
            return
        }
        let forward = direction / length
        let side = Self.perpendicular(to: forward)
        let head = min(length * 0.25, 0.2)
        line(end, end - forward * head + side * head * 0.5)
        line(end, end - forward * head - side * head * 0.5)
    }

    mutating func cross(_ center: SIMD3<Float>, size: Float) {
        line(center - [size, 0, 0], center + [size, 0, 0])
        line(center - [0, size, 0], center + [0, size, 0])
        line(center - [0, 0, size], center + [0, 0, size])
    }

    static func perpendicular(to direction: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        return simd_normalize(simd_cross(helper, direction))
    }
}

extension ForceField {
    /// Wind: an arrow along the wind above the origin. Attractor: a cross at the center and its radius. Vortex: rings
    /// around the axis with arrows showing the direction of spin. Turbulence fills all space and draws nothing.
    func addWireframe(to builder: inout WireframeBuilder) {
        switch self {
        case let .wind(velocity, _):
            guard simd_length(velocity) > 0 else {
                return
            }
            let direction = simd_normalize(velocity)
            for offset: SIMD3<Float> in [[0, 1, 0], [0, 2, 0], [0, 3, 0]] {
                builder.arrow(offset - direction * 0.5, offset + direction * 0.5)
            }
        case let .attractor(center, _, radius):
            builder.cross(center, size: 0.15)
            if radius > 0 {
                builder.sphere(center, radius: radius)
            }
        case let .vortex(center, axis, strength, radius):
            let up = simd_length(axis) > 0 ? simd_normalize(axis) : [0, 1, 0]
            let u = WireframeBuilder.perpendicular(to: up)
            let v = simd_cross(up, u)
            let ring = radius > 0 ? radius : 1
            builder.arrow(center - up * ring * 0.5, center + up * ring * 0.5)
            for scale: Float in [0.5, 1] {
                builder.circle(center, radius: ring * scale, u: u, v: v)
            }
            // Tangent arrows on the outer ring, pointing the way particles are swept.
            let spin: Float = strength >= 0 ? 1 : -1
            for index in 0..<4 {
                let angle = Float(index) * .pi / 2
                let point = center + (u * cos(angle) + v * sin(angle)) * ring
                let tangent = (-u * sin(angle) + v * cos(angle)) * spin
                builder.arrow(point, point + tangent * 0.3)
            }
        case .turbulence:
            break
        }
    }
}

extension TriggerVolume {
    func addWireframe(to builder: inout WireframeBuilder) {
        switch self {
        case let .sphere(center, radius): builder.sphere(center, radius: radius)
        case let .box(center, halfExtents): builder.box(center, halfExtents: halfExtents)
        }
    }
}

extension EmitterShape {
    /// The shape outline in emitter space around `center`. Mesh shapes draw only a cross at the center.
    func addWireframe(to builder: inout WireframeBuilder, center: SIMD3<Float>) {
        switch self {
        case .point, .mesh:
            builder.cross(center, size: 0.1)
        case let .sphere(radius):
            builder.sphere(center, radius: radius)
        case let .box(size):
            builder.box(center, halfExtents: size / 2)
        case let .plane(size):
            builder.box(center, halfExtents: [size.x / 2, 0, size.y / 2])
        case let .disc(radius):
            builder.circle(center, radius: radius)
        case let .cylinder(radius, height):
            let half: SIMD3<Float> = [0, height / 2, 0]
            builder.circle(center - half, radius: radius)
            builder.circle(center + half, radius: radius)
            for side: SIMD3<Float> in [[1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1]] {
                builder.line(center - half + side * radius, center + half + side * radius)
            }
        case let .cone(radius, height):
            builder.circle(center, radius: radius)
            for side: SIMD3<Float> in [[1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1]] {
                builder.line(center + side * radius, center + [0, height, 0])
            }
        case let .torus(radius, tubeRadius):
            builder.circle(center, radius: radius + tubeRadius)
            builder.circle(center, radius: max(radius - tubeRadius, 0))
            for index in 0..<4 {
                let angle = Float(index) * .pi / 2
                let outward = SIMD3<Float>(cos(angle), 0, sin(angle))
                builder.circle(center + outward * radius, radius: tubeRadius, u: outward, v: [0, 1, 0], segments: 16)
            }
        }
    }
}

/// Which debug wireframes `ParticleSystem.renderWireframes` draws.
public struct WireframeOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let colliders = Self(rawValue: 1 << 0)
    public static let forceFields = Self(rawValue: 1 << 1)
    public static let triggerVolumes = Self(rawValue: 1 << 2)
    public static let emitters = Self(rawValue: 1 << 3)
    public static let all: Self = [.colliders, .forceFields, .triggerVolumes, .emitters]
}

public extension ParticleSystem {
    /// Draws debug wireframes: colliders (blue), force fields (magenta), trigger volumes (green), and emitter shapes at
    /// their current transforms (yellow). Place inside a `RenderPass`.
    func renderWireframes(projection: simd_float4x4, view: simd_float4x4, options: WireframeOptions = .all) throws -> some Element {
        var forceFieldLines = WireframeBuilder()
        var triggerLines = WireframeBuilder()
        var emitterLines = WireframeBuilder()
        if options.contains(.forceFields) {
            for field in forceFields {
                field.addWireframe(to: &forceFieldLines)
            }
        }
        if options.contains(.triggerVolumes) {
            for volume in triggerVolumes {
                volume.addWireframe(to: &triggerLines)
            }
        }
        if options.contains(.emitters) {
            for emitter in emitters {
                emitterLines.transform = emitter.transform
                emitter.settings.shape.addWireframe(to: &emitterLines, center: emitter.settings.position)
            }
        }
        let colliderLines = options.contains(.colliders) ? colliders.flatMap(\.wireframe) : []
        let viewProjection = projection * view
        return try Group {
            try wireframe(colliderLines, color: [0.4, 0.6, 1, 1], viewProjection: viewProjection)
            try wireframe(forceFieldLines.vertices, color: [1, 0.35, 0.9, 1], viewProjection: viewProjection)
            try wireframe(triggerLines.vertices, color: [0.3, 1, 0.4, 1], viewProjection: viewProjection)
            try wireframe(emitterLines.vertices, color: [1, 0.9, 0.3, 1], viewProjection: viewProjection)
        }
    }
}

extension ParticleSystem {
    /// Draws line-list `vertices` in one flat color.
    func wireframe(_ vertices: [SIMD4<Float>], color: SIMD4<Float>, viewProjection: simd_float4x4) throws -> some Element {
        try RenderPipeline(vertexShader: library.wireframeVertex, fragmentShader: library.wireframeFragment) {
            Draw { encoder in
                if !vertices.isEmpty {
                    encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: vertices.count)
                }
            }
        }
        .parameter("vertices", values: vertices.isEmpty ? [.zero] : vertices)
        .parameter("uniforms", value: WireframeUniforms(viewProjection: viewProjection, color: color))
    }
}
