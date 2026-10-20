import Metal
import simd
import SwiftMesh

/// A small 3D shape drawn for each particle instead of a sprite (`ParticleEmitter.particleMesh`): debris, coins, thick
/// confetti. The particle's size scales it (shapes span about -1...1), its color tints it, and each particle tumbles
/// about its own random axis by its rotation angle. Lit emitters shade it with real normals; unlit ones get a little
/// camera-facing shading so the shape reads.
public enum ParticleMesh: Sendable, Hashable, Codable {
    case cube
    case tetrahedron
    /// A flat cylinder, like a coin.
    case coin
    /// Flat triangle list: three positions per triangle, with one normal per position.
    case triangles(positions: [SIMD3<Float>], normals: [SIMD3<Float>])

    /// A SwiftMesh mesh, triangulated, with flat normals.
    public init(mesh: Mesh) {
        let triangles = mesh.triangulate().map { triangle in
            (mesh.positions[triangle.0.raw], mesh.positions[triangle.1.raw], mesh.positions[triangle.2.raw])
        }
        self = Self.flat(triangles)
    }

    /// Interleaved position and normal (each a float4), three vertices per triangle.
    var vertices: [SIMD4<Float>] {
        let (positions, normals) = geometry
        return zip(positions, normals).flatMap { position, normal in
            [SIMD4(position, 1), SIMD4(simd_length(normal) > 0 ? simd_normalize(normal) : [0, 1, 0], 0)]
        }
    }

    private var geometry: (positions: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        switch self {
        case .cube:
            return Self.flat(Self.cubeTriangles, outward: true).geometry
        case .tetrahedron:
            let a: SIMD3<Float> = [1, 1, 1]
            let b: SIMD3<Float> = [1, -1, -1]
            let c: SIMD3<Float> = [-1, 1, -1]
            let d: SIMD3<Float> = [-1, -1, 1]
            return Self.flat([(a, b, c), (a, d, b), (a, c, d), (b, d, c)], outward: true).geometry
        case .coin:
            return Self.coinGeometry(segments: 16, radius: 1, halfThickness: 0.15)
        case let .triangles(positions, normals):
            let count = min(positions.count, normals.count) / 3 * 3
            return (Array(positions.prefix(count)), Array(normals.prefix(count)))
        }
    }

    /// `outward` points each normal away from the origin, for convex shapes centered on it, whatever the winding.
    private static func flat(_ triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)], outward: Bool = false) -> Self {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for (a, b, c) in triangles {
            var normal = simd_cross(b - a, c - a)
            if outward, simd_dot(normal, a + b + c) < 0 {
                normal = -normal
            }
            positions += [a, b, c]
            normals += Array(repeating: normal, count: 3)
        }
        return .triangles(positions: positions, normals: normals)
    }

    private static var cubeTriangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        // Each face: its normal axis, and two axes spanning it, ordered so the winding faces out.
        for axis in 0..<3 {
            for sign: Float in [-1, 1] {
                var normal = SIMD3<Float>.zero
                normal[axis] = sign
                var u = SIMD3<Float>.zero
                u[(axis + 1) % 3] = 1
                var v = SIMD3<Float>.zero
                v[(axis + 2) % 3] = 1
                if sign < 0 {
                    swap(&u, &v)
                }
                let corners = [normal - u - v, normal + u - v, normal + u + v, normal - u + v]
                triangles += [(corners[0], corners[1], corners[2]), (corners[0], corners[2], corners[3])]
            }
        }
        return triangles
    }

    private static func coinGeometry(segments: Int, radius: Float, halfThickness: Float) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        func point(_ index: Int, _ y: Float) -> SIMD3<Float> {
            let angle = Float(index) / Float(segments) * 2 * .pi
            return [cos(angle) * radius, y, sin(angle) * radius]
        }
        for index in 0..<segments {
            let top0 = point(index, halfThickness)
            let top1 = point(index + 1, halfThickness)
            let bottom0 = point(index, -halfThickness)
            let bottom1 = point(index + 1, -halfThickness)
            // Faces, then the rim with smooth normals.
            positions += [[0, halfThickness, 0], top1, top0, [0, -halfThickness, 0], bottom0, bottom1]
            normals += Array(repeating: [0, 1, 0], count: 3) + Array(repeating: [0, -1, 0], count: 3)
            let n0 = SIMD3(top0.x, 0, top0.z)
            let n1 = SIMD3(top1.x, 0, top1.z)
            positions += [top0, top1, bottom1, top0, bottom1, bottom0]
            normals += [n0, n1, n1, n0, n1, n0]
        }
        return (positions, normals)
    }
}

/// Built-in shapes keep the synthesized form (`{"cube": {}}`); `triangles` is a PLY file next to the effect's JSON
/// (see EffectResources), `{"triangles": "particle-mesh-<hash>.ply"}`. Inline triangles are not read (#169, #181).
extension ParticleMesh {
    private enum CodingKeys: String, CodingKey {
        case cube, tetrahedron, coin, triangles
    }

    private enum NoKeys: CodingKey {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.triangles) {
            guard (try? container.decode(String.self, forKey: .triangles)) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .triangles, in: container,
                    debugDescription: "Inline particle meshes are not read; effects keep them in PLY files next to their JSON."
                )
            }
            let (positions, normals) = try ParticleMeshFile.triangles(from: container.decodeResource(forKey: .triangles, decoder: decoder))
            self = .triangles(positions: positions, normals: normals)
        } else if container.contains(.cube) {
            self = .cube
        } else if container.contains(.tetrahedron) {
            self = .tetrahedron
        } else if container.contains(.coin) {
            self = .coin
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected cube, tetrahedron, coin, or triangles"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cube:
            _ = container.nestedContainer(keyedBy: NoKeys.self, forKey: .cube)
        case .tetrahedron:
            _ = container.nestedContainer(keyedBy: NoKeys.self, forKey: .tetrahedron)
        case .coin:
            _ = container.nestedContainer(keyedBy: NoKeys.self, forKey: .coin)
        case let .triangles(positions, normals):
            let data = try ParticleMeshFile.plyData(positions: positions, normals: normals)
            try container.encodeResource(data, forKey: .triangles, encoder: encoder, prefix: "particle-mesh", fileExtension: "ply")
        }
    }
}

extension ParticleSystemRuntime {
    /// The GPU vertices for `mesh`, made once per system.
    func vertexBuffer(for mesh: ParticleMesh) throws -> (buffer: MTLBuffer, vertexCount: Int)? {
        if let cached = particleMeshBuffers[mesh] {
            return cached
        }
        let vertices = mesh.vertices
        guard !vertices.isEmpty else {
            return nil
        }
        let buffer = try EmitterMesh.makeBuffer(device: device, vertices, label: "Particle mesh")
        let entry = (buffer, vertices.count / 2)
        particleMeshBuffers[mesh] = entry
        return entry
    }
}
