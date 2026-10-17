import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftUI

struct EmitterInspectorView: View {
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        Form {
            Section("Playback") {
                Picker("State", selection: $model.playback) {
                    Text("Play").tag(SimulationState.playing)
                    Text("Pause").tag(SimulationState.paused)
                    Text("Stop").tag(SimulationState.stopped)
                }
                .pickerStyle(.segmented)
                ParameterSliderView("Speed", value: $model.speedFactor, in: 0...3)
                Toggle("Emitting", isOn: $model.isEmitting)
                HStack {
                    Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                    Button("Burst", systemImage: "sparkles") { model.burst() }
                }
            }

            Section("Emission") {
                ParameterSliderView("Birth Rate", value: $model.emitter.birthRate, in: 0...100_000, format: .number.precision(.fractionLength(0)))
                ParameterSliderView("Rate Variation", value: $model.emitter.birthRateVariation, in: 0...50_000, format: .number.precision(.fractionLength(0)))
                ParameterSliderView("Lifetime Min", value: $model.emitter.lifetimeMinimum, in: 0.1...10)
                ParameterSliderView("Lifetime Max", value: $model.emitter.lifetimeMaximum, in: 0.1...10)
                Toggle("Limited Duration", isOn: $model.emitter.hasLimitedEmission)
                if model.emitter.hasLimitedEmission {
                    ParameterSliderView("Duration", value: $model.emitter.limitedEmissionDuration, in: 0.1...10)
                    ParameterSliderView("Idle", value: $model.emitter.idleDuration, in: 0...10)
                    Toggle("Loops", isOn: $model.emitter.loops)
                }
            }

            Section("Motion") {
                ParameterSliderView("Launch Speed", value: $model.emitter.launchSpeed, in: -10...20)
                ParameterSliderView("Spread", value: $model.emitter.velocitySpread, in: 0...10)
                ParameterSliderView("Speed Variation", value: $model.emitter.speedVariation, in: 0...10)
                ParameterSliderView("Gravity", value: $model.emitter.gravityY, in: -20...20)
                ParameterSliderView("Drag", value: $model.emitter.drag, in: 0...5)
                ParameterSliderView("Turbulence", value: $model.forceFields.turbulenceStrength, in: 0...20)
                ParameterSliderView("Vortex", value: $model.forceFields.vortexStrength, in: -20...20)
            }

            Section("Appearance") {
                Picker("Blend", selection: $model.emitter.blendMode) {
                    ForEach(ParticleBlendMode.allCases) { mode in
                        Text(mode.name).tag(mode)
                    }
                }
                Picker("Orientation", selection: $model.emitter.orientationKind) {
                    ForEach(OrientationKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                if model.emitter.orientationKind == .velocityAligned {
                    ParameterSliderView("Stretch", value: $model.emitter.velocityStretch, in: 0...2)
                }
                ColorPicker("Start Color", selection: $model.emitter.colorOverLife.startColor)
                ColorPicker("End Color", selection: $model.emitter.colorOverLife.endColor)
                ParameterSliderView("Hue Variation", value: $model.emitter.hueVariation, in: 0...0.5)
                ParameterSliderView("Start Size", value: $model.emitter.sizeStart, in: 0...0.3, format: .number.precision(.fractionLength(3)))
                ParameterSliderView("End Size", value: $model.emitter.sizeEnd, in: 0...0.3, format: .number.precision(.fractionLength(3)))
                ParameterSliderView("Size Variation", value: $model.emitter.sizeVariation, in: 0...1)
            }

            Section("Collision") {
                Toggle("Animate Colliders", isOn: $model.animateColliders)
                Toggle("Show Colliders", isOn: $model.showColliders)
                ParameterSliderView("Bounce", value: $model.emitter.restitution, in: 0...1.5)
                ParameterSliderView("Bounce Variation", value: $model.emitter.restitutionVariation, in: 0...1)
                ParameterSliderView("Friction", value: $model.emitter.friction, in: 0...1)
            }

            Section {
                Button("Reset Emitter", systemImage: "arrow.uturn.backward") { model.resetEmitter() }
            }
        }
        .formStyle(.grouped)
    }
}

/// A labeled slider with its current value.
struct ParameterSliderView: View {
    let title: LocalizedStringKey
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: FloatingPointFormatStyle<Float>

    init(_ title: LocalizedStringKey, value: Binding<Float>, in range: ClosedRange<Float>, format: FloatingPointFormatStyle<Float> = .number.precision(.fractionLength(2))) {
        self.title = title
        _value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: range)
                Text(value, format: format)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}

#Preview("Inspector") {
    EmitterInspectorView(model: ParticlesDemoModel(capacity: 1))
        .frame(width: 360, height: 900)
}

#Preview("Slider") {
    @Previewable @State var value: Float = 0.5
    ParameterSliderView("Value", value: $value, in: 0...1)
        .padding()
}
