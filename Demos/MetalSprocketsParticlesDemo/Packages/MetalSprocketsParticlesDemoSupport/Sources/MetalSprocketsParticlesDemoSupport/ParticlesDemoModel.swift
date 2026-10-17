import Metal
import MetalSprocketsParticles
import Observation
import simd

/// Demo state edited by the inspector. Each change is pushed to the particle system.
@Observable
@MainActor
final class ParticlesDemoModel {
    @ObservationIgnored let system: ParticleSystem?
    @ObservationIgnored private var textureCache: [ParticleSprite: MTLTexture] = [:]
    /// Particles per emitter. Preset layers bring their own; emitters added in the inspector get the default.
    @ObservationIgnored private var capacities: [DemoEmitter.ID: Int] = [:]
    private static let defaultCapacity = 50_000

    /// The preset last loaded. Choosing another loads it, replacing emitters, colliders, and force fields.
    var presetName: String {
        didSet {
            if presetName != oldValue, let preset = ParticlePreset.named(presetName) {
                load(preset)
            }
        }
    }

    var emitters: [DemoEmitter] = [] {
        didSet { sync(from: oldValue) }
    }

    var selectedEmitterID: DemoEmitter.ID?

    /// The emitter the inspector edits. Falls back to the first emitter.
    var selectedEmitter: DemoEmitter {
        get { emitters.first { $0.id == selectedEmitterID } ?? emitters[0] }
        set {
            if let index = emitters.firstIndex(where: { $0.id == newValue.id }) {
                emitters[index] = newValue
            }
        }
    }

    /// Collider rest positions. `animateColliders` moves them each frame.
    var colliders: [ColliderItem] = [] {
        didSet { system?.colliders = colliders.map(\.collider) }
    }

    var forceFields: [ForceFieldItem] = [] {
        didSet { system?.forceFields = forceFields.map(\.field) }
    }

    var playback: SimulationState = .playing {
        didSet { system?.state = playback }
    }

    var speedFactor: Float = 1 {
        didSet { system?.speedFactor = speedFactor }
    }

    var animateColliders = false
    var showColliders = false

    /// The preset's suggested camera, updated on load.
    private(set) var cameraEye: SIMD3<Float> = [0, 3, 6]
    private(set) var cameraTarget: SIMD3<Float> = [0, 1.5, 0]

    init(preset: ParticlePreset = .fountain) {
        system = try? ParticleSystem(emitters: [], capacity: 1)
        presetName = preset.name
        load(preset)
    }

    func load(_ preset: ParticlePreset) {
        let emitters = preset.layers.map(DemoEmitter.init)
        capacities = Dictionary(uniqueKeysWithValues: zip(emitters.map(\.id), preset.layers.map(\.capacity)))
        self.emitters = emitters
        selectedEmitterID = emitters.first?.id
        colliders = preset.colliders.map { ColliderItem(collider: $0) }
        forceFields = preset.forceFields.map { ForceFieldItem(field: $0) }
        animateColliders = preset.animatesColliders
        cameraEye = preset.cameraEye
        cameraTarget = preset.cameraTarget
    }

    /// Reloads the current preset, discarding edits.
    func reloadPreset() {
        if let preset = ParticlePreset.named(presetName) {
            load(preset)
        }
    }

    // MARK: Emitters

    func addEmitter() {
        var settings = ParticleEmitter()
        settings.birthRate = 2_000
        let emitter = DemoEmitter(name: "Emitter \(emitters.count + 1)", settings: settings)
        emitters.append(emitter)
        selectedEmitterID = emitter.id
    }

    func duplicateSelectedEmitter() {
        let source = selectedEmitter
        var copy = DemoEmitter(name: "\(source.name) Copy", settings: source.settings)
        copy.sprite = source.sprite
        copy.motion = source.motion
        copy.simulationSpace = source.simulationSpace
        copy.isEmitting = source.isEmitting
        capacities[copy.id] = capacities[source.id]
        emitters.append(copy)
        selectedEmitterID = copy.id
    }

    /// Keeps at least one emitter.
    func removeSelectedEmitter() {
        guard emitters.count > 1, let index = emitters.firstIndex(where: { $0.id == selectedEmitter.id }) else {
            return
        }
        emitters.remove(at: index)
        selectedEmitterID = emitters[min(index, emitters.count - 1)].id
    }

    func burstSelectedEmitter(_ count: Int = 2_000) {
        guard let index = emitters.firstIndex(where: { $0.id == selectedEmitter.id }), let system, index < system.emitters.count else {
            return
        }
        system.emitters[index].burst(count)
    }

    func restart() {
        system?.restart()
        playback = .playing
    }

    // MARK: Per frame

    func frameColliders(time: Float) -> [Collider] {
        guard animateColliders else {
            return colliders.map(\.collider)
        }
        return colliders.enumerated().map { index, item in item.collider.animated(time: time, index: index) }
    }

    func frameTransforms(time: Float) -> [simd_float4x4] {
        emitters.map { $0.motion.transform(time: time) }
    }

    // MARK: Sync

    private func sync(from oldValue: [DemoEmitter]) {
        guard let system else {
            return
        }
        // Adding, removing, or reordering emitters rebuilds the shared buffer.
        if oldValue.map(\.id) != emitters.map(\.id) {
            _ = try? system.setEmitters(emitters.map { ($0.settings, capacities[$0.id] ?? Self.defaultCapacity) })
        }
        for (emitter, runtime) in zip(emitters, system.emitters) {
            runtime.settings = emitter.settings
            runtime.texture = texture(emitter.sprite, device: system.device)
            runtime.simulationSpace = emitter.simulationSpace
            runtime.isEmitting = emitter.isEmitting
        }
    }

    private func texture(_ sprite: ParticleSprite, device: MTLDevice) -> MTLTexture? {
        if let cached = textureCache[sprite] {
            return cached
        }
        let texture = sprite.makeTexture(device: device)
        textureCache[sprite] = texture
        return texture
    }
}
