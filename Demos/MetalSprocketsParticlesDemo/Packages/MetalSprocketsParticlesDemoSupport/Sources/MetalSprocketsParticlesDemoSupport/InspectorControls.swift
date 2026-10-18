import MetalSprocketsParticles
import simd
import SwiftUI

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

/// Three sliders for x, y, z.
struct VectorEditorView: View {
    let title: LocalizedStringKey
    @Binding var value: SIMD3<Float>
    let range: ClosedRange<Float>

    init(_ title: LocalizedStringKey, value: Binding<SIMD3<Float>>, in range: ClosedRange<Float>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        DisclosureGroup {
            ParameterSliderView("X", value: $value.x, in: range)
            ParameterSliderView("Y", value: $value.y, in: range)
            ParameterSliderView("Z", value: $value.z, in: range)
        } label: {
            LabeledContent(title) {
                Text("\(value.x, format: .number.precision(.fractionLength(2))), \(value.y, format: .number.precision(.fractionLength(2))), \(value.z, format: .number.precision(.fractionLength(2)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Edits color stops over a particle's life. Stops are identified by position: the library keyframes have no ids.
struct ColorCurveEditorView: View {
    let title: LocalizedStringKey
    @Binding var curve: ParticleCurve<SIMD4<Float>>

    var body: some View {
        DisclosureGroup(title) {
            ForEach(curve.keyframes.indices, id: \.self) { index in
                HStack {
                    ColorPicker("Stop \(index + 1)", selection: $curve.keyframes[index].color)
                    Slider(value: $curve.keyframes[index].time, in: 0...1)
                    Button("Remove Stop", systemImage: "minus.circle") {
                        curve.keyframes.remove(at: index)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(curve.keyframes.count == 1)
                }
            }
            Button("Add Stop", systemImage: "plus") {
                curve.keyframes.append(.init(1, curve.end))
            }
        }
    }
}

/// Edits scalar stops over a particle's life.
struct FloatCurveEditorView: View {
    let title: LocalizedStringKey
    @Binding var curve: ParticleCurve<Float>
    let range: ClosedRange<Float>

    var body: some View {
        DisclosureGroup(title) {
            ForEach(curve.keyframes.indices, id: \.self) { index in
                HStack {
                    VStack {
                        ParameterSliderView("Time", value: $curve.keyframes[index].time, in: 0...1)
                        ParameterSliderView("Value", value: $curve.keyframes[index].value, in: range, format: .number.precision(.fractionLength(3)))
                    }
                    Button("Remove Stop", systemImage: "minus.circle") {
                        curve.keyframes.remove(at: index)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(curve.keyframes.count == 1)
                }
            }
            Button("Add Stop", systemImage: "plus") {
                curve.keyframes.append(.init(1, curve.end))
            }
        }
    }
}

/// Picks any library kind: shape, collider, blend mode, trigger condition, and so on.
struct KindPicker<Kind: ParticleKind>: View {
    let title: String
    @Binding var selection: Kind

    init(_ title: String, selection: Binding<Kind>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Kind.allCases) { kind in
                Text(kind.name).tag(kind)
            }
        }
    }
}

#Preview("Slider") {
    @Previewable @State var value: Float = 0.5
    ParameterSliderView("Value", value: $value, in: 0...1)
        .padding()
}

#Preview("Curves") {
    @Previewable @State var color = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.5, 0, 1], to: [0.2, 0, 0, 0])
    @Previewable @State var size = ParticleCurve<Float>.linear(from: 0.05, to: 0.01)
    Form {
        ColorCurveEditorView(title: "Color", curve: $color)
        FloatCurveEditorView(title: "Size", curve: $size, range: 0...0.3)
    }
    .formStyle(.grouped)
}
