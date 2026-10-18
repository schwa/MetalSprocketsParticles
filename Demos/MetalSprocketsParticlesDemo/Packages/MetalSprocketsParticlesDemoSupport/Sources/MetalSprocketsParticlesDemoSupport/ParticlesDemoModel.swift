import Metal
import MetalSprocketsParticles
import Observation
import simd

/// Demo state edited by the inspector. Each change is pushed to the particle system.
@Observable
@MainActor
final class ParticlesDemoModel {
    @ObservationIgnored let system: ParticleSystem?

    /// The preset last loaded. Choosing another loads it, replacing emitters, colliders, and force fields.
    var presetName: String {
        didSet {
            if presetName != oldValue, let preset = ParticlePreset.named(presetName) {
                load(preset)
            }
        }
    }

    var emitters: [EmitterDescription] = [] {
        didSet { _ = try? system?.apply(emitters) }
    }

    var selectedEmitterID: EmitterDescription.ID?

    /// What the outline has selected and the inspector shows. Selecting an emitter or one of its children also
    /// selects that emitter.
    var selection: OutlineItem? = .scene {
        didSet {
            if let emitterID = selection?.emitterID {
                selectedEmitterID = emitterID
            }
        }
    }

    /// The emitter the inspector edits. Falls back to the first emitter.
    var selectedEmitter: EmitterDescription {
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

    /// The event name the inspector's Send button fires.
    var eventToSend = "boom"

    func sendEvent() {
        system?.send(event: eventToSend)
    }

    /// The preset's suggested camera, updated on load.
    private(set) var cameraEye: SIMD3<Float> = [0, 3, 6]
    private(set) var cameraTarget: SIMD3<Float> = [0, 1.5, 0]

    init(preset: ParticlePreset = .fountain) {
        system = try? ParticleSystem(emitters: [], capacity: 1)
        presetName = preset.name
        load(preset)
    }

    func load(_ preset: ParticlePreset) {
        // Fresh ids, so loading the same preset again rebuilds and clears the particles.
        let emitters = preset.layers.map { $0.copy() }
        self.emitters = emitters
        selectedEmitterID = emitters.first?.id
        if selection != .scene {
            selection = emitters.first.map { .emitter($0.id) }
        }
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
        let emitter = EmitterDescription("Emitter \(emitters.count + 1)", settings: settings)
        emitters.append(emitter)
        selection = .emitter(emitter.id)
    }

    func duplicateSelectedEmitter() {
        let copy = selectedEmitter.copy(named: "\(selectedEmitter.name) Copy")
        emitters.append(copy)
        selection = .emitter(copy.id)
    }

    /// Keeps at least one emitter.
    func removeSelectedEmitter() {
        guard emitters.count > 1, let index = emitters.firstIndex(where: { $0.id == selectedEmitter.id }) else {
            return
        }
        emitters.remove(at: index)
        selection = .emitter(emitters[min(index, emitters.count - 1)].id)
    }

    // MARK: Outline

    func addSubEmitter(to emitterID: EmitterDescription.ID) {
        guard let index = emitters.firstIndex(where: { $0.id == emitterID }) else {
            return
        }
        emitters[index].settings.subEmitters.append(.sparks)
        selection = .subEmitter(emitterID, emitters[index].settings.subEmitters.count - 1)
    }

    func addTrigger(to emitterID: EmitterDescription.ID) {
        guard let index = emitters.firstIndex(where: { $0.id == emitterID }) else {
            return
        }
        emitters[index].settings.triggers.append(EmissionTrigger(.event(eventToSend), .burst(100)))
        selection = .trigger(emitterID, emitters[index].settings.triggers.count - 1)
    }

    func addCollider(_ kind: ColliderKind) {
        var collider = Collider.sphere(center: [0, 1, 0], radius: 0.5)
        collider.kind = kind
        let item = ColliderItem(collider: collider)
        colliders.append(item)
        selection = .collider(item.id)
    }

    func addForceField(_ kind: ForceFieldKind) {
        var field = ForceField.wind(velocity: [2, 0, 0], strength: 1)
        field.kind = kind
        let item = ForceFieldItem(field: field)
        forceFields.append(item)
        selection = .forceField(item.id)
    }

    /// Removes the selected item and selects its parent (or the scene). Emitters keep at least one.
    func removeSelection() {
        switch selection {
        case .emitter:
            removeSelectedEmitter()
        case let .subEmitter(emitterID, index):
            if let emitter = emitters.firstIndex(where: { $0.id == emitterID }), index < emitters[emitter].settings.subEmitters.count {
                emitters[emitter].settings.subEmitters.remove(at: index)
            }
            selection = .emitter(emitterID)
        case let .trigger(emitterID, index):
            if let emitter = emitters.firstIndex(where: { $0.id == emitterID }), index < emitters[emitter].settings.triggers.count {
                emitters[emitter].settings.triggers.remove(at: index)
            }
            selection = .emitter(emitterID)
        case let .collider(id):
            colliders.removeAll { $0.id == id }
            selection = .scene
        case let .forceField(id):
            forceFields.removeAll { $0.id == id }
            selection = .scene
        case .scene, nil:
            break
        }
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
}
