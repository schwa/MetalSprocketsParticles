import Foundation
import Metal
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh

/// The region particles are born in, in emitter space and centered on `ParticleEmitter.position`. Shapes with an axis
/// use +Y.
public enum EmitterShape: Sendable, Equatable, Codable {
    case point
    case sphere(radius: Float)
    case box(size: SIMD3<Float>)
    /// A rectangle in the XZ plane facing +Y.
    case plane(size: SIMD2<Float>)
    /// A disc in the XZ plane facing +Y. Surface means the rim.
    case disc(radius: Float)
    /// Centered on the origin along Y. Surface means the side.
    case cylinder(radius: Float, height: Float)
    /// Base at y = 0, apex at y = `height`. Surface means the slanted side.
    case cone(radius: Float, height: Float)
    /// A ring in the XZ plane with tube radius `tubeRadius`.
    case torus(radius: Float, tubeRadius: Float)
    /// The emitter's `ParticleSystem.Emitter.mesh`. Volume emission falls back to the surface.
    case mesh
}

extension ParticleShapeData {
    /// The shader's view of an emitter's shape and birth settings. `mesh` supplies counts for `EmitterShape.mesh`.
    init(_ settings: ParticleEmitter, mesh: EmitterMesh?) {
        self.init()
        kind = settings.shape.kind
        birthLocation = settings.birthLocation
        birthDirection = settings.birthDirection
        sweep = max(settings.sweepAngle, 0)
        center = settings.position
        switch settings.shape {
        case .point:
            break
        case .mesh:
            meshTriangleCount = UInt32(mesh?.triangleCount ?? 0)
            meshVertexCount = UInt32(mesh?.vertexCount ?? 0)
            deformedPositionOffset = UInt32(mesh?.deformedPositionOffset ?? 0)
            deformedPositionStride = UInt32(mesh?.deformedPositionStride ?? 0)
        case let .sphere(radius), let .disc(radius):
            self.radius = radius
        case let .box(size):
            self.size = size
        case let .plane(size):
            self.size = [size.x, 0, size.y]
        case let .cylinder(radius, height), let .cone(radius, height):
            self.radius = radius
            self.height = height
        case let .torus(radius, tubeRadius):
            self.radius = radius
            self.tubeRadius = tubeRadius
        }
    }
}

/// Triangles to emit from, uploaded once. Assign to `ParticleSystem.Emitter.mesh` and use `EmitterShape.mesh`.
///
/// For morphing or skinned meshes, keep the rest-pose mesh and call `setDeformedPositions` with each frame's deformed
/// vertex buffer. Particles are then placed on the deformed triangles, chosen by rest-pose area.
public final class EmitterMesh {
    let triangles: MTLBuffer
    let vertices: MTLBuffer
    /// Triangle-list indices, three per triangle, for reading deformed positions.
    let indices: MTLBuffer
    public let triangleCount: Int
    public let vertexCount: Int

    /// Current positions, replacing the rest positions; nil uses the rest pose.
    public private(set) var deformedPositions: MTLBuffer?
    private(set) var deformedPositionOffset = 0
    private(set) var deformedPositionStride = 0

    /// Emits from deformed positions: packed float3s at `offset + stride * vertex` in `buffer`, one per rest vertex, in
    /// the same space as the rest positions (world space for meshes skinned into world space; use an identity emitter
    /// transform). The buffer is read when the simulation runs, so do not overwrite it while frames using it are in
    /// flight; give each frame its own buffer or wait for completion. Pass nil to return to the rest pose.
    public func setDeformedPositions(_ buffer: MTLBuffer?, offset: Int = 0, stride: Int = MemoryLayout<Float>.stride * 3) {
        precondition(buffer == nil || (stride >= 12 && offset >= 0), "Deformed positions need a stride of at least 12 bytes")
        precondition(buffer.map { $0.length >= offset + stride * max(vertexCount - 1, 0) + 12 } ?? true, "Deformed position buffer too short for \(vertexCount) vertices")
        deformedPositions = buffer
        deformedPositionOffset = buffer == nil ? 0 : offset
        deformedPositionStride = buffer == nil ? 0 : stride
    }

    /// `indices` are triangle-list indices into `positions`, in emitter space.
    public init(device: MTLDevice, positions: [SIMD3<Float>], indices: [UInt32]) throws {
        let triangleCount = indices.count / 3
        var triangles: [EmitterMeshTriangle] = []
        triangles.reserveCapacity(triangleCount)
        var total: Float = 0
        for index in 0..<triangleCount {
            let a = positions[Int(indices[index * 3])]
            let b = positions[Int(indices[index * 3 + 1])]
            let c = positions[Int(indices[index * 3 + 2])]
            total += simd_length(simd_cross(b - a, c - a)) / 2
            triangles.append(EmitterMeshTriangle(a: SIMD4(a, total), b: SIMD4(b, 0), c: SIMD4(c, 0)))
        }
        // Normalize cumulative areas; force the last to exactly 1 so the search always finds a triangle.
        for index in triangles.indices {
            triangles[index].a.w = total > 0 ? triangles[index].a.w / total : Float(index + 1) / Float(triangleCount)
        }
        if !triangles.isEmpty {
            triangles[triangles.count - 1].a.w = 1
        }
        self.triangleCount = triangleCount
        vertexCount = positions.count
        self.triangles = try Self.makeBuffer(device: device, triangles.isEmpty ? [EmitterMeshTriangle()] : triangles, label: "Emitter mesh triangles")
        self.indices = try Self.makeBuffer(device: device, indices.isEmpty ? [UInt32(0)] : Array(indices.prefix(triangleCount * 3)), label: "Emitter mesh indices")
        vertices = try Self.makeBuffer(device: device, positions.isEmpty ? [SIMD4<Float>.zero] : positions.map { SIMD4($0, 1) }, label: "Emitter mesh vertices")
    }

    /// Emits from a SwiftMesh mesh. Polygon faces, including faces with holes, are triangulated; positions are in
    /// emitter space.
    public convenience init(device: MTLDevice, mesh: Mesh) throws {
        let indices = mesh.triangulate().flatMap { triangle in
            [UInt32(triangle.0.raw), UInt32(triangle.1.raw), UInt32(triangle.2.raw)]
        }
        try self.init(device: device, positions: mesh.positions, indices: indices)
    }

    static func makeBuffer<T>(device: MTLDevice, _ values: [T], label: String) throws -> MTLBuffer {
        guard let buffer = values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.label = label
        return buffer
    }
}
