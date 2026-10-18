import Metal
import simd
import SwiftMesh

/// A complete effect: emitters with their sprites and motion, plus the colliders and force fields they play against.
public struct ParticlePreset: Sendable, Identifiable {
    /// One emitter in a preset.
    public struct Layer: Sendable {
        public var name: String
        public var settings: ParticleEmitter
        public var sprite: ParticleSprite
        public var motion: EmitterMotion
        public var simulationSpace: SimulationSpace
        public var capacity: Int
        /// Triangles for `EmitterShape.mesh`, in emitter space.
        public var mesh: Mesh?

        public init(
            _ name: String,
            settings: ParticleEmitter,
            sprite: ParticleSprite = .softDot,
            motion: EmitterMotion = EmitterMotion(),
            simulationSpace: SimulationSpace = .world,
            capacity: Int = 50_000,
            mesh: Mesh? = nil
        ) {
            self.mesh = mesh
            self.name = name
            self.settings = settings
            self.sprite = sprite
            self.motion = motion
            self.simulationSpace = simulationSpace
            self.capacity = capacity
        }
    }

    public var name: String
    public var layers: [Layer]
    /// Default colliders. Apps can replace or add to them at runtime.
    public var colliders: [Collider]
    /// Moves the colliders with `Collider.animated(time:index:)`.
    public var animatesColliders: Bool
    public var forceFields: [ForceField]
    /// Suggested camera.
    public var cameraEye: SIMD3<Float>
    public var cameraTarget: SIMD3<Float>

    public var id: String { name }

    public init(
        _ name: String,
        layers: [Layer],
        colliders: [Collider] = [],
        animatesColliders: Bool = false,
        forceFields: [ForceField] = [],
        cameraEye: SIMD3<Float> = [0, 3, 6],
        cameraTarget: SIMD3<Float> = [0, 1.5, 0]
    ) {
        self.name = name
        self.layers = layers
        self.colliders = colliders
        self.animatesColliders = animatesColliders
        self.forceFields = forceFields
        self.cameraEye = cameraEye
        self.cameraTarget = cameraTarget
    }

    /// Colliders for `time`, animated if the preset asks for it.
    public func colliders(at time: Float) -> [Collider] {
        guard animatesColliders else {
            return colliders
        }
        return colliders.enumerated().map { index, collider in collider.animated(time: time, index: index) }
    }

    /// Emitter transforms for `time`, one per layer.
    public func transforms(at time: Float) -> [simd_float4x4] {
        layers.map { $0.motion.transform(time: time) }
    }

    /// Finds a preset by name, ignoring case, spaces, and hyphens.
    public static func named(_ name: String) -> ParticlePreset? {
        func normalized(_ string: String) -> String {
            string.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        return all.first { normalized($0.name) == normalized(name) }
    }
}

public extension ParticleSystem {
    /// Replaces every emitter, collider, and force field with the preset's. Removes all particles.
    func load(_ preset: ParticlePreset) throws {
        try setEmitters(preset.layers.map { ($0.settings, $0.capacity) })
        var textures: [ParticleSprite: MTLTexture] = [:]
        for (emitter, layer) in zip(emitters, preset.layers) {
            if textures[layer.sprite] == nil, let texture = layer.sprite.makeTexture(device: device) {
                textures[layer.sprite] = texture
            }
            emitter.texture = textures[layer.sprite]
            emitter.simulationSpace = layer.simulationSpace
            emitter.transform = layer.motion.transform(time: 0)
            emitter.mesh = try layer.mesh.map { try EmitterMesh(device: device, mesh: $0) }
        }
        colliders = preset.colliders
        forceFields = preset.forceFields
    }
}
