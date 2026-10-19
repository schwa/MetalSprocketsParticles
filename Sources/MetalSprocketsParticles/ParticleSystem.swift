import Metal
import simd

/// A complete effect: emitters with their sprites and motion, plus the colliders and force fields they play against.
public struct ParticleSystem: Sendable, Identifiable, Codable {
    /// One emitter in a particle system.
    public typealias Layer = EmitterDescription

    public var name: String
    /// What the effect shows and how, for people browsing effects.
    public var comment: String = ""
    public var layers: [Layer]
    /// Default colliders. Apps can replace or add to them at runtime.
    public var colliders: [Collider]
    /// Moves the colliders with `Collider.animated(time:index:)`.
    public var animatesColliders: Bool
    /// Draw the colliders as shaded solids and give their depth to the particles, so emitters with `softness` fade
    /// where they meet them. See `ParticleSystemRuntime.renderColliderSolids` and `renderSceneDepth`.
    public var drawsColliders = false
    /// Colliders that turn at a steady rate; see `colliders(at:)`.
    public var colliderSpins: [ColliderSpin] = []
    /// Colliders, force fields, and emitters that follow the pointer. Apps pass the mouse's world position to
    /// `colliders(at:pointer:)`, `forceFields(at:pointer:)`, and `transforms(at:pointer:)`.
    public var pointerBindings: [PointerBinding] = []
    /// Stands in for the pointer when there is no live input, so renders and videos still show the bindings.
    public var pointerMotion = EmitterMotion()
    public var forceFields: [ForceField]
    /// Lights for emitters with `isLit`.
    public var lights: [ParticleLight]
    public var ambientLight: SIMD3<Float>
    /// Stand-ins for app objects, by name, for `EmissionTrigger.Condition.objectEnters`: each moves along its motion's
    /// path. Apps feed `trackedObjectPositions(at:)` into `ParticleSystemRuntime.trackedObjects` each frame.
    public var trackedObjects: [String: EmitterMotion]
    /// Suggested camera.
    public var cameraEye: SIMD3<Float>
    public var cameraTarget: SIMD3<Float>
    /// Reactions to particle events that `ParticlePlayer` carries out on the CPU, a frame or two after they happen.
    public var eventBursts: [EventBurst] = []
    /// 2D: the `.system` camera becomes the overlay camera (one unit is one point, y down) and every emitter is kept on
    /// its plane. The 3D camera and each emitter's own `constrainsToPlane` are kept, so turning it off restores them.
    /// Author 2D effects in points; see `ParticleEmitter.default2D`.
    public var is2D = false

    public var id: String { name }

    /// The layers as they run: in 2D, every emitter kept on its plane.
    var effectiveLayers: [Layer] {
        guard is2D else {
            return layers
        }
        return layers.map { layer in
            var layer = layer
            layer.settings.constrainsToPlane = true
            return layer
        }
    }

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
        try container.update(&drawsColliders, .drawsColliders)
        try container.update(&colliderSpins, .colliderSpins)
        try container.update(&pointerBindings, .pointerBindings)
        try container.update(&pointerMotion, .pointerMotion)
        try container.update(&forceFields, .forceFields)
        try container.update(&lights, .lights)
        try container.update(&ambientLight, .ambientLight)
        try container.update(&trackedObjects, .trackedObjects)
        try container.update(&comment, .comment)
        try container.update(&cameraEye, .cameraEye)
        try container.update(&cameraTarget, .cameraTarget)
        try container.update(&eventBursts, .eventBursts)
        try container.update(&is2D, .is2D)
    }

    /// The same system with `comment` set.
    public func commented(_ comment: String) -> Self {
        var system = self
        system.comment = comment
        return system
    }

    /// Where each tracked object is at `time`.
    public func trackedObjectPositions(at time: Float) -> [String: SIMD3<Float>] {
        trackedObjects.mapValues { $0.transform(time: time).columns.3.xyz }
    }

    /// Colliders for `time`: spun by `colliderSpins`, and animated if the system asks for it.
    public func colliders(at time: Float) -> [Collider] {
        let spun = colliders.spun(colliderSpins, at: time)
        guard animatesColliders else {
            return spun
        }
        return spun.enumerated().map { index, collider in collider.animated(time: time, index: index) }
    }

    /// Emitter transforms for `time`, one per layer.
    public func transforms(at time: Float) -> [simd_float4x4] {
        layers.map { $0.motion.transform(time: time) }
    }
}

public extension [ParticleSystem] {
    /// The system with this name, ignoring case, spaces, and hyphens.
    func named(_ name: String) -> ParticleSystem? {
        func normalized(_ string: String) -> String {
            string.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        return first { normalized($0.name) == normalized(name) }
    }
}

public extension ParticleSystemRuntime {
    /// Makes the runtime match `system`: its emitters, colliders, force fields, lights, and user functions. Particles
    /// stay unless the emitter layout changes (emitters added, removed, reordered, or resized) or `rebuild` is set.
    /// This is the one way a description reaches the runtime; per-frame changes (animation, pointer bindings, tracked
    /// objects) come from `ParticlePlayer` or the caller's `simulate` arguments.
    func apply(_ system: ParticleSystem, rebuild: Bool = false) throws {
        try apply(system.effectiveLayers, rebuild: rebuild)
        colliders = system.colliders
        forceFields = system.forceFields
        lights = system.lights
        ambientLight = system.ambientLight
        try compileFunctions()
    }

    /// Starts `system` from scratch: `apply(system, rebuild: true)`, which removes all particles.
    func load(_ system: ParticleSystem) throws {
        try apply(system, rebuild: true)
    }
}
