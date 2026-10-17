import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftUI

struct EmitterInspectorView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Form {
            PresetSectionView(model: model)
            PlaybackSectionView(model: model)
            EmittersSectionView(model: model)
            ShapeSectionView(settings: $model.selectedEmitter.settings)
            EmissionSectionView(settings: $model.selectedEmitter.settings)
            MotionSectionView(emitter: $model.selectedEmitter)
            AppearanceSectionView(emitter: $model.selectedEmitter)
            VariationSectionView(settings: $model.selectedEmitter.settings)
            CollisionSectionView(settings: $model.selectedEmitter.settings)
            CollidersSectionView(model: model)
            ForceFieldsSectionView(model: model)
        }
        .formStyle(.grouped)
    }
}

struct PresetSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Preset") {
            Picker("Preset", selection: $model.presetName) {
                ForEach(ParticlePreset.all) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            Button("Revert Changes", systemImage: "arrow.uturn.backward") { model.reloadPreset() }
        }
    }
}

struct PlaybackSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Playback") {
            Picker("State", selection: $model.playback) {
                Text("Play").tag(SimulationState.playing)
                Text("Pause").tag(SimulationState.paused)
                Text("Stop").tag(SimulationState.stopped)
            }
            .pickerStyle(.segmented)
            ParameterSliderView("Speed", value: $model.speedFactor, in: 0...3)
            Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
        }
    }
}

struct EmittersSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Emitters") {
            Picker("Editing", selection: $model.selectedEmitterID) {
                ForEach(model.emitters) { emitter in
                    Text(emitter.name).tag(Optional(emitter.id))
                }
            }
            TextField("Name", text: $model.selectedEmitter.name)
            Toggle("Emitting", isOn: $model.selectedEmitter.isEmitting)
            HStack {
                Button("Add", systemImage: "plus") { model.addEmitter() }
                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelectedEmitter() }
                Button("Remove", systemImage: "trash") { model.removeSelectedEmitter() }
                    .disabled(model.emitters.count == 1)
                Button("Burst", systemImage: "sparkles") { model.burstSelectedEmitter() }
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
            if settings.shapeKind != .point {
                Picker("Birth Location", selection: $settings.birthLocation) {
                    ForEach(ParticleBirthLocation.allCases) { location in
                        Text(location.name).tag(location)
                    }
                }
                Picker("Birth Direction", selection: $settings.birthDirection) {
                    ForEach(ParticleBirthDirection.allCases) { direction in
                        Text(direction.name).tag(direction)
                    }
                }
                ParameterSliderView("Sweep", value: $settings.sweepAngle, in: 0...(2 * .pi))
            }
            VectorEditorView("Position", value: $settings.position, in: -5...5)
        }
    }
}

struct EmissionSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Emission") {
            ParameterSliderView("Birth Rate", value: $settings.birthRate, in: 0...100_000, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Rate Variation", value: $settings.birthRateVariation, in: 0...50_000, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Lifetime Min", value: $settings.lifetimeMinimum, in: 0.1...10)
            ParameterSliderView("Lifetime Max", value: $settings.lifetimeMaximum, in: 0.1...10)
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

struct MotionSectionView: View {
    @Binding var emitter: DemoEmitter

    var body: some View {
        Section("Motion") {
            VectorEditorView("Velocity", value: $emitter.settings.velocity, in: -20...20)
            ParameterSliderView("Spread", value: $emitter.settings.velocitySpread, in: 0...10)
            ParameterSliderView("Speed Variation", value: $emitter.settings.speedVariation, in: 0...10)
            VectorEditorView("Gravity", value: $emitter.settings.gravity, in: -20...20)
            ParameterSliderView("Drag", value: $emitter.settings.drag, in: 0...5)
            Picker("Emitter Motion", selection: $emitter.motion.kind) {
                ForEach(EmitterMotion.Kind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            if emitter.motion.kind != .still {
                ParameterSliderView("Motion Radius", value: $emitter.motion.radius, in: 0...4)
                ParameterSliderView("Motion Speed", value: $emitter.motion.speed, in: 0...5)
            }
            VectorEditorView("Emitter Offset", value: $emitter.motion.offset, in: -5...5)
            ParameterSliderView("Emitter Yaw", value: $emitter.motion.yaw, in: -.pi ... .pi)
            ParameterSliderView("Emitter Pitch", value: $emitter.motion.pitch, in: -.pi ... .pi)
            ParameterSliderView("Emitter Spin", value: $emitter.motion.spin, in: -10...10)
            Picker("Simulation Space", selection: $emitter.simulationSpace) {
                ForEach(SimulationSpace.allCases) { space in
                    Text(space.name).tag(space)
                }
            }
            ParameterSliderView("Inherit Velocity", value: $emitter.settings.inheritVelocity, in: 0...1)
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
            if emitter.sprite != .softDot {
                Toggle("Sprite Sheet", isOn: $emitter.settings.hasImageSequence)
                if emitter.settings.hasImageSequence {
                    ImageSequenceEditorView(sequence: $emitter.settings.editableImageSequence)
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
            ColorCurveEditorView(title: "Color Over Life", curve: $emitter.settings.colorOverLife)
            FloatCurveEditorView(title: "Opacity Over Life", curve: $emitter.settings.opacityOverLife, range: 0...1)
            FloatCurveEditorView(title: "Size Over Life", curve: $emitter.settings.sizeOverLife, range: 0...0.5)
            ParameterSliderView("Angle", value: $emitter.settings.angle, in: -.pi ... .pi)
            ParameterSliderView("Spin", value: $emitter.settings.angularSpeed, in: -20...20)
        }
    }
}

struct ImageSequenceEditorView: View {
    @Binding var sequence: ImageSequence

    var body: some View {
        Stepper("Rows: \(sequence.rows)", value: $sequence.gridRows, in: 1...16)
        Stepper("Columns: \(sequence.columns)", value: $sequence.gridColumns, in: 1...16)
        ParameterSliderView("Frame Rate", value: $sequence.frameRate, in: 0...60)
        ParameterSliderView("Frame Rate Variation", value: $sequence.frameRateVariation, in: 0...30)
        ParameterSliderView("Initial Frame Variation", value: $sequence.initialFrameVariation, in: 0...16)
        Picker("Playback", selection: $sequence.mode) {
            ForEach(ParticleImageSequenceMode.allCases) { mode in
                Text(mode.name).tag(mode)
            }
        }
    }
}

struct VariationSectionView: View {
    @Binding var settings: ParticleEmitter

    var body: some View {
        Section("Variation") {
            ParameterSliderView("Size", value: $settings.sizeVariation, in: 0...1)
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

struct CollidersSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Colliders") {
            Toggle("Animate", isOn: $model.animateColliders)
            Toggle("Show Wireframes", isOn: $model.showColliders)
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

struct ForceFieldsSectionView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Section("Force Fields") {
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
    EmitterInspectorView(model: ParticlesDemoModel())
        .frame(width: 380, height: 1_000)
}
