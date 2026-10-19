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
            case .emitter:
                EmitterSectionView()
                EmissionSectionView(settings: $model.selectedEmitter.settings, capacity: $model.selectedEmitter.editableCapacity)
                ShapeSectionView(settings: $model.selectedEmitter.settings)
                if [.mesh, .points].contains(model.selectedEmitter.settings.shape.kind) {
                    ShapeSourceSectionView(emitter: $model.selectedEmitter)
                }
                MotionSectionView(emitter: $model.selectedEmitter)
                AppearanceSectionView(emitter: $model.selectedEmitter)
                CollisionSectionView(settings: $model.selectedEmitter.settings)
                FlockingSectionView(settings: $model.selectedEmitter.settings)
                LevelOfDetailSectionView(settings: $model.selectedEmitter.settings)
            case let .subEmitter(_, index):
                if index < model.selectedEmitter.settings.subEmitters.count {
                    Section {
                        SubEmitterEditorView(subEmitter: $model.selectedSubEmitter)
                    } header: {
                        Text("Sub-Emitter of \(model.selectedEmitter.name)")
                    } footer: {
                        Text("Adding, removing, or resizing a sub-emitter clears the particles.")
                    }
                    RemoveSectionView(title: "Remove Sub-Emitter")
                }
            case let .trigger(_, index):
                if index < model.selectedEmitter.settings.triggers.count {
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
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    try model.openEffect(at: try result.get())
                } catch {
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
            .fileExporter(isPresented: $isExporting, item: model.currentEffect, contentTypes: [.json], defaultFilename: model.presetName) { result in
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
        }
    }
}

// MARK: - Selected emitter

struct EmissionSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @Binding var settings: ParticleEmitter
    /// The emitter's capacity. Changing it rebuilds the particle buffer and restarts the effect, so it applies when the
    /// field is committed, not per keystroke.
    @Binding var capacity: Int

    var body: some View {
        Section("Emission") {
            LabeledContent("Max Particles") {
                // Each new capacity rebuilds the buffer and restarts the effect, so only a finished number is applied.
                CommittedNumberField("Max Particles", value: $capacity)
                    .frame(width: 110)
            }
            .help("Particles this emitter can have alive at once. Changing it restarts the effect. The limit is the GPU's largest buffer (80 bytes a particle).")
            if let capacityError = model.capacityError {
                Label(capacityError, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let needed = settings.particlesNeeded(capacity: capacity) {
                Label("Needs about \(needed.formatted()) at this rate and lifetime; newest particles replace the oldest early.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ParameterSliderView("Birth Rate", value: $settings.birthRate, in: 0...100_000, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Lifetime", value: $settings.lifetimeAverage, in: 0.1...30)
                .help("Seconds each particle lives, on average. Type a value for longer lives.")
            ParameterSliderView("Lifetime Variation", value: $settings.lifetimeVariation, in: 0...15)
                .help("Each particle lives this many seconds more or less than Lifetime, at random.")
            DisclosureGroup("Timing") {
                ParameterSliderView("Rate Variation", value: $settings.birthRateVariation, in: 0...50_000, format: .number.precision(.fractionLength(0)))
                ParameterSliderView("Warmup", value: $settings.warmupDuration, in: 0...5)
                Toggle("Limited Duration", isOn: $settings.hasLimitedEmission)
                if settings.hasLimitedEmission {
                    ParameterSliderView("Duration", value: $settings.limitedEmissionDuration, in: 0.1...10)
                    ParameterSliderView("Idle", value: $settings.idleDuration, in: 0...10)
                    Toggle("Loops", isOn: $settings.loops)
                }
                // Birth-rate multiplier over seconds since the emitter started; ending at 0 makes a finite effect.
                FloatCurveEditorView(title: "Emission Over Time", curve: $settings.emissionOverTime, range: 0...1, timeRange: 0...30)
            }
        }
    }
}

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
            if emitter.settings.shape.kind == .mesh {
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

struct ShapeSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Shape") {
            KindPicker("Shape", selection: $settings.shape.kind)
            switch settings.shape.kind {
            case .sphere, .disc:
                ParameterSliderView("Radius", value: $settings.shapeRadius, in: 0...3)
            case .cylinder, .cone:
                ParameterSliderView("Radius", value: $settings.shapeRadius, in: 0...3)
                ParameterSliderView("Height", value: $settings.shapeSecondary, in: 0...3)
            case .torus:
                ParameterSliderView("Radius", value: $settings.shapeRadius, in: 0...3)
                ParameterSliderView("Tube Radius", value: $settings.shapeSecondary, in: 0...1)
            case .box, .plane:
                VectorEditorView("Size", value: $settings.shapeSize, in: 0...5)
            default:
                EmptyView()
            }
            DisclosureGroup("Placement") {
                if settings.shape.kind != .point {
                    KindPicker("Birth Location", selection: $settings.birthLocation)
                    ParameterSliderView("Sweep", value: $settings.sweepAngle, in: 0...(2 * .pi))
                }
                KindPicker("Birth Direction", selection: $settings.birthDirection)
                VectorEditorView("Position", value: $settings.position, in: -5...5)
            }
        }
    }
}

struct MotionSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @Binding var emitter: EmitterDescription

    var body: some View {
        @Bindable var model = model
        Section("Motion") {
            VectorEditorView("Velocity", value: $emitter.settings.velocity, in: -20...20)
            ParameterSliderView("Spread", value: $emitter.settings.velocitySpread, in: 0...10)
            VectorEditorView("Gravity", value: $emitter.settings.gravity, in: -20...20)
            ParameterSliderView("Drag", value: $emitter.settings.drag, in: 0...5)
            Toggle("Constrain to Plane", isOn: $emitter.settings.constrainsToPlane)
                .help("Keep particles on the emitter's XY plane, for 2D effects or flat sheets.")
            DisclosureGroup("Emitter Motion") {
                Toggle("Follow Pointer", isOn: $model.selectedEmitterFollowsPointer)
                KindPicker("Path", selection: $emitter.motion.kind)
                if emitter.motion.kind != .still {
                    ParameterSliderView("Path Radius", value: $emitter.motion.radius, in: 0...4)
                    ParameterSliderView("Path Speed", value: $emitter.motion.speed, in: 0...5)
                }
                VectorEditorView("Offset", value: $emitter.motion.offset, in: -5...5)
                ParameterSliderView("Yaw", value: $emitter.motion.yaw, in: -.pi ... .pi)
                ParameterSliderView("Pitch", value: $emitter.motion.pitch, in: -.pi ... .pi)
                ParameterSliderView("Spin", value: $emitter.motion.spin, in: -10...10)
                KindPicker("Simulation Space", selection: $emitter.simulationSpace)
                ParameterSliderView("Inherit Velocity", value: $emitter.settings.inheritVelocity, in: 0...1)
            }
        }
    }
}

struct AppearanceSectionView: View {
    @Binding var emitter: EmitterDescription

    var body: some View {
        Section("Appearance") {
            Picker("Draw As", selection: $emitter.settings.drawing) {
                ForEach(ParticleDrawing.allCases.filter { $0 != .custom || emitter.settings.drawing == .custom }) { drawing in
                    Text(drawing.rawValue).tag(drawing)
                }
            }
            .help("Sprites, or a small mesh per particle (lit, turned by the particle's orientation and spin).")
            KindPicker("Sprite", selection: $emitter.sprite)
            KindPicker("Blend", selection: $emitter.settings.blendMode)
            KindPicker("Sort", selection: $emitter.settings.sortMode)
            KindPicker("Orientation", selection: $emitter.settings.orientation.kind)
            Toggle("Lit", isOn: $emitter.settings.isLit)
            ParameterSliderView("Softness", value: $emitter.settings.softness, in: 0...1)
                .help("Soft particles: fade out over this distance in front of solid colliders instead of clipping hard. 0 turns it off.")
            if emitter.settings.orientation.kind == .velocityAligned {
                ParameterSliderView("Stretch", value: $emitter.settings.velocityStretch, in: 0...2)
            }
            DisclosureGroup("Curves") {
                ColorCurveEditorView(title: "Color", curve: $emitter.settings.colorOverLife)
                FloatCurveEditorView(title: "Opacity", curve: $emitter.settings.opacityOverLife, range: 0...1)
                FloatCurveEditorView(title: "Size", curve: $emitter.settings.sizeOverLife, range: 0...0.5)
            }
            DisclosureGroup("Rotation") {
                ParameterSliderView("Angle", value: $emitter.settings.angle, in: -.pi ... .pi)
                ParameterSliderView("Spin", value: $emitter.settings.angularSpeed, in: -20...20)
            }
            if emitter.sprite != .softDot {
                DisclosureGroup("Sprite Sheet") {
                    Toggle("Animate Frames", isOn: $emitter.settings.hasImageSequence)
                    if emitter.settings.hasImageSequence {
                        ImageSequenceEditorView(sequence: $emitter.settings.editableImageSequence)
                    }
                }
            }
            DisclosureGroup("Particle Lights") {
                ParticleLightsView(settings: $emitter.settings)
            }
            DisclosureGroup("Trails and Ribbons") {
                TrailsAndRibbonsView(settings: $emitter.settings)
            }
            DisclosureGroup("Color Effects") {
                ColorEffectsView(settings: $emitter.settings)
            }
            DisclosureGroup("Variation") {
                VariationControlsView(settings: $emitter.settings)
            }
        }
    }
}

/// Some of the emitter's particles light the scene (and other emitters' lit particles).
struct ParticleLightsView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Toggle("Emit Light", isOn: $settings.emitsLight)
            .help("Turns some of this emitter's particles into point lights each frame: sparks lighting smoke, fireflies on leaves.")
        if settings.emitsLight {
            ParameterSliderView("Lights", value: $settings.editableLight.editableCount, in: 1...32, format: .number.precision(.fractionLength(0)))
                .help("How many particles become lights, picked evenly across the emitter.")
            ColorPicker("Color", selection: $settings.editableLight.color.color, supportsOpacity: false)
            ParameterSliderView("Intensity", value: $settings.editableLight.intensity, in: 0...10)
            ParameterSliderView("Range", value: $settings.editableLight.range, in: 0...10)
            Toggle("Brightest Particles", isOn: $settings.editableLight.picksBrightest)
                .help("Each light takes the brightest particle in its share, so lights sit on the hottest sparks. Off is cheaper.")
        }
    }
}

/// Draw particles as ribbons: each through its own recent positions (a trail), or all joined in birth order (a ribbon).
struct TrailsAndRibbonsView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Toggle("Trail", isOn: $settings.hasTrail)
            .help("Each particle draws as a ribbon through its recent positions instead of a sprite.")
        if settings.hasTrail {
            ParameterSliderView("Points", value: $settings.editableTrail.editablePointCount, in: 2...64, format: .number.precision(.fractionLength(0)))
                .help("Positions kept per particle. Memory is 16 bytes per point per particle of every emitter.")
            ParameterSliderView("Point Interval", value: $settings.editableTrail.pointInterval, in: 0...0.2, format: .number.precision(.fractionLength(3)))
                .help("Seconds between recorded points, so trails cover the same time at any frame rate. 0 records one every step.")
            Toggle("Trail Tapers", isOn: $settings.editableTrail.tapers)
            Toggle("Trail Fades", isOn: $settings.editableTrail.fades)
        }
        Toggle("Ribbon", isOn: $settings.hasRibbon)
            .help("Joins the live particles into one ribbon in birth order. Takes the place of trails and mesh particles.")
        if settings.hasRibbon {
            Toggle("Ribbon Tapers", isOn: $settings.editableRibbon.tapers)
        }
    }
}

/// Colors on top of color over life: by speed, by position, a second gradient to blend toward, and an image.
struct ColorEffectsView: View {
    @Binding var settings: ParticleEmitter
    @State private var isChoosingImage = false
    @State private var isShowingImageError = false
    @State private var imageError = ""

    var body: some View {
        Toggle("Color by Speed", isOn: $settings.hasColorBySpeed)
            .help("Multiplies the color by a gradient sampled by speed: the slow end at the minimum speed and below, the fast end at the maximum and above.")
        if settings.hasColorBySpeed {
            ColorCurveEditorView(title: "Speed Gradient", curve: $settings.editableColorBySpeed)
            ParameterSliderView("Slow Speed", value: $settings.colorBySpeedMinimum, in: 0...20)
            ParameterSliderView("Fast Speed", value: $settings.colorBySpeedMaximum, in: 0...20)
        }
        Toggle("Color by Position", isOn: $settings.hasColorByPosition)
            .help("Multiplies the color by a gradient across the world, from Start to End.")
        if settings.hasColorByPosition {
            ColorCurveEditorView(title: "Position Gradient", curve: $settings.editableColorByPosition)
            VectorEditorView("Start", value: $settings.colorByPositionStart, in: -5...5)
            VectorEditorView("End", value: $settings.colorByPositionEnd, in: -5...5)
            Toggle("Sample at Birth", isOn: $settings.colorByPositionAtBirth)
                .help("Keep the color where each particle is born, instead of changing it as the particle moves.")
        }
        Toggle("Alternate Colors", isOn: $settings.hasAlternateColors)
            .help("Each particle blends between Color and this second gradient by its own random amount.")
        if settings.hasAlternateColors {
            ColorCurveEditorView(title: "Alternate", curve: $settings.editableAlternateColorOverLife)
        }
        LabeledContent("Color Image") {
            HStack {
                Button(settings.hasColorImage ? "Replace…" : "Choose…") { isChoosingImage = true }
                if settings.hasColorImage {
                    Button("Remove", role: .destructive) { settings.hasColorImage = false }
                }
            }
        }
        .help("Multiplies each particle's color by an image laid over the world, under the particle.")
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            chooseImage(result)
        }
        .alert("Color Image", isPresented: $isShowingImageError) {
            Button("OK") {}
        } message: {
            Text(imageError)
        }
        if settings.hasColorImage {
            VectorEditorView("Origin", value: $settings.editableColorImage.origin, in: -5...5)
            VectorEditorView("Width", value: $settings.editableColorImage.width, in: -5...5)
            VectorEditorView("Height", value: $settings.editableColorImage.height, in: -5...5)
        }
    }

    private func chooseImage(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            settings.colorImage = try ParticleColorImage.choosing(data: Data(contentsOf: url), replacing: settings.colorImage)
        } catch {
            imageError = error.localizedDescription
            isShowingImageError = true
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

struct VariationControlsView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        ParameterSliderView("Size", value: $settings.sizeVariation, in: 0...1)
        ParameterSliderView("Speed", value: $settings.speedVariation, in: 0...10)
        ParameterSliderView("Hue", value: $settings.colorVariation.x, in: 0...0.5)
        ParameterSliderView("Saturation", value: $settings.colorVariation.y, in: 0...1)
        ParameterSliderView("Brightness", value: $settings.colorVariation.z, in: 0...1)
        ParameterSliderView("Alpha", value: $settings.colorVariation.w, in: 0...1)
        ParameterSliderView("Angle", value: $settings.angleVariation, in: 0 ... .pi)
        ParameterSliderView("Spin", value: $settings.angularSpeedVariation, in: 0...20)
        ParameterSliderView("Bounce", value: $settings.restitutionVariation, in: 0...1)
        ParameterSliderView("Friction", value: $settings.frictionVariation, in: 0...1)
    }
}

struct CollisionSectionView: View {
    @Binding var settings: ParticleEmitter
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        Section("Collision") {
            ParameterSliderView("Bounce", value: $settings.restitution, in: 0...1.5)
            ParameterSliderView("Friction", value: $settings.friction, in: 0...1)
            Toggle("Die on Collision", isOn: $settings.diesOnCollision)
            ParameterSliderView("Radius", value: $settings.collisionRadius, in: 0...0.5, format: .number.precision(.fractionLength(3)))
                .help("Particles collide as spheres of this radius instead of points, so large sprites and mesh particles rest on colliders instead of sinking in.")
            Toggle("Collide with Scene Depth", isOn: $settings.collidesWithSceneDepth)
                .help("Bounce off whatever was drawn into the scene depth last frame (here, solid colliders). Only works on screen.")
            Toggle("Report Collisions", isOn: $settings.reportsCollisions)
                .help("Report each collider hit to the app (ParticleSystemRuntime.recentEvents), for sounds, decals, or event bursts.")
            Toggle("Report Deaths", isOn: $settings.reportsDeaths)
                .help("Report each particle death to the app (ParticleSystemRuntime.recentEvents).")
            CategoryMaskView(
                "Categories",
                mask: $settings.categoryMask,
                detail: "Matches \(categoryMatchCount(settings.categoryMask, categories: model.colliders.map(\.collider.categoryBitMask), noun: "collider")) and "
                    + categoryMatchCount(settings.categoryMask, categories: model.forceFields.map(\.field.categoryBitMask), noun: "field")
            )
            .help("Colliders and force fields apply when they share a category with the emitter. Give them different categories to feel one but not the other.")
        }
    }
}

/// Fewer or no particles where they matter less: distance LOD, culling, and a floor on on-screen size.
struct LevelOfDetailSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Level of Detail") {
            ParameterSliderView("Full Rate Within", value: $settings.lodNearDistance, in: 0...50)
                .help("Distance from the camera within which the emitter emits at its full rate.")
            ParameterSliderView("Reduced Rate At", value: $settings.lodFarDistance, in: 0...100)
                .help("Distance at which emission falls to the far rate. LOD is off unless this is farther than Full Rate Within.")
            ParameterSliderView("Far Rate", value: $settings.lodFarRateScale, in: 0...1)
                .help("Birth rate at the far distance, as a fraction of the full rate.")
            Toggle("Grow When Thinned", isOn: $settings.lodScalesSize)
                .help("Grows particles as LOD thins them, so the effect covers about the same area with fewer particles.")
            ParameterSliderView("Minimum Screen Size", value: $settings.minimumScreenSize, in: 0...0.02, format: .number.precision(.fractionLength(4)))
                .help("Far particles never draw smaller than this: half their size as a fraction of the view height (0.002 is about two pixels at 1080p). 0 lets them shrink.")
            ParameterSliderView("Culling Radius", value: $settings.cullingRadius, in: 0...20)
                .help("A sphere around the emitter that holds its particles; when it is out of view the emitter is not drawn. 0 never culls.")
            if settings.cullingRadius > 0 {
                Toggle("Simulate When Culled", isOn: $settings.simulatesWhenCulled)
                    .help("Keep simulating out of view, so the effect is right when it comes back. Off saves the work but freezes it.")
            }
        }
    }
}

struct FlockingSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Flocking") {
            Toggle("Flocks", isOn: $settings.isFlocking)
                .help("Particles steer by their neighbors: away from close ones, along with their heading, and toward their center. Costs a neighbor search each frame.")
            if settings.isFlocking {
                ParameterSliderView("Neighbor Radius", value: $settings.editableFlocking.radius, in: 0.01...2)
                    .help("How far a particle sees its neighbors. Smaller is faster.")
                ParameterSliderView("Separation Radius", value: $settings.editableFlocking.separationRadius, in: 0...1)
                    .help("Closer than this, neighbors push apart.")
                ParameterSliderView("Separation", value: $settings.editableFlocking.separation, in: 0...0.2, format: .number.precision(.fractionLength(3)))
                ParameterSliderView("Alignment", value: $settings.editableFlocking.alignment, in: 0...5)
                ParameterSliderView("Cohesion", value: $settings.editableFlocking.cohesion, in: 0...5)
                ParameterSliderView("Minimum Speed", value: $settings.editableFlocking.minimumSpeed, in: 0...10)
                ParameterSliderView("Maximum Speed", value: $settings.editableFlocking.maximumSpeed, in: 0...10)
                ParameterSliderView("Neighbors", value: $settings.editableFlocking.neighborLimit, in: 1...64, format: .number.precision(.fractionLength(0)))
                    .help("Neighbors counted per particle, to bound the cost in dense crowds.")
            }
        }
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
            Toggle("Replaces Parent", isOn: $subEmitter.replacesParent)
                .help("The parent dies when it spawns children, so it turns into them.")
            Toggle("Continues Parent's Life", isOn: $subEmitter.continuesParentLife)
                .help("Children keep the parent's age and lifetime instead of starting a new life.")
            KindPicker("Sprite", selection: $subEmitter.sprite)
            Stepper("Per Event: \(subEmitter.countPerEvent)", value: $subEmitter.countPerEvent, in: 1...1_000, step: 10)
            ParameterSliderView("Inherit Velocity", value: $subEmitter.velocityFactor, in: 0...1)
            ParameterSliderView("Lifetime", value: $subEmitter.settings.lifetimeAverage, in: 0.05...10)
            ParameterSliderView("Lifetime Variation", value: $subEmitter.settings.lifetimeVariation, in: 0...5)
            VectorEditorView("Velocity", value: $subEmitter.settings.velocity, in: -10...10)
            ParameterSliderView("Spread", value: $subEmitter.settings.velocitySpread, in: 0...10)
            VectorEditorView("Gravity", value: $subEmitter.settings.gravity, in: -20...20)
            KindPicker("Blend", selection: $subEmitter.settings.blendMode)
            ColorCurveEditorView(title: "Color", curve: $subEmitter.settings.colorOverLife)
            FloatCurveEditorView(title: "Size", curve: $subEmitter.settings.sizeOverLife, range: 0...0.5)
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
