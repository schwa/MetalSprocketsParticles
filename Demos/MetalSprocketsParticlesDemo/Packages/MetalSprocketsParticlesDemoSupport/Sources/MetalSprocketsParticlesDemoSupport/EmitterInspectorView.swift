import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
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
                MotionSectionView(emitter: $model.selectedEmitter)
                AppearanceSectionView(emitter: $model.selectedEmitter)
                CollisionSectionView(settings: $model.selectedEmitter.settings)
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
            Toggle("2D", systemImage: "square.on.square", isOn: $model.is2D)
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
            KindPicker("Sprite", selection: $emitter.sprite)
            KindPicker("Blend", selection: $emitter.settings.blendMode)
            KindPicker("Sort", selection: $emitter.settings.sortMode)
            KindPicker("Orientation", selection: $emitter.settings.orientation.kind)
            Toggle("Lit", isOn: $emitter.settings.isLit)
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
            DisclosureGroup("Variation") {
                VariationControlsView(settings: $emitter.settings)
            }
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
            default:
                EmptyView()
            }
            CategoryMaskView("Categories", mask: $collider.categoryBitMask)
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
