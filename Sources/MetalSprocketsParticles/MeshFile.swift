import Foundation
import Metal
import MetalKit
import ModelIO
import SwiftMesh

/// Emitter meshes in files (#170): OBJ, written and read here so positions and triangles come back exactly, and other
/// formats Model I/O reads (PLY, USD), read through it.
enum MeshFile {
    /// Positions and triangles as OBJ text: `v x y z` lines, then `f a b c` lines (1-based). Floats are written in their
    /// shortest exact form, so reading gives back the same values.
    static func objData(of mesh: Mesh) -> Data {
        var text = "# MetalSprocketsParticles emitter mesh\n"
        for position in mesh.positions {
            text += "v \(position.x) \(position.y) \(position.z)\n"
        }
        for triangle in mesh.triangulate() {
            text += "f \(triangle.0.raw + 1) \(triangle.1.raw + 1) \(triangle.2.raw + 1)\n"
        }
        return Data(text.utf8)
    }

    /// A mesh from file data; `fileExtension` picks the reader.
    static func mesh(from data: Data, fileExtension: String) throws -> Mesh {
        // OBJ through our reader only: it skips lines it does not use, so a failure is a real error, reported as such.
        if fileExtension.lowercased() == "obj" {
            return try objMesh(from: data)
        }
        return try modelIOMesh(from: data, fileExtension: fileExtension)
    }

    /// `v` and `f` lines of an OBJ file; other lines are ignored. Faces may be polygons, may use `v/vt/vn` forms (only
    /// the position index is used), and may count from the end with negative indices.
    static func objMesh(from data: Data) throws -> Mesh {
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw MeshFileError.unreadable
        }
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let kind = fields.first else {
                continue
            }
            if kind == "v" {
                guard fields.count >= 4, let x = Float(fields[1]), let y = Float(fields[2]), let z = Float(fields[3]) else {
                    throw MeshFileError.unreadable
                }
                positions.append([x, y, z])
            } else if kind == "f" {
                let indices = try fields.dropFirst().map { field -> Int in
                    guard let index = field.split(separator: "/", omittingEmptySubsequences: false).first.flatMap({ Int($0) }), index != 0 else {
                        throw MeshFileError.unreadable
                    }
                    return index > 0 ? index - 1 : positions.count + index
                }
                guard indices.count >= 3, indices.allSatisfy({ positions.indices.contains($0) }) else {
                    throw MeshFileError.indexOutOfRange
                }
                faces.append(indices)
            }
        }
        guard !faces.isEmpty else {
            throw MeshFileError.noMesh
        }
        return Mesh(positions: positions, faces: faces)
    }

    /// The first mesh Model I/O reads from the data, written to a temporary file of that type.
    static func modelIOMesh(from data: Data, fileExtension: String) throws -> Mesh {
        guard MDLAsset.canImportFileExtension(fileExtension) else {
            throw MeshFileError.unsupportedFormat(fileExtension)
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "mesh-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let device = ParticleSystemRuntime.defaultDevice()
        // SwiftMesh converts through MetalKit, which needs the asset's buffers made by a MetalKit allocator.
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: MTKMeshBufferAllocator(device: device))
        guard let first = asset.childObjects(of: MDLMesh.self).compactMap({ $0 as? MDLMesh }).first else {
            throw MeshFileError.noMesh
        }
        return try Mesh(mdlMesh: first, device: device)
    }
}

public enum MeshFileError: Error, LocalizedError, Sendable {
    case unreadable
    case indexOutOfRange
    case noMesh
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: "The mesh file could not be read."
        case .indexOutOfRange: "The mesh file has a face with a vertex index out of range."
        case .noMesh: "The mesh file has no faces."
        case let .unsupportedFormat(fileExtension): "Mesh files of type '\(fileExtension)' cannot be read."
        }
    }
}
