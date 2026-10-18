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

extension ParticleCurve {
    /// The keyframe at `index`, for row bindings. Rows are identified by position, so after a removal SwiftUI can read or
    /// write a row binding past the end once more: those reads return the last keyframe and those writes are dropped.
    subscript(stop index: Int) -> Keyframe {
        get { keyframes.indices.contains(index) ? keyframes[index] : keyframes.last ?? Keyframe(0, end) }
        set {
            if keyframes.indices.contains(index) {
                keyframes[index] = newValue
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
                    ColorPicker("Stop \(index + 1)", selection: $curve[stop: index].color)
                    Slider(value: $curve[stop: index].time, in: 0...1)
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
    /// 0...1 for over-life curves; seconds for curves over emitter time.
    var timeRange: ClosedRange<Float> = 0...1

    var body: some View {
        DisclosureGroup(title) {
            ForEach(curve.keyframes.indices, id: \.self) { index in
                HStack {
                    VStack {
                        ParameterSliderView("Time", value: $curve[stop: index].time, in: timeRange)
                        ParameterSliderView("Value", value: $curve[stop: index].value, in: range, format: .number.precision(.fractionLength(3)))
                    }
                    Button("Remove Stop", systemImage: "minus.circle") {
                        curve.keyframes.remove(at: index)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(curve.keyframes.count == 1)
                }
            }
            Button("Add Stop", systemImage: "plus") {
                // A tenth of the range after the last stop, so new stops do not pile up on existing ones.
                let last = curve.keyframes.map(\.time).max() ?? timeRange.lowerBound
                let time = min(timeRange.upperBound, last + (timeRange.upperBound - timeRange.lowerBound) / 10)
                curve.keyframes.append(.init(time, curve.end))
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

extension UInt32 {
    /// Bit `index`, for toggle bindings.
    subscript(bit index: Int) -> Bool {
        get { self & (1 << index) != 0 }
        set { self = newValue ? self | (1 << index) : self & ~(1 << index) }
    }
}

/// Category bits 1 to 8 as toggle buttons. A collider or field applies to an emitter when they share a bit; bits above 8
/// are left as they are.
struct CategoryMaskView: View {
    let title: LocalizedStringKey
    @Binding var mask: UInt32

    init(_ title: LocalizedStringKey, mask: Binding<UInt32>) {
        self.title = title
        _mask = mask
    }

    var body: some View {
        LabeledContent(title) {
            HStack {
                ForEach(0..<8, id: \.self) { bit in
                    Toggle("\(bit + 1)", isOn: $mask[bit: bit])
                        .toggleStyle(.button)
                }
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

#Preview("Category Mask") {
    @Previewable @State var mask: UInt32 = 0b101
    Form {
        CategoryMaskView("Collides With", mask: $mask)
    }
    .formStyle(.grouped)
}
