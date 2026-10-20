import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftMesh
import SwiftUI
import UniformTypeIdentifiers

/// The trailing inspector: details for whatever the outline has selected. The most-used controls stay visible; the
/// rest are in disclosure groups. Controls are small so more fit without scrolling.
struct EmitterInspectorView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            switch model.selection {
            case .scene, nil:
                SceneSectionView()
                WorldSectionView()
                SendEventSectionView()
                EventBurstsSectionView()
                TrackedObjectsSectionView()
                ScriptedPointerSectionView()
            case .emitter:
                EmitterSectionView()
                AppearanceSectionView(emitter: $model.selectedEmitter)
                EmitterMotionSectionView(emitter: $model.selectedEmitter)
                if [.mesh, .points].contains(model.selectedEmitter.modules.shape?.kind) {
                    ShapeSourceSectionView(emitter: $model.selectedEmitter)
                }
                ModuleStacksView(modules: $model.selectedEmitter.modules)
                UserFunctionsSectionView(modules: $model.selectedEmitter.modules)
                    // Fresh drafts when another emitter is selected.
                    .id(model.selectedEmitter.id)
            case let .subEmitter(_, index):
                if index < model.selectedEmitter.modules.subEmitters.count {
                    Section {
                        SubEmitterEditorView(subEmitter: $model.selectedSubEmitter)
                    } header: {
                        Text("Sub-Emitter of \(model.selectedEmitter.name)")
                    } footer: {
                        Text("Adding, removing, or resizing a sub-emitter clears the particles. Its shape is centered on the parent particle; birth rate and timing are ignored.")
                    }
                    ModuleStacksView(modules: $model.selectedSubEmitter.modules)
                    RemoveSectionView(title: "Remove Sub-Emitter")
                }
            case let .module(_, stage, index):
                // Just this module; select the emitter for the rest.
                SingleModuleView(modules: $model.selectedEmitter.modules, stage: stage, index: index)
            case let .trigger(_, index):
                if index < model.selectedEmitter.modules.triggers.count {
                    Section("Trigger on \(model.selectedEmitter.name)") {
                        TriggerEditorView(trigger: $model.selectedTrigger)
                    }
                    SendEventSectionView()
                    RemoveSectionView(title: "Remove Trigger")
                }
            case let .collider(id):
                if model.colliders[id: id] != nil {
                    Section("Collider") {
                        ColliderEditorView(collider: $model.selectedCollider)
                        Toggle("Follow Pointer", isOn: $model.selectedColliderFollowsPointer)
                        Toggle("Spins", isOn: $model.selectedColliderSpins)
                            .help("Turn at a steady rate about the collider's center, flinging particles that rest on it.")
                        if model.selectedColliderSpins {
                            VectorEditorView("Spin Axis", value: $model.selectedColliderSpin.axis, in: -1...1)
                            ParameterSliderView("Spin Speed", value: $model.selectedColliderSpin.speed, in: -10...10)
                        }
                    }
                    RemoveSectionView(title: "Remove Collider")
                }
            case let .forceField(id):
                if model.forceFields[id: id] != nil {
                    Section("Force Field") {
                        ForceFieldEditorView(field: $model.selectedForceField)
                        Toggle("Follow Pointer", isOn: $model.selectedForceFieldFollowsPointer)
                            .help("Attractors and vortices center on the mouse. Wind and turbulence have no position.")
                    }
                    RemoveSectionView(title: "Remove Force Field")
                }
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

struct RemoveSectionView: View {
    let title: String
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        Section {
            Button(title, systemImage: "trash", role: .destructive) { model.removeSelection() }
        }
    }
}

struct SendEventSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Events") {
            HStack {
                TextField("Event", text: $model.eventToSend)
                Button("Send", systemImage: "paperplane") { model.sendEvent() }
            }
        }
    }
}

// MARK: - Scene and emitter

struct SceneSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        @Bindable var model = model
        Section(model.presetName) {
            if !model.presetComment.isEmpty {
                Text(model.presetComment)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
            }
            HStack {
                Button("Open Effect", systemImage: "folder") { isImporting = true }
                Button("Save Effect", systemImage: "square.and.arrow.down") { isExporting = true }
            }
            VideoExportView()
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.particleEffect, .json]) { result in
                do {
                    try model.openEffect(at: try result.get())
                } catch {
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
            .fileExporter(isPresented: $isExporting, document: ParticleEffectDocument(effect: model.currentEffect), contentType: .particleEffect, defaultFilename: model.presetName) { result in
                if case let .failure(error) = result {
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
            .alert("Effect File", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
}

/// Scene picker and playback controls, in the window toolbar so they stay visible. Each control is its own item.
struct SceneToolbarContent: ToolbarContent {
    @Environment(ParticlesDemoModel.self) private var model

    // Explicit groups with fixed spacers: left to itself, the toolbar merges neighboring items into capsules that cut
    // across these (the 2D toggle shared one with Next Preset).
    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItemGroup(placement: .principal) {
            Button("Previous Preset", systemImage: "chevron.backward") { model.stepPreset(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .help("Previous preset (⌘[)")
            Picker("Preset", selection: $model.presetName) {
                ForEach(model.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button("Next Preset", systemImage: "chevron.forward") { model.stepPreset(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .help("Next preset (⌘])")
        }
        ToolbarSpacer(.fixed, placement: .principal)
        ToolbarItem(placement: .principal) {
            Toggle("2D", systemImage: "view.2d", isOn: $model.is2D)
                .help("2D mode: the scene seen flat from the front, with every emitter kept on its plane")
        }
        ToolbarSpacer(.fixed, placement: .principal)
        ToolbarItem(placement: .principal) {
            Picker("Playback", selection: $model.playback) {
                Label("Play", systemImage: "play.fill").tag(SimulationState.playing)
                Label("Pause", systemImage: "pause.fill").tag(SimulationState.paused)
                Label("Stop", systemImage: "stop.fill").tag(SimulationState.stopped)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        ToolbarSpacer(.fixed, placement: .principal)
        ToolbarItemGroup(placement: .principal) {
            Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
            Button("Revert", systemImage: "arrow.uturn.backward") { model.reloadPreset() }
            SpeedControlView()
        }
    }
}

struct SpeedControlView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack {
            Slider(value: $model.speedFactor, in: 0...3) {
                Text("Speed")
            }
            .frame(width: 100)
            .help("Speed")
            Text(model.speedFactor, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}

/// Renders the current scene to a movie (5 s, 1080p, 30 fps) with progress, then asks where to keep it.
struct VideoExportView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var model = model
        Group {
            if let progress = model.videoExportProgress {
                ProgressView("Exporting video", value: progress)
            } else {
                Button("Export Video", systemImage: "film", action: export)
            }
        }
        .fileMover(isPresented: $model.isMovingExportedVideo, file: model.exportedVideo) { result in
            if case let .failure(error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Video Export Failed", isPresented: $errorMessage.isPresent) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func export() {
        Task {
            do {
                try await model.exportVideo()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension Optional {
    /// True when there is a value; setting false clears it. For alert and sheet bindings.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}

struct EmitterSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Emitter") {
            HStack {
                TextField("Name", text: $model.selectedEmitter.name)
                Menu("Emitter Actions", systemImage: "ellipsis.circle") {
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelectedEmitter() }
                    Button("Add Sub-Emitter", systemImage: "sparkles") { model.addSubEmitter(to: model.selectedEmitter.id) }
                    Button("Add Trigger", systemImage: "bolt") { model.addTrigger(to: model.selectedEmitter.id) }
                    Button("Remove", systemImage: "trash", role: .destructive) { model.removeSelectedEmitter() }
                        .disabled(model.emitters.count == 1)
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            HStack {
                Toggle("Emitting", isOn: $model.selectedEmitter.isEmitting)
                Spacer()
                Button("Burst", systemImage: "sparkles") { model.burstSelectedEmitter() }
            }
            CapacityView(emitter: $model.selectedEmitter)
        }
    }
}

// MARK: - Selected emitter

/// Where the Mesh and Point Cache shapes get their data: a mesh (built in, or a model file) with an optional wave, or
/// points from an image (or a point cache from a saved effect).
struct ShapeSourceSectionView: View {
    @Binding var emitter: EmitterDescription
    @State private var isImporting = false
    @State private var importing = Importing.model
    @State private var isShowingError = false
    @State private var errorMessage = ""

    enum Importing {
        case model
        case image
    }

    var body: some View {
        Section("Shape Source") {
            if emitter.modules.shape?.kind == .mesh {
                LabeledContent("Mesh") {
                    Menu(emitter.mesh.map { "\($0.positions.count) vertices" } ?? "None") {
                        ForEach(DemoMesh.allCases) { choice in
                            Button(choice.rawValue) { emitter.mesh = choice.mesh }
                        }
                        Divider()
                        Button("Model File…") {
                            importing = .model
                            isImporting = true
                        }
                    }
                    .fixedSize()
                }
                Toggle("Wave", isOn: $emitter.hasWaveDeformation)
                    .help("Ripples the mesh, so particles born on it move with the wave.")
                if emitter.hasWaveDeformation {
                    ParameterSliderView("Amplitude", value: $emitter.waveAmplitude, in: 0...1)
                    ParameterSliderView("Wavelength", value: $emitter.waveLength, in: 0.1...5)
                    ParameterSliderView("Speed", value: $emitter.waveSpeed, in: 0...5)
                }
            } else {
                LabeledContent("Points") {
                    HStack {
                        Button(emitter.image == nil ? "From Image…" : "Replace Image…") {
                            importing = .image
                            isImporting = true
                        }
                        if emitter.image != nil || emitter.points != nil {
                            Button("Clear", role: .destructive) {
                                emitter.image = nil
                                emitter.points = nil
                            }
                        }
                    }
                }
                if emitter.image != nil {
                    ParameterSliderView("Points", value: $emitter.editableImage.editablePointCount, in: 100...100_000, format: .number.precision(.fractionLength(0)))
                    ParameterSliderView("Width", value: $emitter.editableImage.width, in: 0.1...10)
                    Picker("Weighting", selection: $emitter.editableImage.weighting) {
                        ForEach(EmitterImage.Weighting.allCases, id: \.self) { weighting in
                            Text(weighting.rawValue.capitalized).tag(weighting)
                        }
                    }
                    .help("Alpha: opaque pixels emit (logos, emoji). Brightness: bright pixels emit more (photos, glows).")
                    Toggle("Use Image Colors", isOn: $emitter.editableImage.usesColors)
                } else if let points = emitter.points {
                    LabeledContent("Point Cache", value: "\(points.count) points")
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: importing == .image ? [.image] : [.threeDContent]) { result in
            load(result)
        }
        .alert("Shape Source", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if importing == .image {
                emitter.image = try EmitterImage.choosing(data: Data(contentsOf: url), replacing: emitter.image)
            } else {
                emitter.mesh = try Mesh.loadingFirstMesh(from: url, device: ParticleSystemRuntime.defaultDevice())
            }
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}

struct ImageSequenceEditorView: View {
    @Binding var sequence: ImageSequence

    var body: some View {
        Stepper("Rows: \(sequence.rows)", value: $sequence.gridRows, in: 1...16)
        Stepper("Columns: \(sequence.columns)", value: $sequence.gridColumns, in: 1...16)
        ParameterSliderView("Frame Rate", value: $sequence.frameRate, in: 0...60)
        ParameterSliderView("Rate Variation", value: $sequence.frameRateVariation, in: 0...30)
        ParameterSliderView("Start Frame", value: $sequence.initialFrame, in: 0...16)
        ParameterSliderView("Start Frame Variation", value: $sequence.initialFrameVariation, in: 0...16)
        KindPicker("Playback", selection: $sequence.mode)
    }
}

// MARK: - Sub-emitters and triggers

struct SubEmitterEditorView: View {
    @Binding var subEmitter: SubEmitter

    var body: some View {
        Group {
            KindPicker("Occasion", selection: $subEmitter.occasion.kind)
            if subEmitter.occasion.kind == .whileAlive {
                ParameterSliderView("Interval", value: $subEmitter.trailInterval, in: 0.005...0.5, format: .number.precision(.fractionLength(3)))
            }
            if subEmitter.occasion.kind == .age {
                ParameterSliderView("Age", value: $subEmitter.transitionAge, in: 0...10)
            }
            if subEmitter.occasion.kind == .enterVolume {
                TriggerVolumeEditorView(volume: $subEmitter.enteredVolume)
            }
            if subEmitter.occasion.kind == .glint {
                ParameterSliderView("Threshold", value: $subEmitter.glintThreshold, in: 0...1)
                    .help("Fires when the parent's glint rises past this. The parent needs Foil and to tumble (Tumbling sprites or meshes).")
            }
            Toggle("Replaces Parent", isOn: $subEmitter.replacesParent)
                .help("The parent dies when it spawns children, so it turns into them.")
            Toggle("Continues Parent's Life", isOn: $subEmitter.continuesParentLife)
                .help("Children keep the parent's age and lifetime instead of starting a new life.")
            KindPicker("Sprite", selection: $subEmitter.sprite)
            Stepper("Per Event: \(subEmitter.countPerEvent)", value: $subEmitter.countPerEvent, in: 1...1_000, step: 10)
            ParameterSliderView("Inherit Velocity", value: $subEmitter.velocityFactor, in: 0...1)
        }
    }
}

struct TriggerEditorView: View {
    @Binding var trigger: EmissionTrigger

    var body: some View {
        Group {
            KindPicker("When", selection: $trigger.condition.kind)
            switch trigger.condition.kind {
            case .event:
                TextField("Event Name", text: $trigger.eventName)
            case .after, .every:
                ParameterSliderView("Seconds", value: $trigger.seconds, in: 0.05...10)
            case .objectEnters:
                TextField("Object Name", text: $trigger.eventName)
                TriggerVolumeEditorView(volume: $trigger.volume)
            case .particlesEnter:
                TriggerVolumeEditorView(volume: $trigger.volume)
                Stepper("Count: \(trigger.threshold)", value: $trigger.threshold, in: 1...10_000)
            case .colliderHit:
                Stepper("Collider: \(trigger.colliderIndex)", value: $trigger.colliderIndex, in: 0...63)
                Stepper("Count: \(trigger.threshold)", value: $trigger.threshold, in: 1...10_000)
            }
            KindPicker("Do", selection: $trigger.action.kind)
            if trigger.action.kind == .burst {
                Stepper("Burst: \(trigger.burstCount)", value: $trigger.burstCount, in: 1...100_000, step: 50)
            }
        }
    }
}

struct TriggerVolumeEditorView: View {
    @Binding var volume: TriggerVolume

    var body: some View {
        KindPicker("Volume", selection: $volume.kind)
            .pickerStyle(.segmented)
        VectorEditorView("Center", value: $volume.center, in: -5...5)
        ParameterSliderView(volume.kind == .box ? "Half Size" : "Radius", value: $volume.radius, in: 0.05...5)
    }
}

// MARK: - World

struct WorldSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("World") {
            HStack {
                Toggle("Animate Colliders", isOn: $model.animateColliders)
                Toggle("Solid Colliders", isOn: $model.drawColliders)
                    .help("Draw colliders as solids. Emitters with Softness fade where they meet them.")
            }
        }
        LightingSectionView()
    }
}

/// The scene's lights and ambient light, for emitters with Lit on.
struct LightingSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Lighting") {
            ColorPicker("Ambient", selection: $model.ambientLight.color, supportsOpacity: false)
                .help("Light lit particles get from every direction.")
            ForEach($model.lights) { $item in
                LightEditorView(light: $item.light) {
                    model.lights.removeAll { $0.id == item.id }
                }
            }
            Button("Add Light", systemImage: "plus") { model.addLight() }
                .disabled(model.lights.count >= Int(PARTICLE_MAX_LIGHTS))
        }
    }
}

struct LightEditorView: View {
    @Binding var light: ParticleLight
    let remove: () -> Void

    var body: some View {
        DisclosureGroup(light.isPoint ? "Point Light" : "Directional Light") {
            Picker("Kind", selection: $light.isPoint) {
                Text("Directional").tag(false)
                Text("Point").tag(true)
            }
            ColorPicker("Color", selection: $light.color.color, supportsOpacity: false)
            ParameterSliderView("Intensity", value: $light.intensity, in: 0...10)
            if light.isPoint {
                VectorEditorView("Position", value: $light.position, in: -10...10)
                ParameterSliderView("Range", value: $light.range, in: 0...20)
                    .help("Light fades to zero at this distance. 0 means no falloff.")
            } else {
                VectorEditorView("Direction", value: $light.direction, in: -1...1)
            }
            Button("Remove Light", systemImage: "trash", role: .destructive, action: remove)
        }
    }
}

struct ColliderEditorView: View {
    @Binding var collider: Collider

    var body: some View {
        Group {
            KindPicker("Kind", selection: $collider.kind)
            switch collider.kind {
            case .plane:
                ParameterSliderView("Height", value: $collider.shape.center.y, in: -2...4)
            case .sphere:
                VectorEditorView("Center", value: $collider.shape.center, in: -5...5)
                ParameterSliderView("Radius", value: $collider.shape.radius, in: 0.05...3)
            case .box:
                VectorEditorView("Center", value: $collider.shape.center, in: -5...5)
                VectorEditorView("Size", value: $collider.shape.size, in: 0.05...5)
                ParameterSliderView("Tilt", value: $collider.shape.tilt, in: -.pi ... .pi)
            case .capsule:
                VectorEditorView("Center", value: $collider.shape.center, in: -5...5)
                ParameterSliderView("Length", value: $collider.shape.length, in: 0...5)
                ParameterSliderView("Radius", value: $collider.shape.radius, in: 0.05...2)
            case .signedDistanceField:
                VectorEditorView("Center", value: $collider.shape.center, in: -5...5)
                ParameterSliderView("Turn", value: $collider.shape.turn, in: -.pi ... .pi)
                DistanceFieldBakeView(collider: $collider)
            default:
                EmptyView()
            }
            CategoryMaskView("Categories", mask: $collider.categoryBitMask)
        }
    }
}

/// Bakes a distance field collider from a mesh: built in, extruded text, or a model file. The field has no surface to
/// draw, so the collider shows as its grid's bounds in wireframes.
struct DistanceFieldBakeView: View {
    @Binding var collider: Collider
    @State private var source = DistanceFieldSource.teapot
    @State private var text = "SDF"
    @State private var resolution: Float = 48
    @State private var padding: Float = 2
    @State private var insideOut = false
    @State private var isBaking = false
    @State private var bakeTime: Duration?
    @State private var isImporting = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        if case let .signedDistanceField(field, _, _) = collider.shape {
            LabeledContent("Grid", value: "\(field.resolution.x) × \(field.resolution.y) × \(field.resolution.z), cells \(field.spacing.max().formatted(.number.precision(.fractionLength(3))))")
                .help("Parts thinner than a couple of cells are blurred; bake at a higher resolution for them.")
        }
        DisclosureGroup("Bake") {
            LabeledContent("From") {
                Menu(sourceName) {
                    ForEach(DemoMesh.allCases) { choice in
                        Button(choice.rawValue) { source = .builtIn(choice) }
                    }
                    Button("Text") { source = .text(text) }
                    Divider()
                    Button("Model File…") { isImporting = true }
                }
                .fixedSize()
            }
            if case .text = source {
                TextField("Text", text: $text)
                    .onSubmit { source = .text(text) }
            }
            ParameterSliderView("Resolution", value: $resolution, in: 16...128, format: .number.precision(.fractionLength(0)))
                .help("Samples along the mesh's longest side. Memory and bake time grow with its cube.")
            ParameterSliderView("Padding", value: $padding, in: 0...8, format: .number.precision(.fractionLength(0)))
                .help("Cells of room around the mesh. More keeps containers (Inside Out) from leaking at the edge.")
            Toggle("Inside Out", isOn: $insideOut)
                .help("Negate the field, so the mesh's inside is a container particles stay in.")
            HStack {
                Button(isBaking ? "Baking…" : "Bake") { bake() }
                    .disabled(isBaking)
                if let bakeTime {
                    Text(bakeTime.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.threeDContent]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                source = .file(try Mesh.loadingFirstMesh(from: url, device: ParticleSystemRuntime.defaultDevice()))
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
        .alert("Distance Field", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var sourceName: String {
        switch source {
        case let .builtIn(choice): choice.rawValue
        case .text: "Text"
        case .file: "Model File"
        }
    }

    /// Bakes off the main thread (a detailed mesh at a high resolution takes a moment), then replaces the field,
    /// keeping the collider's place and turn.
    private func bake() {
        if case .text = source {
            source = .text(text)
        }
        guard case let .signedDistanceField(_, center, rotation) = collider.shape else {
            return
        }
        let source = source
        let resolution = Int(resolution)
        let padding = Int(padding)
        let insideOut = insideOut
        isBaking = true
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            let shape = await Task.detached {
                source.shape(resolution: resolution, padding: padding, insideOut: insideOut, center: center, rotation: rotation)
            }.value
            bakeTime = clock.now - start
            isBaking = false
            if let shape {
                collider.shape = shape
            } else {
                errorMessage = "The mesh has no triangles to bake."
                isShowingError = true
            }
        }
    }
}

struct ForceFieldEditorView: View {
    @Binding var field: ForceField

    var body: some View {
        Group {
            KindPicker("Kind", selection: $field.kind)
            ParameterSliderView("Strength", value: $field.effect.strength, in: -20...20)
            switch field.kind {
            case .wind:
                VectorEditorView("Velocity", value: $field.effect.windVelocity, in: -10...10)
            case .attractor, .vortex:
                VectorEditorView("Center", value: $field.effect.center, in: -5...5)
                ParameterSliderView("Radius", value: $field.effect.radius, in: 0...6)
            case .turbulence:
                ParameterSliderView("Scale", value: $field.effect.turbulenceScale, in: 0.1...5)
                ParameterSliderView("Speed", value: $field.effect.turbulenceSpeed, in: 0...3)
            default:
                EmptyView()
            }
            CategoryMaskView("Categories", mask: $field.categoryBitMask)
        }
    }
}

extension ImageSequence {
    /// Rows; keeps `frameCount` covering the whole grid.
    var gridRows: Int {
        get { rows }
        set {
            rows = newValue
            frameCount = rows * columns
        }
    }

    /// Columns; keeps `frameCount` covering the whole grid.
    var gridColumns: Int {
        get { columns }
        set {
            columns = newValue
            frameCount = rows * columns
        }
    }
}

#Preview("Inspector") {
    EmitterInspectorView()
        .environment(ParticlesDemoModel(preset: .fireworks))
        .frame(width: 380, height: 1_000)
}
