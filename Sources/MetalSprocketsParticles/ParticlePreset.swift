import Metal
import simd

/// A complete effect: emitters with their sprites and motion, plus the colliders and force fields they play against.
public struct ParticlePreset: Sendable, Identifiable, Codable {
    /// One emitter in a preset.
    public typealias Layer = EmitterDescription

    public var name: String
    public var layers: [Layer]
    /// Default colliders. Apps can replace or add to them at runtime.
    public var colliders: [Collider]
    /// Moves the colliders with `Collider.animated(time:index:)`.
    public var animatesColliders: Bool
    public var forceFields: [ForceField]
    /// Lights for emitters with `isLit`.
    public var lights: [ParticleLight]
    public var ambientLight: SIMD3<Float>
    /// Stand-ins for app objects, by name, for `EmissionTrigger.Condition.objectEnters`: each moves along its motion's
    /// path. Apps feed `trackedObjectPositions(at:)` into `ParticleSystem.trackedObjects` each frame.
    public var trackedObjects: [String: EmitterMotion]
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
        lights: [ParticleLight] = [],
        ambientLight: SIMD3<Float> = [0.25, 0.25, 0.25],
        trackedObjects: [String: EmitterMotion] = [:],
        cameraEye: SIMD3<Float> = [0, 3, 6],
        cameraTarget: SIMD3<Float> = [0, 1.5, 0]
    ) {
        self.name = name
        self.layers = layers
        self.colliders = colliders
        self.animatesColliders = animatesColliders
        self.forceFields = forceFields
        self.lights = lights
        self.ambientLight = ambientLight
        self.trackedObjects = trackedObjects
        self.cameraEye = cameraEye
        self.cameraTarget = cameraTarget
    }

    /// Missing keys keep their defaults, so effects saved before a field existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(String.self, forKey: .name), layers: try container.decode([Layer].self, forKey: .layers))
        try container.update(&colliders, .colliders)
        try container.update(&animatesColliders, .animatesColliders)
        try container.update(&forceFields, .forceFields)
        try container.update(&lights, .lights)
        try container.update(&ambientLight, .ambientLight)
        try container.update(&trackedObjects, .trackedObjects)
        try container.update(&cameraEye, .cameraEye)
        try container.update(&cameraTarget, .cameraTarget)
    }

    /// Where each tracked object is at `time`.
    public func trackedObjectPositions(at time: Float) -> [String: SIMD3<Float>] {
        trackedObjects.mapValues { $0.transform(time: time).columns.3.xyz }
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
        try apply(preset.layers, rebuild: true)
        colliders = preset.colliders
        forceFields = preset.forceFields
        lights = preset.lights
        ambientLight = preset.ambientLight
    }
}
