import Foundation
import Metal
import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
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
            if presetName != oldValue, let preset = preset(named: presetName) {
                load(preset)
            }
        }
    }

    var emitters: [EmitterDescription] = [] {
        didSet { _ = try? system?.apply(emitters) }
    }

    var selectedEmitterID: EmitterDescription.ID?

    private static let placeholderEmitter = EmitterDescription("No Emitter", settings: ParticleEmitter(), isEmitting: false)

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
        // An effect file can have no emitters; then reads get a placeholder and writes (unknown id) are dropped.
        get { emitters.first { $0.id == selectedEmitterID } ?? emitters.first ?? Self.placeholderEmitter }
        set {
            if let index = emitters.firstIndex(where: { $0.id == newValue.id }) {
                emitters[index] = newValue
            }
        }
    }

    // The selected collider and force field for the inspector. Never optional: after a removal, SwiftUI can read an
    // editor's bindings once more before the inspector stops showing it, so a missing item reads as a harmless
    // placeholder and writes to it are dropped.

    var selectedCollider: Collider {
        get {
            guard case let .collider(id) = selection, let item = colliders[id: id] else {
                return .plane(normal: [0, 1, 0], distance: 0)
            }
            return item.collider
        }
        set {
            if case let .collider(id) = selection, let index = colliders.firstIndex(where: { $0.id == id }) {
                colliders[index].collider = newValue
            }
        }
    }

    var selectedSubEmitter: SubEmitter {
        get {
            guard case let .subEmitter(_, index) = selection, index < selectedEmitter.settings.subEmitters.count else {
                return SubEmitter(occasion: .onDeath, countPerEvent: 1, settings: ParticleEmitter())
            }
            return selectedEmitter.settings.subEmitters[index]
        }
        set {
            if case let .subEmitter(_, index) = selection, index < selectedEmitter.settings.subEmitters.count {
                selectedEmitter.settings.subEmitters[index] = newValue
            }
        }
    }

    var selectedTrigger: EmissionTrigger {
        get {
            guard case let .trigger(_, index) = selection, index < selectedEmitter.settings.triggers.count else {
                return EmissionTrigger(.event(""), .start)
            }
            return selectedEmitter.settings.triggers[index]
        }
        set {
            if case let .trigger(_, index) = selection, index < selectedEmitter.settings.triggers.count {
                selectedEmitter.settings.triggers[index] = newValue
            }
        }
    }

    var selectedForceField: ForceField {
        get {
            guard case let .forceField(id) = selection, let item = forceFields[id: id] else {
                return .wind(velocity: .zero, strength: 0)
            }
            return item.field
        }
        set {
            if case let .forceField(id) = selection, let index = forceFields.firstIndex(where: { $0.id == id }) {
                forceFields[index].field = newValue
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

    // MARK: Effect files

    /// Effects opened from files this session, listed after the built-in presets.
    private(set) var openedEffects: [ParticlePreset] = []

    var presets: [ParticlePreset] {
        ParticlePreset.all + openedEffects
    }

    func preset(named name: String) -> ParticlePreset? {
        presets.first { $0.name == name }
    }

    /// The scene as it is now, for saving.
    var currentEffect: ParticlePreset {
        ParticlePreset(
            presetName,
            layers: emitters,
            colliders: colliders.map(\.collider),
            animatesColliders: animateColliders,
            forceFields: forceFields.map(\.field),
            lights: system?.lights ?? [],
            ambientLight: system?.ambientLight ?? [0.25, 0.25, 0.25],
            trackedObjects: trackedObjects,
            cameraEye: cameraEye,
            cameraTarget: cameraTarget
        )
        .commented(presetComment)
    }

    /// Reads a saved effect and loads it, named after the file.
    func openEffect(at url: URL) throws {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        open(try ParticlePreset(contentsOf: url), named: url.deletingPathExtension().lastPathComponent)
    }

    /// Adds an opened effect under `name` (made unique against built-in presets) and loads it.
    func open(_ effect: ParticlePreset, named name: String) {
        var effect = effect
        effect.name = ParticlePreset.all.contains { $0.name == name } ? "\(name) (File)" : name
        openedEffects.removeAll { $0.name == effect.name }
        openedEffects.append(effect)
        if presetName == effect.name {
            load(effect)
        } else {
            presetName = effect.name
        }
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
        system?.lights = preset.lights
        system?.ambientLight = preset.ambientLight
        trackedObjects = preset.trackedObjects
        presetComment = preset.comment
        cameraEye = preset.cameraEye
        cameraTarget = preset.cameraTarget
    }

    /// Reloads the current preset, discarding edits.
    func reloadPreset() {
        if let preset = preset(named: presetName) {
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

    func addCollider(_ kind: ParticleColliderKind) {
        var collider = Collider.sphere(center: [0, 1, 0], radius: 0.5)
        collider.kind = kind
        let item = ColliderItem(collider: collider)
        colliders.append(item)
        selection = .collider(item.id)
    }

    func addForceField(_ kind: ParticleForceFieldKind) {
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

    // MARK: Video export

    /// Fraction done while a video export runs; nil otherwise.
    private(set) var videoExportProgress: Double?
    /// The finished movie, in a temporary folder, waiting to be moved where the user chooses.
    var exportedVideo: URL?
    /// True while the finished movie waits for the user to pick a location.
    var isMovingExportedVideo = false

    /// Renders the current scene (with edits) from the start to a temporary movie, off the main actor, then offers it
    /// to be moved. Uses the preset's camera, not the interactive one.
    func exportVideo(duration: TimeInterval = 5, size: CGSize = CGSize(width: 1920, height: 1080), frameRate: Double = 30) async throws {
        let effect = currentEffect
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(effect.name).mov")
        videoExportProgress = 0
        defer { videoExportProgress = nil }
        _ = try await Task.detached {
            try await effect.exportVideo(to: url, size: size, frameRate: frameRate, duration: duration) { fraction in
                Task { @MainActor in
                    self.videoExportProgress = fraction
                }
                return true
            }
        }.value
        exportedVideo = url
        isMovingExportedVideo = true
    }

    /// What the loaded preset shows, for the inspector.
    private(set) var presetComment = ""

    /// The preset's stand-ins for app objects, for objectEnters triggers.
    var trackedObjects: [String: EmitterMotion] = [:]

    /// Tracked object positions at `time`, for `ParticleSystem.trackedObjects`.
    func frameTrackedObjects(time: Float) -> [String: SIMD3<Float>] {
        trackedObjects.mapValues { motion in
            let column = motion.transform(time: time).columns.3
            return SIMD3(column.x, column.y, column.z)
        }
    }

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
