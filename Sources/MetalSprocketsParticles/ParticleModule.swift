import Foundation

// One emitter behavior with its settings (#200). Each module type owns its fields, its defaults, how it lowers onto
// ParticleEmitter, and how it is recovered from one. SpawnModule, UpdateModule, and RenderModule wrap the types of
// each stage.

public protocol ParticleModule: Sendable, Equatable, Codable {
    /// The key in effect files, e.g. "gravity". Unique within a stage.
    static var kind: String { get }
    /// Every emitter has this module; lifting always produces it and editors do not remove it.
    static var isRequired: Bool { get }
    /// What an editor adds, or nil if editors cannot add this kind.
    static var added: Self? { get }
    /// Writes the module's settings onto `emitter`.
    func apply(to emitter: inout ParticleEmitter)
    /// The module that `emitter` implies, or nil when `emitter` has it at its neutral value.
    init?(lifting emitter: ParticleEmitter)
}

public extension ParticleModule {
    static var isRequired: Bool { false }
    static var added: Self? { nil }
}

/// A stage's module enum: one case per module type, wrapping it.
public protocol StageModule: Sendable, Equatable, Codable {
    /// The stage's module types in lifting order.
    static var types: [any ParticleModule.Type] { get }

    var module: any ParticleModule { get }

    init?(wrapping module: any ParticleModule)
}

public extension StageModule {
    var kind: String { type(of: module).kind }
    var isRequired: Bool { type(of: module).isRequired }

    /// A new module of each kind an editor can add.
    static var addable: [Self] {
        // A key path here crashes the compiler (existential metatypes).
        types.compactMap { $0.added }.compactMap { Self(wrapping: $0) } // swiftlint:disable:this prefer_key_path
    }

    func apply(to emitter: inout ParticleEmitter) {
        module.apply(to: &emitter)
    }

    /// The modules `emitter` implies, in lifting order.
    static func lifted(from emitter: ParticleEmitter) -> [Self] {
        types.compactMap { $0.init(lifting: emitter) }.compactMap { Self(wrapping: $0) }
    }

    /// Saved as `{"kind": {settings}}`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ModuleKey.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A module has exactly one key, its kind"))
        }
        guard let type = Self.types.first(where: { $0.kind == key.stringValue }) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unknown module '\(key.stringValue)'")
        }
        let module = try type.init(from: container.superDecoder(forKey: key))
        guard let wrapped = Self(wrapping: module) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Module '\(key.stringValue)' does not belong in this stage")
        }
        self = wrapped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ModuleKey.self)
        try module.encode(to: container.superEncoder(forKey: ModuleKey(kind)))
    }
}

struct ModuleKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
