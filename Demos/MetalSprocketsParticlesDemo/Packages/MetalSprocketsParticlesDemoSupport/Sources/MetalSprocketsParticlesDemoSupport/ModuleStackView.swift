import MetalSprocketsParticles
import SwiftUI

/// The emitter's modules (#196, #203): one section per module, in stack order, each editing its module directly. Turn
/// modules off, remove them, add new ones, and reorder stitched user modules.
struct ModuleStacksView: View {
    @Binding var modules: EmitterModules
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        ModuleStackView(title: "Spawn", stack: $modules.spawn) { module in
            StageModuleEditor(module: module)
        }
        ModuleStackView(title: "Update", stack: $modules.update) { module in
            StageModuleEditor(module: module)
        }
        ModuleStackView(title: "Render", stack: $modules.render) { module in
            StageModuleEditor(module: module)
        }
        Section("Categories") {
            CategoryMaskView(
                "Categories",
                mask: $modules.categoryMask,
                detail: "Matches \(categoryMatchCount(modules.categoryMask, categories: model.colliders.map(\.collider.categoryBitMask), noun: "collider")) and "
                    + categoryMatchCount(modules.categoryMask, categories: model.forceFields.map(\.field.categoryBitMask), noun: "field")
            )
            .help("Colliders and force fields apply when they share a category with the emitter. Give them different categories to feel one but not the other.")
        }
    }
}

/// A module stack's stage, for the outline and for selecting one module.
enum ModuleStage: String, CaseIterable, Identifiable {
    case spawn = "Spawn"
    case update = "Update"
    case render = "Render"

    var id: Self { self }

    /// Each module's title and whether it is on, in stack order.
    func labels(of modules: EmitterModules) -> [(title: String, isEnabled: Bool)] {
        switch self {
        case .spawn: modules.spawn.map { (ModuleStackView<SpawnModule, EmptyView>.label($0.module), $0.isEnabled) }
        case .update: modules.update.map { (ModuleStackView<UpdateModule, EmptyView>.label($0.module), $0.isEnabled) }
        case .render: modules.render.map { (ModuleStackView<RenderModule, EmptyView>.label($0.module), $0.isEnabled) }
        }
    }
}

/// One module's section, for a module selected in the outline.
struct SingleModuleView: View {
    @Binding var modules: EmitterModules
    let stage: ModuleStage
    let index: Int

    var body: some View {
        switch stage {
        case .spawn:
            ModuleStackView(title: stage.rawValue, stack: $modules.spawn, only: index) { StageModuleEditor(module: $0) }
        case .update:
            ModuleStackView(title: stage.rawValue, stack: $modules.update, only: index) { StageModuleEditor(module: $0) }
        case .render:
            ModuleStackView(title: stage.rawValue, stack: $modules.render, only: index) { StageModuleEditor(module: $0) }
        }
    }
}

struct ModuleStackView<Module: StageModule, Editor: View>: View {
    let title: String
    @Binding var stack: [ModuleSlot<Module>]
    /// Show only this slot, without the Add menu.
    var only: Int?
    @ViewBuilder var editor: (Binding<Module>) -> Editor

    var body: some View {
        ForEach(only.map { $0 < stack.count ? [$0] : [] } ?? Array(stack.indices), id: \.self) { index in
            Section {
                if stack[index].isEnabled {
                    editor($stack[index].module)
                }
            } header: {
                header(index)
            }
        }
        let present = Set(stack.map(\.module.kind))
        // Stitched user modules can be added any number of times; built-ins once.
        let missing = Module.addable.filter { $0.kind == "stitched" || !present.contains($0.kind) }
        if only == nil, !missing.isEmpty {
            Section {
                Menu("Add \(title) Module") {
                    ForEach(missing.indices, id: \.self) { index in
                        Button(Self.label(missing[index])) { stack.append(ModuleSlot(Self.uniquelyNamed(missing[index], in: stack))) }
                    }
                }
            }
        }
    }

    private func header(_ index: Int) -> some View {
        HStack {
            Text("\(title): \(Self.label(stack[index].module))")
            Spacer()
            // Only user modules have an order; built-ins run at fixed points (Documentation/Modules.md).
            if stack[index].module.kind == "stitched" {
                let previous = stack[..<index].lastIndex { $0.module.kind == "stitched" }
                let next = stack[(index + 1)...].firstIndex { $0.module.kind == "stitched" }
                Button("Move Up", systemImage: "chevron.up") { previous.map { stack.swapAt(index, $0) } }
                    .disabled(previous == nil)
                Button("Move Down", systemImage: "chevron.down") { next.map { stack.swapAt(index, $0) } }
                    .disabled(next == nil)
            }
            if !stack[index].module.isRequired {
                Toggle("Enabled", isOn: $stack[index].isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button("Remove", systemImage: "minus.circle", role: .destructive) { stack.remove(at: index) }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    /// `module` with a function name no stitched module in `stack` has (swirl, swirl2, ...), so editing one copy's
    /// source cannot clash with another's (#217).
    static func uniquelyNamed(_ module: Module, in stack: [ModuleSlot<Module>]) -> Module {
        let names = Set(stack.compactMap { stitched($0.module)?.name })
        guard var stitched = stitched(module), names.contains(stitched.name) else {
            return module
        }
        let base = stitched.name
        var number = 2
        while names.contains("\(base)\(number)") {
            number += 1
        }
        stitched.source = stitched.source.replacingOccurrences(of: "*\(base)(", with: "*\(base)\(number)(")
        stitched.name = "\(base)\(number)"
        switch module.module {
        case is StitchedUpdateModule: return Module(wrapping: StitchedUpdateModule(module: stitched)) ?? module
        case is StitchedSpawnModule: return Module(wrapping: StitchedSpawnModule(module: stitched)) ?? module
        default: return module
        }
    }

    private static func stitched(_ module: Module) -> StitchedModule? {
        switch module.module {
        case let stitched as StitchedUpdateModule: stitched.module
        case let stitched as StitchedSpawnModule: stitched.module
        default: nil
        }
    }

    /// "colorOverLife" as "Color Over Life"; stitched modules by their function name.
    nonisolated static func label(_ module: Module) -> String {
        switch module.module {
        case let stitched as StitchedUpdateModule: return "Stitched \(stitched.module.name)"
        case let stitched as StitchedSpawnModule: return "Stitched \(stitched.module.name)"
        default: break
        }
        var words = ""
        for character in module.kind {
            if character.isUppercase {
                words += " "
            }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// The shading model (#172): unlit, lit, foil with its sliders, or a custom function with a code editor.
struct ShadingModuleEditor: View {
    @Binding var model: ShadingModel

    var body: some View {
        Picker("Model", selection: $model.kind) {
            ForEach(ShadingModel.Kind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        .help("Unlit draws colors as they are; Lit adds the scene's lights; Foil shades like metallic foil (use with tumbling sprites or meshes); Custom runs your own Metal function per vertex.")
        switch model {
        case .unlit, .lit:
            EmptyView()
        case let .foil(foil):
            let settings = Binding(get: { foil }, set: { model = .foil(settings: $0) })
            ParameterSliderView("Glint", value: settings.glint, in: 0...10)
            ParameterSliderView("Shininess", value: settings.shininess, in: 1...200, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Iridescence", value: settings.iridescence, in: 0...1)
        case let .custom(function):
            ShadingFunctionEditor(function: Binding(get: { function }, set: { model = .custom(function: $0) }))
        }
    }
}

/// A custom shading function. Source and name are drafts until Compile & Apply, which compiles them first.
struct ShadingFunctionEditor: View {
    @Binding var function: ParticleFunction
    @State private var draftSource = ""
    @State private var draftName = ""
    @State private var compileError: String?

    var body: some View {
        TextField("Function Name", text: $draftName)
            .monospaced()
        TextEditor(text: $draftSource)
            .font(.system(.callout, design: .monospaced))
            .frame(minHeight: 140)
            .scrollContentBackground(.hidden)
            .background(.quaternary, in: .rect(cornerRadius: 6))
        if let compileError {
            Text(compileError)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Compile & Apply") { apply() }
                .disabled(isUnchanged)
            Button("Revert") { loadDrafts() }
                .disabled(isUnchanged)
        }
        ParametersEditorView(parameters: $function.parameters)
        Text("Signature: [[visible]] float4 name(ShadingInput input, ShadingScene scene, constant ShadingLight *lights, const device ShadingLight *particleLights, constant float4 *parameters). Return the vertex color.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onChange(of: function, initial: true) { _, _ in
                if isUnchanged || draftSource.isEmpty {
                    loadDrafts()
                }
            }
    }

    private var isUnchanged: Bool {
        draftSource == function.source && draftName == function.name
    }

    private func loadDrafts() {
        draftSource = function.source
        draftName = function.name
        compileError = nil
    }

    private func apply() {
        let candidate = ParticleFunction(source: draftSource, name: draftName, parameters: function.parameters)
        do {
            try candidate.validateShading(device: ParticleSystemRuntime.defaultDevice())
            compileError = nil
            function = candidate
        } catch {
            compileError = error.localizedDescription
        }
    }
}

extension ShadingModel {
    enum Kind: String, CaseIterable, Identifiable {
        case unlit = "Unlit"
        case lit = "Lit"
        case foil = "Foil"
        case custom = "Custom"

        var id: Self { self }
    }

    /// Switching kind starts foil from its defaults and a custom function from the template.
    var kind: Kind {
        get {
            switch self {
            case .unlit: .unlit
            case .lit: .lit
            case .foil: .foil
            case .custom: .custom
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            switch newValue {
            case .unlit: self = .unlit
            case .lit: self = .lit
            case .foil: self = .foil(settings: ParticleFoil())
            case .custom: self = .custom(function: ShadingModule.template)
            }
        }
    }
}

struct ShapeModuleEditor: View {
    @Binding var module: ShapeModule

    var body: some View {
        KindPicker("Shape", selection: $module.shape.kind)
        switch module.shape.kind {
        case .sphere, .disc:
            ParameterSliderView("Radius", value: $module.shape.radius, in: 0...3)
        case .cylinder, .cone:
            ParameterSliderView("Radius", value: $module.shape.radius, in: 0...3)
            ParameterSliderView("Height", value: $module.shape.secondary, in: 0...3)
        case .torus:
            ParameterSliderView("Radius", value: $module.shape.radius, in: 0...3)
            ParameterSliderView("Tube Radius", value: $module.shape.secondary, in: 0...1)
        case .box, .plane:
            VectorEditorView("Size", value: $module.shape.size, in: 0...5)
        default:
            EmptyView()
        }
        DisclosureGroup("Placement") {
            if module.shape.kind != .point {
                KindPicker("Birth Location", selection: $module.birthLocation)
                ParameterSliderView("Sweep", value: $module.sweepAngle, in: 0...(2 * .pi))
            }
            KindPicker("Birth Direction", selection: $module.birthDirection)
            VectorEditorView("Position", value: $module.position, in: -5...5)
        }
    }
}

struct RateModuleEditor: View {
    @Binding var module: RateModule

    var body: some View {
        ParameterSliderView("Birth Rate", value: $module.birthRate, in: 0...100_000, format: .number.precision(.fractionLength(0)))
        DisclosureGroup("Timing") {
            ParameterSliderView("Rate Variation", value: $module.variation, in: 0...50_000, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Warmup", value: $module.warmupDuration, in: 0...5)
            Toggle("Limited Duration", isOn: $module.hasLimitedEmission)
            if module.hasLimitedEmission {
                ParameterSliderView("Duration", value: $module.limitedEmissionDuration, in: 0.1...10)
                ParameterSliderView("Idle", value: $module.idleDuration, in: 0...10)
                Toggle("Loops", isOn: $module.loops)
            }
            // Birth-rate multiplier over seconds since the emitter started; ending at 0 makes a finite effect.
            FloatCurveEditorView(title: "Emission Over Time", curve: $module.overTime, range: 0...1, timeRange: 0...30)
        }
    }
}

struct ColorImageModuleEditor: View {
    @Binding var image: ParticleColorImage
    @State private var isChoosing = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        Button("Replace Image…") { isChoosing = true }
            .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    image = try ParticleColorImage.choosing(data: Data(contentsOf: url), replacing: image)
                } catch {
                    errorMessage = error.localizedDescription
                    isShowingError = true
                }
            }
            .alert("Color Image", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        VectorEditorView("Origin", value: $image.origin, in: -5...5)
        VectorEditorView("Width", value: $image.width, in: -5...5)
        VectorEditorView("Height", value: $image.height, in: -5...5)
    }
}

/// Edits a stitched user module. Source and name are drafts until Compile & Apply, which stitches the module on its
/// own first, so typing does not recompile the effect on every key. Parameters apply at once.
struct StitchedModuleEditor: View {
    @Binding var module: StitchedModule
    @State private var draftSource = ""
    @State private var draftName = ""
    @State private var compileError: String?

    var body: some View {
        TextField("Function Name", text: $draftName)
            .monospaced()
        TextEditor(text: $draftSource)
            .font(.system(.callout, design: .monospaced))
            .frame(minHeight: 140)
            .scrollContentBackground(.hidden)
            .background(.quaternary, in: .rect(cornerRadius: 6))
        if let compileError {
            Text(compileError)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Compile & Apply") { apply() }
                .disabled(isUnchanged)
            Button("Revert") { loadDrafts() }
                .disabled(isUnchanged)
        }
        ParametersEditorView(parameters: $module.parameters)
        Stepper("Reads \(module.parameterCount) Parameters", value: $module.parameterCount, in: 0...ParticleFunction.minimumParameterCount)
            .help("Entries this module reads and skips. The code must return parameters + this count.")
        Text("Signature: [[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters). Return parameters + the count it reads.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onChange(of: module, initial: true) { _, _ in
                if isUnchanged || draftSource.isEmpty {
                    loadDrafts()
                }
            }
    }

    private var isUnchanged: Bool {
        draftSource == module.source && draftName == module.name
    }

    private func loadDrafts() {
        draftSource = module.source
        draftName = module.name
        compileError = nil
    }

    private func apply() {
        var candidate = module
        candidate.source = draftSource
        candidate.name = draftName
        do {
            try candidate.validate(device: ParticleSystemRuntime.defaultDevice())
            compileError = nil
            module = candidate
        } catch {
            compileError = error.localizedDescription
        }
    }
}

struct FlockingModuleEditor: View {
    @Binding var flocking: ParticleFlocking

    var body: some View {
        ParameterSliderView("Neighbor Radius", value: $flocking.radius, in: 0.01...2)
            .help("How far a particle sees its neighbors. Smaller is faster.")
        ParameterSliderView("Separation Radius", value: $flocking.separationRadius, in: 0...1)
            .help("Closer than this, neighbors push apart.")
        ParameterSliderView("Separation", value: $flocking.separation, in: 0...0.2, format: .number.precision(.fractionLength(3)))
        ParameterSliderView("Alignment", value: $flocking.alignment, in: 0...5)
        ParameterSliderView("Cohesion", value: $flocking.cohesion, in: 0...5)
        ParameterSliderView("Minimum Speed", value: $flocking.minimumSpeed, in: 0...10)
        ParameterSliderView("Maximum Speed", value: $flocking.maximumSpeed, in: 0...10)
        ParameterSliderView("Neighbors", value: $flocking.neighborLimit, in: 1...64, format: .number.precision(.fractionLength(0)))
            .help("Neighbors counted per particle, to bound the cost in dense crowds.")
    }
}

