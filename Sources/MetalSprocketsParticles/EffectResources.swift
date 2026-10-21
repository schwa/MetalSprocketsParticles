import CryptoKit
import Foundation

/// Binary data an effect keeps in files next to its JSON instead of inside it: images, and distance fields' values.
/// JSON refers to each file by name (resolved in the effect's folder) or by a `file:` URL.
///
/// Encoding adds each piece of data under a stable name made from its content, so saving the same data twice gives
/// the same file; decoding reads names from the folder. Pass a store to coders with `encoder(_:)` and `decoder(_:)`,
/// or use `ParticleSystem(contentsOf:)` and `write(to:)`, which do it for you. An in-memory store (no folder) holds the
/// files itself, for drag and drop and tests.
public final class EffectResources: @unchecked Sendable {
    /// Where names resolve when reading; nil for an in-memory store.
    public let folder: URL?
    private let lock = NSLock()
    private var storage: [String: Data]

    /// Reads names from `folder`.
    public init(folder: URL) {
        self.folder = folder
        storage = [:]
    }

    /// Holds `files` in memory, by name.
    public init(files: [String: Data] = [:]) {
        folder = nil
        storage = files
    }

    /// The files added while encoding (and, in memory, the ones given), by name.
    public var files: [String: Data] {
        lock.withLock { storage }
    }

    /// A JSON encoder that writes data to this store and puts its file names in the JSON.
    public func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.userInfo[.effectResources] = self
        return encoder
    }

    /// A JSON decoder that reads data named in the JSON from this store.
    public func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.effectResources] = self
        return decoder
    }

    /// The file name `add` gives `data`: `prefix`, the first 8 hex digits of its SHA-256, and `fileExtension`.
    static func name(for data: Data, prefix: String, fileExtension: String) -> String {
        let digest = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(digest).\(fileExtension)"
    }

    /// Stores `data` and returns its file name (see `name(for:prefix:fileExtension:)`).
    func add(_ data: Data, prefix: String, fileExtension: String) -> String {
        let name = Self.name(for: data, prefix: prefix, fileExtension: fileExtension)
        lock.withLock { storage[name] = data }
        return name
    }

    /// The data for `reference`: a file name in the folder (or in memory), or a `file:` URL.
    func data(for reference: String) throws -> Data {
        if let url = URL(string: reference), url.isFileURL {
            return try Data(contentsOf: url)
        }
        // Plain names only: no folders, no way out of the effect's folder.
        guard !reference.isEmpty, !reference.contains("/"), !reference.contains("\\"), reference != ".", reference != ".." else {
            throw EffectResourceError.invalidReference(reference)
        }
        if let data = lock.withLock({ storage[reference] }) {
            return data
        }
        guard let folder else {
            throw EffectResourceError.missing(reference)
        }
        let url = folder.appending(path: reference)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EffectResourceError.missing(reference)
        }
        return try Data(contentsOf: url)
    }

    /// Writes the added files into `folder`.
    func write(into folder: URL) throws {
        for (name, data) in files {
            try data.write(to: folder.appending(path: name), options: .atomic)
        }
    }
}

extension Data {
    /// A file extension for image data, from its first bytes: png, jpg, gif, heic, or image when unknown.
    var imageFileExtension: String {
        let bytes = [UInt8](prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if bytes.count >= 12, bytes[4...7] == [0x66, 0x74, 0x79, 0x70] { return "heic" }
        return "image"
    }
}

public enum EffectResourceError: Error, LocalizedError, Sendable {
    /// A reference that is not a plain file name or a `file:` URL.
    case invalidReference(String)
    /// No file with that name next to the effect.
    case missing(String)
    /// Coding data without an `EffectResources` store in the coder's userInfo.
    case noStore

    public var errorDescription: String? {
        switch self {
        case let .invalidReference(reference):
            "'\(reference.prefix(40))' is not a file name or file URL. Effects keep images and distance fields in files next to their JSON; inline data is not read."
        case let .missing(name):
            "The effect refers to '\(name)', which is not next to it."
        case .noStore:
            "Effects with images or distance fields need an EffectResources store to encode or decode them; use ParticleSystem(contentsOf:) and write(to:)."
        }
    }
}

public extension CodingUserInfoKey {
    /// The `EffectResources` an effect's coders read and write files through.
    static let effectResources: CodingUserInfoKey = {
        guard let key = CodingUserInfoKey(rawValue: "MetalSprocketsParticles.effectResources") else {
            preconditionFailure("A constant, non-empty key is always valid.")
        }
        return key
    }()
}

extension KeyedDecodingContainer {
    /// Replaces `value` when `key` is present; otherwise leaves it alone.
    func update<T: Decodable>(_ value: inout T, _ key: Key) throws {
        if contains(key) {
            value = try decode(T.self, forKey: key)
        }
    }

    /// Data stored as a file reference.
    func decodeResource(forKey key: Key, decoder: Decoder) throws -> Data {
        try decodeNamedResource(forKey: key, decoder: decoder).data
    }

    /// Data stored as a file reference, with the reference (for its file extension).
    func decodeNamedResource(forKey key: Key, decoder: Decoder) throws -> (reference: String, data: Data) {
        let reference = try decode(String.self, forKey: key)
        guard let resources = decoder.userInfo[.effectResources] as? EffectResources else {
            throw EffectResourceError.noStore
        }
        return (reference, try resources.data(for: reference))
    }
}

extension KeyedEncodingContainer {
    /// Writes `data` to the encoder's store and its file name here.
    mutating func encodeResource(_ data: Data, forKey key: Key, encoder: Encoder, prefix: String, fileExtension: String) throws {
        guard let resources = encoder.userInfo[.effectResources] as? EffectResources else {
            throw EffectResourceError.noStore
        }
        try encode(resources.add(data, prefix: prefix, fileExtension: fileExtension), forKey: key)
    }
}
