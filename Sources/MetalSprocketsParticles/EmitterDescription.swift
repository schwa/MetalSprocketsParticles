import Foundation
import Metal
import simd
import SwiftMesh

/// Everything needed to create one emitter: its settings plus the resources and runtime choices that live on
/// `ParticleSystem.Emitter`. Presets, apps, and editors describe emitters with this; `ParticleSystem.apply(_:)` turns
/// descriptions into running emitters.
public struct EmitterDescription: Sendable, Identifiable, Equatable {
    /// Identifies the emitter across edits. `apply(_:)` rebuilds the particle buffer when the ids change.
    public let id: UUID
    public var name: String
    public var settings: ParticleEmitter
    public var sprite: ParticleSprite
    public var motion: EmitterMotion
    public var simulationSpace: SimulationSpace
    /// Particles this emitter can have alive at once.
    public var capacity: Int
    /// Triangles for `EmitterShape.mesh`, in emitter space.
    public var mesh: Mesh?
    /// Animates `mesh`.
    public var meshDeformation: MeshDeformation = .none
    public var isEmitting: Bool

    public init(
        _ name: String,
        settings: ParticleEmitter,
        sprite: ParticleSprite = .softDot,
        motion: EmitterMotion = EmitterMotion(),
        simulationSpace: SimulationSpace = .world,
        capacity: Int = 50_000,
        mesh: Mesh? = nil,
        isEmitting: Bool = true
    ) {
        id = UUID()
        self.name = name
        self.settings = settings
        self.sprite = sprite
        self.motion = motion
        self.simulationSpace = simulationSpace
        self.capacity = capacity
        self.mesh = mesh
        self.isEmitting = isEmitting
    }

    /// The same emitter under a new id, so `apply(_:)` treats it as a different emitter.
    public func copy(named name: String? = nil) -> Self {
        var copy = Self(
            name ?? self.name,
            settings: settings,
            sprite: sprite,
            motion: motion,
            simulationSpace: simulationSpace,
            capacity: capacity,
            mesh: mesh,
            isEmitting: isEmitting
        )
        copy.meshDeformation = meshDeformation
        return copy
    }
}

public extension ParticleSystem {
    /// Makes the system's emitters match `descriptions`. Adding, removing, reordering, or resizing emitters (a change
    /// in ids or capacities), or `rebuild`, reallocates the particle buffer and removes all particles; otherwise
    /// emitters are updated in place and keep their particles. Textures and GPU meshes are cached.
    func apply(_ descriptions: [EmitterDescription], rebuild: Bool = false) throws {
        let layout = descriptions.map { AppliedEmitter(id: $0.id, capacity: max($0.capacity, 1)) }
        if rebuild || layout != appliedLayout {
            try setEmitters(descriptions.map { ($0.settings, $0.capacity) })
            for (emitter, description) in zip(emitters, descriptions) {
                emitter.transform = description.motion.transform(time: 0)
            }
            appliedLayout = layout
        }
        for (emitter, description) in zip(emitters, descriptions) {
            emitter.settings = description.settings
            emitter.simulationSpace = description.simulationSpace
            emitter.isEmitting = description.isEmitting
            emitter.texture = texture(for: description.sprite)
            // Array equality is fast when the storage is shared, so an unchanged mesh costs almost nothing here.
            if emitter.meshSource != description.mesh {
                emitter.mesh = try description.mesh.map { try EmitterMesh(device: device, mesh: $0) }
                emitter.meshSource = description.mesh
            }
            // Back to the rest pose only when turning a built-in deformation off; positions an app set itself stay.
            if description.meshDeformation == .none, emitter.meshDeformation != .none {
                emitter.mesh?.setDeformedPositions(nil)
            }
            emitter.meshDeformation = description.meshDeformation
        }
    }

    /// The sprite's texture, made once per system.
    func texture(for sprite: ParticleSprite) -> MTLTexture? {
        if let cached = spriteTextures[sprite] {
            return cached
        }
        let texture = sprite.makeTexture(device: device)
        spriteTextures[sprite] = texture
        return texture
    }
}

/// SwiftMesh meshes are not Codable, so `mesh` is saved as its triangulated positions and triangle indices (all that
/// emission uses) and loads back as a triangle mesh.
extension EmitterDescription: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, settings, sprite, motion, simulationSpace, capacity, isEmitting, meshPositions, meshTriangles, meshDeformation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(ParticleEmitter.self, forKey: .settings)
        sprite = try container.decode(ParticleSprite.self, forKey: .sprite)
        motion = try container.decode(EmitterMotion.self, forKey: .motion)
        simulationSpace = try container.decode(SimulationSpace.self, forKey: .simulationSpace)
        capacity = try container.decode(Int.self, forKey: .capacity)
        isEmitting = try container.decodeIfPresent(Bool.self, forKey: .isEmitting) ?? true
        if let positions = try container.decodeIfPresent([SIMD3<Float>].self, forKey: .meshPositions) {
            let triangles = try container.decode([SIMD3<Int32>].self, forKey: .meshTriangles)
            guard triangles.allSatisfy({ all($0 .>= 0) && all($0 .< Int32(positions.count)) }) else {
                throw DecodingError.dataCorruptedError(forKey: .meshTriangles, in: container, debugDescription: "Mesh triangle index out of range")
            }
            mesh = Mesh(positions: positions, faces: triangles.map { [Int($0.x), Int($0.y), Int($0.z)] })
        } else {
            mesh = nil
        }
        meshDeformation = try container.decodeIfPresent(MeshDeformation.self, forKey: .meshDeformation) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(settings, forKey: .settings)
        try container.encode(sprite, forKey: .sprite)
        try container.encode(motion, forKey: .motion)
        try container.encode(simulationSpace, forKey: .simulationSpace)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(isEmitting, forKey: .isEmitting)
        if let mesh {
            try container.encode(mesh.positions, forKey: .meshPositions)
            let triangles = mesh.triangulate().map { SIMD3<Int32>(Int32($0.0.raw), Int32($0.1.raw), Int32($0.2.raw)) }
            try container.encode(triangles, forKey: .meshTriangles)
        }
        if meshDeformation != .none {
            try container.encode(meshDeformation, forKey: .meshDeformation)
        }
    }
}

/// What `apply(_:)` last built the buffer for.
struct AppliedEmitter: Equatable {
    var id: UUID
    var capacity: Int
}
