import CoreTransferable
import Foundation
import MetalSprocketsParticlesShaders
import simd
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
        case kind, normal, distance, center, radius, halfExtents, rotation, start, end
    }

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
        }
    }
}

public extension ParticleSystem {
    /// Loads a saved effect (JSON). Emitter meshes are not saved, so mesh emitters load without one.
    init(contentsOf url: URL) throws {
        self = try JSONDecoder().decode(ParticleSystem.self, from: try Data(contentsOf: url))
    }

    /// The effect as pretty-printed JSON.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func write(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }
}

/// Saved effects as JSON, for file export and import, drag and drop, and sharing.
extension ParticleSystem: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .json) { system in
            try system.jsonData()
        } importing: { data in
            try JSONDecoder().decode(ParticleSystem.self, from: data)
        }
    }
}
