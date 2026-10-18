import Foundation
import Metal
import simd
import SwiftMesh

/// Everything needed to create one emitter: its settings plus the resources and runtime choices that live on
/// `ParticleSystem.Emitter`. Presets, apps, and editors describe emitters with this; `ParticleSystem.apply(_:)` turns
/// descriptions into running emitters.
public struct EmitterDescription: Sendable, Identifiable, Equatable, Codable {
    /// `mesh` is not saved: SwiftMesh meshes are not Codable.
    enum CodingKeys: String, CodingKey {
        case id, name, settings, sprite, motion, simulationSpace, capacity, isEmitting
    }

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
    public func copy(named name: String? = nil) -> EmitterDescription {
        EmitterDescription(
            name ?? self.name,
            settings: settings,
            sprite: sprite,
            motion: motion,
            simulationSpace: simulationSpace,
            capacity: capacity,
            mesh: mesh,
            isEmitting: isEmitting
        )
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

/// What `apply(_:)` last built the buffer for.
struct AppliedEmitter: Equatable {
    var id: UUID
    var capacity: Int
}
