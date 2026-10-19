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
                // Typed values may go beyond the slider's range.
                TextField("", value: $value, format: format)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
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

extension UInt32 {
    /// Categories the inspector lists one by one; the rest (9 to 32) are one switch.
    static let namedCategoryCount = 8
    static let upperCategories: UInt32 = ~0 << UInt32(namedCategoryCount)

    /// Whether all of categories 9 to 32 are set; setting it sets or clears them together.
    var hasUpperCategories: Bool {
        get { self & Self.upperCategories == Self.upperCategories }
        set { self = newValue ? self | Self.upperCategories : self & ~Self.upperCategories }
    }

    /// "All", "None", or the categories set, such as "1, 3" or "2 + 9–32" (or "+ some of 9–32").
    var categorySummary: String {
        if self == .max {
            return "All"
        }
        if self == 0 {
            return "None"
        }
        var parts = (0..<Self.namedCategoryCount).filter { self[bit: $0] }.map { String($0 + 1) }.joined(separator: ", ")
        let upper = self & Self.upperCategories
        if upper != 0 {
            let rest = upper == Self.upperCategories ? "9–32" : "some of 9–32"
            parts = parts.isEmpty ? rest : "\(parts) + \(rest)"
        }
        return parts
    }
}

/// A category mask as a menu: a summary of the categories set, with All, None, categories 1 to 8, and 9 to 32 as one
/// item. A collider or field applies to an emitter when they share a category. `detail` says what the mask matches.
struct CategoryMaskView: View {
    let title: LocalizedStringKey
    @Binding var mask: UInt32
    let detail: String?

    init(_ title: LocalizedStringKey, mask: Binding<UInt32>, detail: String? = nil) {
        self.title = title
        _mask = mask
        self.detail = detail
    }

    var body: some View {
        LabeledContent {
            Menu(mask.categorySummary) {
                Button("All") { mask = .max }
                Button("None") { mask = 0 }
                Divider()
                ForEach(0..<UInt32.namedCategoryCount, id: \.self) { bit in
                    Toggle("Category \(bit + 1)", isOn: $mask[bit: bit])
                }
                Toggle("Categories 9–32", isOn: $mask.hasUpperCategories)
            }
            .fixedSize()
        } label: {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
    }
}

/// "Matches 2 of 3 colliders": how many of `categories` share a bit with `mask`. `noun` is singular.
func categoryMatchSummary(_ mask: UInt32, categories: [UInt32], noun: String) -> String {
    "Matches \(categoryMatchCount(mask, categories: categories, noun: noun))"
}

/// "2 of 3 colliders", for combining several kinds in one summary.
func categoryMatchCount(_ mask: UInt32, categories: [UInt32], noun: String) -> String {
    let matched = categories.filter { $0 & mask != 0 }.count
    return "\(matched) of \(categories.count) \(categories.count == 1 ? noun : noun + "s")"
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
