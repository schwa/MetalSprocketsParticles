import Foundation
import Metal
import simd
import SwiftMesh

/// Everything needed to create one emitter: its settings plus the resources and runtime choices that live on
/// `ParticleSystemRuntime.Emitter`. Presets, apps, and editors describe emitters with this; `ParticleSystemRuntime.apply(_:)` turns
/// descriptions into running emitters.
public struct EmitterDescription: Sendable, Identifiable, Equatable {
    /// Identifies the emitter across edits. `apply(_:)` rebuilds the particle buffer when the ids change.
    public let id: UUID
    public var name: String
    /// What the emitter does: module stacks per stage.
    public var modules: EmitterModules
    public var sprite: ParticleSprite
    public var motion: EmitterMotion
    public var simulationSpace: SimulationSpace
    /// Particles this emitter can have alive at once.
    public var capacity: Int
    /// Triangles for `EmitterShape.mesh`, in emitter space.
    public var mesh: Mesh?
    /// Animates `mesh`.
    public var meshDeformation: MeshDeformation = .none
    /// Points for `EmitterShape.points`, in emitter space. Takes the place of `mesh` when set; nil uses `mesh`.
    public var points: [EmitterPoint]? // swiftlint:disable:this discouraged_optional_collection
    /// An image for `EmitterShape.points`, sampled into points when applied. Takes the place of `points` and `mesh`.
    public var image: EmitterImage?
    public var isEmitting: Bool

    public init(
        _ name: String,
        modules: EmitterModules,
        sprite: ParticleSprite = .softDot,
        motion: EmitterMotion = EmitterMotion(),
        simulationSpace: SimulationSpace = .world,
        capacity: Int = 50_000,
        mesh: Mesh? = nil,
        isEmitting: Bool = true
    ) {
        id = UUID()
        self.name = name
        self.modules = modules
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
            modules: modules,
            sprite: sprite,
            motion: motion,
            simulationSpace: simulationSpace,
            capacity: capacity,
            mesh: mesh,
            isEmitting: isEmitting
        )
        copy.meshDeformation = meshDeformation
        copy.points = points
        copy.image = image
        return copy
    }
}

public extension ParticleSystemRuntime {
    /// Makes the system's emitters match `descriptions`. Adding, removing, reordering, or resizing emitters (a change
    /// in ids or capacities), or `rebuild`, reallocates the particle buffer and removes all particles; otherwise
    /// emitters are updated in place and keep their particles. Textures and GPU meshes are cached. `constrainsToPlane`
    /// keeps every emitter on its plane, as 2D systems do.
    func apply(_ descriptions: [EmitterDescription], rebuild: Bool = false, constrainsToPlane: Bool = false) throws {
        let layout = descriptions.map { AppliedEmitter(id: $0.id, capacity: max($0.capacity, 1)) }
        if rebuild || layout != appliedLayout {
            try setEmitters(descriptions.map { (modules: $0.modules, capacity: $0.capacity) })
            for (emitter, description) in zip(emitters, descriptions) {
                emitter.transform = description.motion.transform(time: 0)
            }
            appliedLayout = layout
        }
        for (emitter, description) in zip(emitters, descriptions) {
            emitter.configure(modules: description.modules)
            emitter.forcesPlane = constrainsToPlane
            emitter.simulationSpace = description.simulationSpace
            // Only a change in the description turns emission on or off, so start and stop triggers survive re-applying
            // the same description (as ParticlePlayer does every frame).
            if emitter.appliedIsEmitting != description.isEmitting {
                emitter.isEmitting = description.isEmitting
                emitter.appliedIsEmitting = description.isEmitting
            }
            emitter.texture = texture(for: description.sprite)
            // Array equality is fast when the storage is shared, so an unchanged mesh costs almost nothing here.
            if emitter.meshSource != description.mesh || emitter.pointsSource != description.points || emitter.imageSource != description.image {
                if let image = description.image {
                    emitter.mesh = try EmitterMesh(device: device, points: image.points())
                } else if let points = description.points {
                    emitter.mesh = try EmitterMesh(device: device, points: points)
                } else {
                    emitter.mesh = try description.mesh.map { try EmitterMesh(device: device, mesh: $0) }
                }
                emitter.meshSource = description.mesh
                emitter.pointsSource = description.points
                emitter.imageSource = description.image
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
        case id, name, modules, sprite, motion, simulationSpace, capacity, isEmitting, mesh, meshPositions, meshTriangles, meshDeformation, points, image
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        modules = try container.decode(EmitterModules.self, forKey: .modules)
        sprite = try container.decode(ParticleSprite.self, forKey: .sprite)
        motion = try container.decode(EmitterMotion.self, forKey: .motion)
        simulationSpace = try container.decode(SimulationSpace.self, forKey: .simulationSpace)
        capacity = try container.decode(Int.self, forKey: .capacity)
        isEmitting = try container.decodeIfPresent(Bool.self, forKey: .isEmitting) ?? true
        if container.contains(.mesh) {
            // A file next to the effect's JSON (see EffectResources): OBJ, or another format Model I/O reads.
            let (reference, data) = try container.decodeNamedResource(forKey: .mesh, decoder: decoder)
            let fileExtension = reference.contains(".") ? String(reference.split(separator: ".").last ?? "") : ""
            mesh = try MeshFile.mesh(from: data, fileExtension: fileExtension)
        } else if container.contains(.meshPositions) || container.contains(.meshTriangles) {
            throw DecodingError.dataCorruptedError(
                forKey: .meshPositions, in: container,
                debugDescription: "Inline meshes (meshPositions, meshTriangles) are not read; effects keep meshes in files next to their JSON."
            )
        } else {
            mesh = nil
        }
        meshDeformation = try container.decodeIfPresent(MeshDeformation.self, forKey: .meshDeformation) ?? .none
        if container.contains(.points) {
            guard (try? container.decode(String.self, forKey: .points)) != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .points, in: container,
                    debugDescription: "Inline point caches are not read; effects keep points in PLY files next to their JSON."
                )
            }
            points = try PointCacheFile.points(from: container.decodeResource(forKey: .points, decoder: decoder))
        } else {
            points = nil
        }
        image = try container.decodeIfPresent(EmitterImage.self, forKey: .image)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(modules, forKey: .modules)
        try container.encode(sprite, forKey: .sprite)
        try container.encode(motion, forKey: .motion)
        try container.encode(simulationSpace, forKey: .simulationSpace)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(isEmitting, forKey: .isEmitting)
        if let mesh {
            try container.encodeResource(MeshFile.objData(of: mesh), forKey: .mesh, encoder: encoder, prefix: "mesh", fileExtension: "obj")
        }
        if meshDeformation != .none {
            try container.encode(meshDeformation, forKey: .meshDeformation)
        }
        if let points {
            try container.encodeResource(PointCacheFile.plyData(of: points), forKey: .points, encoder: encoder, prefix: "points", fileExtension: "ply")
        }
        try container.encodeIfPresent(image, forKey: .image)
    }
}

/// What `apply(_:)` last built the buffer for.
struct AppliedEmitter: Equatable {
    var id: UUID
    var capacity: Int
}
