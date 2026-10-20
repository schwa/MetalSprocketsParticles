import Foundation
import simd
import SwiftPLY

/// Custom particle meshes (`ParticleMesh.triangles`) in PLY files (#181): a `vertex` element with float
/// `x y z nx ny nz`, and a `face` element of triangles (`vertex_indices`). Corners with the same position and normal
/// share a vertex. Floats keep values exact, so reading gives back the same triangle list.
enum ParticleMeshFile {
    static func plyData(positions: [SIMD3<Float>], normals: [SIMD3<Float>]) throws -> Data {
        let count = min(positions.count, normals.count) / 3 * 3
        var vertices: [[Float]] = []
        var indexOfVertex: [[Float]: UInt32] = [:]
        var corners: [UInt32] = []
        corners.reserveCapacity(count)
        for index in 0..<count {
            let position = positions[index]
            let normal = normals[index]
            let vertex = [position.x, position.y, position.z, normal.x, normal.y, normal.z]
            if let existing = indexOfVertex[vertex] {
                corners.append(existing)
            } else {
                let new = UInt32(vertices.count)
                indexOfVertex[vertex] = new
                vertices.append(vertex)
                corners.append(new)
            }
        }
        let vertexElement = PLYReader.Element(
            name: "vertex", count: vertices.count,
            properties: ["x", "y", "z", "nx", "ny", "nz"].map { PLYReader.Property(name: $0, kind: .scalar(.float)) }
        )
        let faceElement = PLYReader.Element(
            name: "face", count: count / 3,
            properties: [PLYReader.Property(name: "vertex_indices", kind: .list(count: .uchar, item: .uint))]
        )
        var writer = PLYWriter(header: PLYHeader(format: .binaryLittleEndian, elements: [vertexElement, faceElement]))
        for vertex in vertices {
            try writer.write(vertex.map { .float($0) })
        }
        for start in stride(from: 0, to: corners.count, by: 3) {
            try writer.write([.list(corners[start..<(start + 3)].map { .uint($0) })])
        }
        return try writer.finish()
    }

    /// The triangle list from a PLY file. Faces with more than three corners become fans; vertices without normals get
    /// flat face normals.
    static func triangles(from data: Data) throws -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        let reader = try PLYReader(data: data)
        guard let vertexElement = reader.elements.first(where: { $0.name == "vertex" }),
              let faceElement = reader.elements.first(where: { $0.name == "face" }) else {
            throw ParticleMeshFileError.noFaces
        }
        let names = vertexElement.properties.map(\.name)
        func indices(_ wanted: [String]) -> [Int]? { // swiftlint:disable:this discouraged_optional_collection
            let found = wanted.compactMap { names.firstIndex(of: $0) }
            return found.count == wanted.count ? found : nil
        }
        guard let positionIndices = indices(["x", "y", "z"]) else {
            throw ParticleMeshFileError.noPositions
        }
        let normalIndices = indices(["nx", "ny", "nz"])
        var vertexPositions: [SIMD3<Float>] = []
        var vertexNormals: [SIMD3<Float>] = []
        try reader.readFloatValues(element: vertexElement) { values in
            func vector(_ indices: [Int]) throws -> SIMD3<Float> {
                guard let x = values[indices[0]], let y = values[indices[1]], let z = values[indices[2]] else {
                    throw ParticleMeshFileError.unreadable
                }
                return [x, y, z]
            }
            vertexPositions.append(try vector(positionIndices))
            if let normalIndices {
                vertexNormals.append(try vector(normalIndices))
            }
        }
        guard let listIndex = faceElement.properties.firstIndex(where: { $0.name == "vertex_indices" || $0.name == "vertex_index" }) else {
            throw ParticleMeshFileError.noFaces
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        try reader.readValues(element: faceElement) { values in
            guard case let .list(items)? = values[listIndex] else {
                throw ParticleMeshFileError.unreadable
            }
            let corners = try items.map { item -> Int in
                guard let index = item.integerValue, vertexPositions.indices.contains(index) else {
                    throw ParticleMeshFileError.indexOutOfRange
                }
                return index
            }
            guard corners.count >= 3 else {
                return
            }
            for index in 1..<(corners.count - 1) {
                let triangle = [corners[0], corners[index], corners[index + 1]]
                let points = triangle.map { vertexPositions[$0] }
                positions += points
                if vertexNormals.isEmpty {
                    normals += Array(repeating: simd_cross(points[1] - points[0], points[2] - points[0]), count: 3)
                } else {
                    normals += triangle.map { vertexNormals[$0] }
                }
            }
        }
        guard !positions.isEmpty else {
            throw ParticleMeshFileError.noFaces
        }
        return (positions, normals)
    }
}

private extension PLYReader.PropertyValue {
    var integerValue: Int? {
        switch self {
        case let .char(value): Int(value)
        case let .uchar(value): Int(value)
        case let .short(value): Int(value)
        case let .ushort(value): Int(value)
        case let .int(value): Int(value)
        case let .uint(value): Int(value)
        case .float, .double, .list: nil
        }
    }
}

enum ParticleMeshFileError: Error, LocalizedError, Equatable {
    case noFaces
    case noPositions
    case indexOutOfRange
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noFaces: "The particle mesh PLY file has no faces."
        case .noPositions: "The particle mesh PLY file's vertices have no x, y, and z."
        case .indexOutOfRange: "The particle mesh PLY file has a face with a vertex index out of range."
        case .unreadable: "The particle mesh PLY file has a value that cannot be read."
        }
    }
}
