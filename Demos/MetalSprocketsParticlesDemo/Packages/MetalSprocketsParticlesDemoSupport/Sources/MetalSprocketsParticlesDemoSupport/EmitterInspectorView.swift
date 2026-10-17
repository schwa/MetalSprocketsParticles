import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftUI

/// The demo's sidebar. The most-used controls stay visible at the top of each section; the rest are in disclosure
/// groups. Controls are small so more fit without scrolling.
struct EmitterInspectorView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Form {
            SceneSectionView(model: model)
            EmitterSectionView(model: model)
            EmissionSectionView(settings: $model.selectedEmitter.settings)
            ShapeSectionView(settings: $model.selectedEmitter.settings)
            MotionSectionView(emitter: $model.selectedEmitter)
            AppearanceSectionView(emitter: $model.selectedEmitter)
            CollisionSectionView(settings: $model.selectedEmitter.settings)
            SubEmittersSectionView(settings: $model.selectedEmitter.settings)
            TriggersSectionView(model: model)
            WorldSectionView(model: model)
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}

// MARK: - Scene and emitter

struct SceneSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Scene") {
            Picker("Preset", selection: $model.presetName) {
                ForEach(ParticlePreset.all) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            Picker("Playback", selection: $model.playback) {
                Label("Play", systemImage: "play.fill").tag(SimulationState.playing)
                Label("Pause", systemImage: "pause.fill").tag(SimulationState.paused)
                Label("Stop", systemImage: "stop.fill").tag(SimulationState.stopped)
            }
            .pickerStyle(.segmented)
            ParameterSliderView("Speed", value: $model.speedFactor, in: 0...3)
            HStack {
                Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                Button("Revert", systemImage: "arrow.uturn.backward") { model.reloadPreset() }
            }
        }
    }
}

struct EmitterSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Emitter") {
            HStack {
                Picker("Emitter", selection: $model.selectedEmitterID) {
                    ForEach(model.emitters) { emitter in
                        Text(emitter.name).tag(Optional(emitter.id))
                    }
                }
                Menu("Emitter Actions", systemImage: "ellipsis.circle") {
                    Button("Add", systemImage: "plus") { model.addEmitter() }
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelectedEmitter() }
                    Button("Remove", systemImage: "trash", role: .destructive) { model.removeSelectedEmitter() }
                        .disabled(model.emitters.count == 1)
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            TextField("Name", text: $model.selectedEmitter.name)
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
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Emission") {
            ParameterSliderView("Birth Rate", value: $settings.birthRate, in: 0...100_000, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Lifetime Min", value: $settings.lifetimeMinimum, in: 0.1...10)
            ParameterSliderView("Lifetime Max", value: $settings.lifetimeMaximum, in: 0.1...10)
            DisclosureGroup("Timing") {
                ParameterSliderView("Rate Variation", value: $settings.birthRateVariation, in: 0...50_000, format: .number.precision(.fractionLength(0)))
                ParameterSliderView("Warmup", value: $settings.warmupDuration, in: 0...5)
                Toggle("Limited Duration", isOn: $settings.hasLimitedEmission)
                if settings.hasLimitedEmission {
                    ParameterSliderView("Duration", value: $settings.limitedEmissionDuration, in: 0.1...10)
                    ParameterSliderView("Idle", value: $settings.idleDuration, in: 0...10)
                    Toggle("Loops", isOn: $settings.loops)
                }
            }
        }
    }
}

struct ShapeSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Shape") {
            Picker("Shape", selection: $settings.shapeKind) {
                ForEach(ShapeKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            switch settings.shapeKind {
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
            case .point:
                EmptyView()
            }
            DisclosureGroup("Placement") {
                if settings.shapeKind != .point {
                    Picker("Birth Location", selection: $settings.birthLocation) {
                        ForEach(ParticleBirthLocation.allCases) { location in
                            Text(location.name).tag(location)
                        }
                    }
                    ParameterSliderView("Sweep", value: $settings.sweepAngle, in: 0...(2 * .pi))
                }
                Picker("Birth Direction", selection: $settings.birthDirection) {
                    ForEach(ParticleBirthDirection.allCases) { direction in
                        Text(direction.name).tag(direction)
                    }
                }
                VectorEditorView("Position", value: $settings.position, in: -5...5)
            }
        }
    }
}

struct MotionSectionView: View {
    @Binding var emitter: DemoEmitter

    var body: some View {
        Section("Motion") {
            VectorEditorView("Velocity", value: $emitter.settings.velocity, in: -20...20)
            ParameterSliderView("Spread", value: $emitter.settings.velocitySpread, in: 0...10)
            VectorEditorView("Gravity", value: $emitter.settings.gravity, in: -20...20)
            ParameterSliderView("Drag", value: $emitter.settings.drag, in: 0...5)
            DisclosureGroup("Emitter Motion") {
                Picker("Path", selection: $emitter.motion.kind) {
                    ForEach(EmitterMotion.Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                if emitter.motion.kind != .still {
                    ParameterSliderView("Path Radius", value: $emitter.motion.radius, in: 0...4)
                    ParameterSliderView("Path Speed", value: $emitter.motion.speed, in: 0...5)
                }
                VectorEditorView("Offset", value: $emitter.motion.offset, in: -5...5)
                ParameterSliderView("Yaw", value: $emitter.motion.yaw, in: -.pi ... .pi)
                ParameterSliderView("Pitch", value: $emitter.motion.pitch, in: -.pi ... .pi)
                ParameterSliderView("Spin", value: $emitter.motion.spin, in: -10...10)
                Picker("Simulation Space", selection: $emitter.simulationSpace) {
                    ForEach(SimulationSpace.allCases) { space in
                        Text(space.name).tag(space)
                    }
                }
                ParameterSliderView("Inherit Velocity", value: $emitter.settings.inheritVelocity, in: 0...1)
            }
        }
    }
}

struct AppearanceSectionView: View {
    @Binding var emitter: DemoEmitter

    var body: some View {
        Section("Appearance") {
            Picker("Sprite", selection: $emitter.sprite) {
                ForEach(ParticleSprite.allCases) { sprite in
                    Text(sprite.rawValue).tag(sprite)
                }
            }
            Picker("Blend", selection: $emitter.settings.blendMode) {
                ForEach(ParticleBlendMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            Picker("Sort", selection: $emitter.settings.sortMode) {
                ForEach(ParticleSortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            Picker("Orientation", selection: $emitter.settings.orientationKind) {
                ForEach(OrientationKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            if emitter.settings.orientationKind == .velocityAligned {
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
        Picker("Playback", selection: $sequence.mode) {
            ForEach(ParticleImageSequenceMode.allCases) { mode in
                Text(mode.name).tag(mode)
            }
        }
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

    var body: some View {
        Section("Collision") {
            ParameterSliderView("Bounce", value: $settings.restitution, in: 0...1.5)
            ParameterSliderView("Friction", value: $settings.friction, in: 0...1)
            Toggle("Die on Collision", isOn: $settings.diesOnCollision)
        }
    }
}

// MARK: - Sub-emitters and triggers

/// Sub-emitters and trigger lists are library value types without ids, so rows are identified by position.
struct SubEmittersSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section {
            ForEach(settings.subEmitters.indices, id: \.self) { index in
                SubEmitterEditorView(subEmitter: $settings.subEmitters[index]) {
                    settings.subEmitters.remove(at: index)
                }
            }
            Button("Add Sub-Emitter", systemImage: "plus") {
                settings.subEmitters.append(.sparks)
            }
        } header: {
            Text("Sub-Emitters")
        } footer: {
            Text("Adding, removing, or resizing a sub-emitter clears the particles.")
        }
    }
}

struct SubEmitterEditorView: View {
    @Binding var subEmitter: SubEmitter
    let remove: () -> Void

    var body: some View {
        DisclosureGroup(subEmitter.occasionKind.rawValue) {
            Picker("Occasion", selection: $subEmitter.occasionKind) {
                ForEach(OccasionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            if subEmitter.occasionKind == .whileAlive {
                ParameterSliderView("Interval", value: $subEmitter.trailInterval, in: 0.005...0.5, format: .number.precision(.fractionLength(3)))
            }
            Stepper("Per Event: \(subEmitter.countPerEvent)", value: $subEmitter.countPerEvent, in: 1...1_000, step: 10)
            ParameterSliderView("Inherit Velocity", value: $subEmitter.velocityFactor, in: 0...1)
            ParameterSliderView("Lifetime Min", value: $subEmitter.settings.lifetimeMinimum, in: 0.05...5)
            ParameterSliderView("Lifetime Max", value: $subEmitter.settings.lifetimeMaximum, in: 0.05...5)
            VectorEditorView("Velocity", value: $subEmitter.settings.velocity, in: -10...10)
            ParameterSliderView("Spread", value: $subEmitter.settings.velocitySpread, in: 0...10)
            VectorEditorView("Gravity", value: $subEmitter.settings.gravity, in: -20...20)
            Picker("Blend", selection: $subEmitter.settings.blendMode) {
                ForEach(ParticleBlendMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            }
            ColorCurveEditorView(title: "Color", curve: $subEmitter.settings.colorOverLife)
            FloatCurveEditorView(title: "Size", curve: $subEmitter.settings.sizeOverLife, range: 0...0.5)
            Button("Remove Sub-Emitter", systemImage: "trash", role: .destructive, action: remove)
        }
    }
}

struct TriggersSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Triggers") {
            ForEach(model.selectedEmitter.settings.triggers.indices, id: \.self) { index in
                TriggerEditorView(trigger: $model.selectedEmitter.settings.triggers[index]) {
                    model.selectedEmitter.settings.triggers.remove(at: index)
                }
            }
            Button("Add Trigger", systemImage: "plus") {
                model.selectedEmitter.settings.triggers.append(EmissionTrigger(.event(model.eventToSend), .burst(100)))
            }
            HStack {
                TextField("Event", text: $model.eventToSend)
                Button("Send", systemImage: "paperplane") { model.sendEvent() }
            }
        }
    }
}

struct TriggerEditorView: View {
    @Binding var trigger: EmissionTrigger
    let remove: () -> Void

    var body: some View {
        DisclosureGroup("\(trigger.conditionKind.rawValue) → \(trigger.actionKind.rawValue)") {
            Picker("When", selection: $trigger.conditionKind) {
                ForEach(TriggerConditionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            switch trigger.conditionKind {
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
            Picker("Do", selection: $trigger.actionKind) {
                ForEach(TriggerActionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            if trigger.actionKind == .burst {
                Stepper("Burst: \(trigger.burstCount)", value: $trigger.burstCount, in: 1...100_000, step: 50)
            }
            Button("Remove Trigger", systemImage: "trash", role: .destructive, action: remove)
        }
    }
}

struct TriggerVolumeEditorView: View {
    @Binding var volume: TriggerVolume

    var body: some View {
        Toggle("Box", isOn: $volume.isBox)
        VectorEditorView("Center", value: $volume.center, in: -5...5)
        ParameterSliderView(volume.isBox ? "Half Size" : "Radius", value: $volume.radius, in: 0.05...5)
    }
}

// MARK: - World

struct WorldSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("World") {
            HStack {
                Toggle("Animate Colliders", isOn: $model.animateColliders)
                Toggle("Wireframes", isOn: $model.showColliders)
            }
            DisclosureGroup("Colliders (\(model.colliders.count))") {
                ForEach($model.colliders) { $item in
                    ColliderEditorView(collider: $item.collider) {
                        model.colliders.removeAll { $0.id == item.id }
                    }
                }
                Menu("Add Collider", systemImage: "plus") {
                    ForEach(ColliderKind.allCases) { kind in
                        Button(kind.rawValue) {
                            var collider = Collider.sphere(center: [0, 1, 0], radius: 0.5)
                            collider.kind = kind
                            model.colliders.append(ColliderItem(collider: collider))
                        }
                    }
                }
            }
            DisclosureGroup("Force Fields (\(model.forceFields.count))") {
                ForEach($model.forceFields) { $item in
                    ForceFieldEditorView(field: $item.field) {
                        model.forceFields.removeAll { $0.id == item.id }
                    }
                }
                Menu("Add Force Field", systemImage: "plus") {
                    ForEach(ForceFieldKind.allCases) { kind in
                        Button(kind.rawValue) {
                            var field = ForceField.wind(velocity: [2, 0, 0], strength: 1)
                            field.kind = kind
                            model.forceFields.append(ForceFieldItem(field: field))
                        }
                    }
                }
            }
        }
    }
}

struct ColliderEditorView: View {
    @Binding var collider: Collider
    let remove: () -> Void

    var body: some View {
        DisclosureGroup(collider.kind.rawValue) {
            Picker("Kind", selection: $collider.kind) {
                ForEach(ColliderKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            switch collider.kind {
            case .plane:
                ParameterSliderView("Height", value: $collider.center.y, in: -2...4)
            case .sphere:
                VectorEditorView("Center", value: $collider.center, in: -5...5)
                ParameterSliderView("Radius", value: $collider.radius, in: 0.05...3)
            case .box:
                VectorEditorView("Center", value: $collider.center, in: -5...5)
                VectorEditorView("Size", value: $collider.size, in: 0.05...5)
                ParameterSliderView("Tilt", value: $collider.tilt, in: -.pi ... .pi)
            case .capsule:
                VectorEditorView("Center", value: $collider.center, in: -5...5)
                ParameterSliderView("Length", value: $collider.length, in: 0...5)
                ParameterSliderView("Radius", value: $collider.radius, in: 0.05...2)
            }
            Button("Remove Collider", systemImage: "trash", role: .destructive, action: remove)
        }
    }
}

struct ForceFieldEditorView: View {
    @Binding var field: ForceField
    let remove: () -> Void

    var body: some View {
        DisclosureGroup(field.kind.rawValue) {
            Picker("Kind", selection: $field.kind) {
                ForEach(ForceFieldKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            ParameterSliderView("Strength", value: $field.strength, in: -20...20)
            switch field.kind {
            case .wind:
                VectorEditorView("Velocity", value: $field.windVelocity, in: -10...10)
            case .attractor, .vortex:
                VectorEditorView("Center", value: $field.center, in: -5...5)
                ParameterSliderView("Radius", value: $field.radius, in: 0...6)
            case .turbulence:
                ParameterSliderView("Scale", value: $field.turbulenceScale, in: 0.1...5)
                ParameterSliderView("Speed", value: $field.turbulenceSpeed, in: 0...3)
            }
            Button("Remove Field", systemImage: "trash", role: .destructive, action: remove)
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
    EmitterInspectorView(model: ParticlesDemoModel(preset: .fireworks))
        .frame(width: 380, height: 1_000)
}
