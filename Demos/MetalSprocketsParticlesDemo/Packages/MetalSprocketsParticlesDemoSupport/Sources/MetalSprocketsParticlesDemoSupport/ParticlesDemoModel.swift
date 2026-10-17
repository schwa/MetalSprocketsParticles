import Metal
import MetalSprocketsParticles
import Observation
import simd

/// Demo state edited by the inspector. Each change is pushed to the particle system.
@Observable
@MainActor
final class ParticlesDemoModel {
    static let capacityPerEmitter = 100_000

    @ObservationIgnored let system: ParticleSystem?
    /// Particles per emitter.
    @ObservationIgnored private let capacity: Int
    @ObservationIgnored private var textureCache: [DemoTexture: MTLTexture] = [:]

    var emitters: [DemoEmitter] {
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

    var animateColliders = true
    var showColliders = true

    init(capacity: Int = capacityPerEmitter) {
        let fountain = DemoEmitter(name: "Fountain", settings: .fountain)
        let colliders = ParticleEmitter.fountainColliders(time: 0).map { ColliderItem(collider: $0) }
        let system = try? ParticleSystem(capacity: capacity, emitter: fountain.settings)
        system?.colliders = colliders.map(\.collider)
        self.system = system
        self.capacity = capacity
        emitters = [fountain]
        selectedEmitterID = fountain.id
        self.colliders = colliders
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
        copy.texture = source.texture
        copy.motion = source.motion
        copy.simulationSpace = source.simulationSpace
        copy.isEmitting = source.isEmitting
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

    func resetScene() {
        let fountain = DemoEmitter(name: "Fountain", settings: .fountain)
        emitters = [fountain]
        selectedEmitterID = fountain.id
        colliders = ParticleEmitter.fountainColliders(time: 0).map { ColliderItem(collider: $0) }
        forceFields = []
    }

    // MARK: Per frame

    func frameColliders(time: Float) -> [Collider] {
        guard animateColliders else {
            return colliders.map(\.collider)
        }
        return colliders.enumerated().map { index, item in item.animated(time: time, index: index) }
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
            _ = try? system.setEmitters(emitters.map { ($0.settings, capacity) })
        }
        for (emitter, runtime) in zip(emitters, system.emitters) {
            runtime.settings = emitter.settings
            runtime.texture = texture(emitter.texture, device: system.device)
            runtime.simulationSpace = emitter.simulationSpace
            runtime.isEmitting = emitter.isEmitting
        }
    }

    private func texture(_ choice: DemoTexture, device: MTLDevice) -> MTLTexture? {
        if let cached = textureCache[choice] {
            return cached
        }
        let texture = choice.makeTexture(device: device)
        textureCache[choice] = texture
        return texture
    }
}
