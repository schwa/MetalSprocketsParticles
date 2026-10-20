import Foundation
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import UniformTypeIdentifiers

// Saved effects are ParticlePresets as JSON. Domain types are Codable directly; this file holds the conformances that
// cannot be synthesized and the file helpers.

extension ParticleBlendMode: @retroactive Codable {}
extension ParticleBirthLocation: @retroactive Codable {}
extension ParticleBirthDirection: @retroactive Codable {}
extension ParticleImageSequenceMode: @retroactive Codable {}

/// Saved flat: the shape's keys plus `categoryBitMask` (omitted when all bits are set).
extension Collider: Codable {
    private enum CodingKeys: String, CodingKey {
        case categoryBitMask
    }

    public init(from decoder: Decoder) throws {
        shape = try Shape(from: decoder)
        categoryBitMask = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(UInt32.self, forKey: .categoryBitMask) ?? .max
    }

    public func encode(to encoder: Encoder) throws {
        try shape.encode(to: encoder)
        if categoryBitMask != .max {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(categoryBitMask, forKey: .categoryBitMask)
        }
    }
}

extension Collider.Shape: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, normal, distance, center, radius, halfExtents, rotation, start, end, field
    }

    private enum FieldKeys: String, CodingKey {
        case origin, spacing, resolution, values
    }

    /// The most samples a saved field may have (256³), so a hostile file cannot ask for a huge texture.
    static let maximumFieldSamples = 256 * 256 * 256

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "plane":
            self = .plane(normal: try container.decode(SIMD3<Float>.self, forKey: .normal), distance: try container.decode(Float.self, forKey: .distance))
        case "sphere":
            self = .sphere(center: try container.decode(SIMD3<Float>.self, forKey: .center), radius: try container.decode(Float.self, forKey: .radius))
        case "box":
            let rotation = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .rotation) ?? [0, 0, 0, 1]
            self = .box(
                center: try container.decode(SIMD3<Float>.self, forKey: .center),
                halfExtents: try container.decode(SIMD3<Float>.self, forKey: .halfExtents),
                rotation: simd_quatf(vector: rotation)
            )
        case "capsule":
            self = .capsule(
                start: try container.decode(SIMD3<Float>.self, forKey: .start),
                end: try container.decode(SIMD3<Float>.self, forKey: .end),
                radius: try container.decode(Float.self, forKey: .radius)
            )
        case "signedDistanceField":
            let rotation = try container.decodeIfPresent(SIMD4<Float>.self, forKey: .rotation) ?? [0, 0, 0, 1]
            self = .signedDistanceField(
                try Self.decodeField(container.nestedContainer(keyedBy: FieldKeys.self, forKey: .field), decoder: decoder),
                center: try container.decodeIfPresent(SIMD3<Float>.self, forKey: .center) ?? .zero,
                rotation: simd_quatf(vector: rotation)
            )
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown collider kind '\(kind)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plane(normal, distance):
            try container.encode("plane", forKey: .kind)
            try container.encode(normal, forKey: .normal)
            try container.encode(distance, forKey: .distance)
        case let .sphere(center, radius):
            try container.encode("sphere", forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
        case let .box(center, halfExtents, rotation):
            try container.encode("box", forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(halfExtents, forKey: .halfExtents)
            // Quaternions are not Codable; store (x, y, z, w).
            try container.encode(rotation.vector, forKey: .rotation)
        case let .capsule(start, end, radius):
            try container.encode("capsule", forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encode(radius, forKey: .radius)
        case let .signedDistanceField(field, center, rotation):
            try container.encode("signedDistanceField", forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(rotation.vector, forKey: .rotation)
            var fieldContainer = container.nestedContainer(keyedBy: FieldKeys.self, forKey: .field)
            try fieldContainer.encode(field.origin, forKey: .origin)
            try fieldContainer.encode(field.spacing, forKey: .spacing)
            try fieldContainer.encode(field.resolution, forKey: .resolution)
            // Little-endian Float32s in a file next to the JSON, x fastest, then y, then z.
            try fieldContainer.encodeResource(field.values.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .values, encoder: encoder, prefix: "field", fileExtension: "bin")
        }
    }

    /// Checks what SignedDistanceField's initializer would trap on, and sizes a hostile file could abuse.
    private static func decodeField(_ container: KeyedDecodingContainer<FieldKeys>, decoder: Decoder) throws -> SignedDistanceField {
        let resolution = try container.decode(SIMD3<Int>.self, forKey: .resolution)
        let data = try container.decodeResource(forKey: .values, decoder: decoder)
        let (samples, overflow) = resolution.x.multipliedReportingOverflow(by: resolution.y)
        let (total, overflow2) = samples.multipliedReportingOverflow(by: resolution.z)
        guard all(resolution .>= 2), !overflow, !overflow2, total <= maximumFieldSamples else {
            throw DecodingError.dataCorruptedError(forKey: .resolution, in: container, debugDescription: "Distance field resolution must be 2 or more per axis and at most \(maximumFieldSamples) samples")
        }
        guard data.count == total * MemoryLayout<Float>.size else {
            throw DecodingError.dataCorruptedError(forKey: .values, in: container, debugDescription: "Distance field has \(data.count) bytes of values; its resolution needs \(total * MemoryLayout<Float>.size)")
        }
        // Data's bytes need not be aligned for Float.
        let values = data.withUnsafeBytes { bytes in
            (0..<total).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
        }
        return SignedDistanceField(
            origin: try container.decode(SIMD3<Float>.self, forKey: .origin),
            spacing: try container.decode(SIMD3<Float>.self, forKey: .spacing),
            resolution: resolution,
            values: values
        )
    }
}

public extension UTType {
    /// A saved effect: a package (folder) holding `effect.json` and the image and distance field files it names.
    static let particleEffect = UTType(filenameExtension: ParticleSystem.packageExtension, conformingTo: .package) ?? .package
}

public extension ParticleSystem {
    /// The file extension of effect packages.
    static let packageExtension = "particles"
    /// The JSON's name inside a package.
    static let packageJSONName = "effect.json"

    /// Loads a saved effect: a package (`Name.particles`, a folder holding `effect.json`), or a JSON file whose
    /// images and distance fields are files next to it, as the bundled presets are.
    init(contentsOf url: URL) throws {
        let isPackage = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let json = isPackage ? url.appending(path: Self.packageJSONName) : url
        let resources = EffectResources(folder: json.deletingLastPathComponent())
        self = try resources.decoder().decode(ParticleSystem.self, from: Data(contentsOf: json))
    }

    /// Decodes `json`, reading named files from `resources`.
    init(json: Data, resources: EffectResources) throws {
        self = try resources.decoder().decode(ParticleSystem.self, from: json)
    }

    /// The effect as pretty-printed JSON, and the files it names (images and distance fields), by name.
    func encoded() throws -> (json: Data, files: [String: Data]) {
        let resources = EffectResources()
        let json = try resources.encoder().encode(self)
        return (json, resources.files)
    }

    /// Saves the effect. A `.particles` URL gets a package: a folder holding `effect.json` and the files it names.
    /// Other URLs get the JSON there and its files next to it.
    func write(to url: URL) throws {
        let (json, files) = try encoded()
        let isPackage = url.pathExtension == Self.packageExtension
        let folder = isPackage ? url : url.deletingLastPathComponent()
        if isPackage {
            // A fresh folder, so files the effect no longer names do not linger.
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try json.write(to: isPackage ? url.appending(path: Self.packageJSONName) : url, options: .atomic)
        try EffectResources(files: files).write(into: folder)
    }

    /// The effect as a package's folder contents, for file documents.
    func packageFileWrapper() throws -> FileWrapper {
        let (json, files) = try encoded()
        var wrappers = files.mapValues { FileWrapper(regularFileWithContents: $0) }
        wrappers[Self.packageJSONName] = FileWrapper(regularFileWithContents: json)
        return FileWrapper(directoryWithFileWrappers: wrappers)
    }

    /// Reads a package's folder contents.
    init(packageFileWrapper wrapper: FileWrapper) throws {
        let contents = wrapper.fileWrappers ?? [:]
        guard let json = contents[Self.packageJSONName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let files = contents.compactMapValues(\.regularFileContents)
        try self.init(json: json, resources: EffectResources(files: files))
    }
}
