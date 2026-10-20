import MetalSprocketsParticles
import SwiftUI

/// The emitter's modules (#196, #203): one section per module, in stack order, each editing its module directly. Turn
/// modules off, remove them, add new ones, and reorder stitched user modules.
struct ModuleStacksView: View {
    @Binding var modules: EmitterModules
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        ModuleStackView(title: "Spawn", stack: $modules.spawn) { module in
            SpawnModuleEditor(module: module)
        }
        ModuleStackView(title: "Update", stack: $modules.update) { module in
            UpdateModuleEditor(module: module)
        }
        ModuleStackView(title: "Render", stack: $modules.render) { module in
            RenderModuleEditor(module: module)
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
            ModuleStackView(title: stage.rawValue, stack: $modules.spawn, only: index) { SpawnModuleEditor(module: $0) }
        case .update:
            ModuleStackView(title: stage.rawValue, stack: $modules.update, only: index) { UpdateModuleEditor(module: $0) }
        case .render:
            ModuleStackView(title: stage.rawValue, stack: $modules.render, only: index) { RenderModuleEditor(module: $0) }
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
    static func label(_ module: Module) -> String {
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

/// A binding to the module inside an enum case.
private func payload<Stage, Payload>(_ module: Binding<Stage>, _ value: Payload, _ wrap: @escaping (Payload) -> Stage) -> Binding<Payload> {
    Binding(get: { value }, set: { module.wrappedValue = wrap($0) })
}

// MARK: - Spawn

struct SpawnModuleEditor: View {
    @Binding var module: SpawnModule

    var body: some View {
        switch module {
        case let .shape(value):
            ShapeModuleEditor(module: payload($module, value, SpawnModule.shape))
        case let .rate(value):
            RateModuleEditor(module: payload($module, value, SpawnModule.rate))
        case let .lifetime(value):
            let lifetime = payload($module, value, SpawnModule.lifetime)
            ParameterSliderView("Lifetime", value: lifetime.average, in: 0.1...30)
                .help("Seconds each particle lives, on average. Type a value for longer lives.")
            ParameterSliderView("Lifetime Variation", value: lifetime.variation, in: 0...15)
                .help("Each particle lives this many seconds more or less than Lifetime, at random.")
        case let .velocity(value):
            let velocity = payload($module, value, SpawnModule.velocity)
            VectorEditorView("Velocity", value: velocity.velocity, in: -20...20)
            ParameterSliderView("Spread", value: velocity.spread, in: 0...10)
            ParameterSliderView("Speed Variation", value: velocity.speedVariation, in: 0...10)
            ParameterSliderView("Inherit Velocity", value: velocity.inherit, in: 0...1)
        case let .rotation(value):
            let rotation = payload($module, value, SpawnModule.rotation)
            ParameterSliderView("Angle", value: rotation.angle, in: -.pi ... .pi)
            ParameterSliderView("Angle Variation", value: rotation.angleVariation, in: 0 ... .pi)
            ParameterSliderView("Spin", value: rotation.angularSpeed, in: -20...20)
            ParameterSliderView("Spin Variation", value: rotation.angularSpeedVariation, in: 0...20)
        case let .variation(value):
            let variation = payload($module, value, SpawnModule.variation)
            ParameterSliderView("Size", value: variation.size, in: 0...1)
            ParameterSliderView("Hue", value: variation.color.x, in: 0...0.5)
            ParameterSliderView("Saturation", value: variation.color.y, in: 0...1)
            ParameterSliderView("Brightness", value: variation.color.z, in: 0...1)
            ParameterSliderView("Alpha", value: variation.color.w, in: 0...1)
        case let .colorImage(value):
            let image = payload($module, value, SpawnModule.colorImage)
            ColorImageModuleEditor(image: image.image)
        case let .function(value):
            LabeledContent("Function", value: value.function.name)
            Text("Edit in User Functions below.").font(.caption)
        case let .stitched(value):
            StitchedModuleEditor(module: payload($module, value, SpawnModule.stitched).module)
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

// MARK: - Update

struct UpdateModuleEditor: View {
    @Binding var module: UpdateModule

    var body: some View {
        switch module {
        case let .gravity(value):
            VectorEditorView("Gravity", value: payload($module, value, UpdateModule.gravity).acceleration, in: -20...20)
        case let .drag(value):
            ParameterSliderView("Drag", value: payload($module, value, UpdateModule.drag).amount, in: 0...5)
        case let .flocking(value):
            FlockingModuleEditor(flocking: payload($module, value, UpdateModule.flocking).flocking)
        case let .collision(value):
            let collision = payload($module, value, UpdateModule.collision)
            ParameterSliderView("Bounce", value: collision.restitution, in: 0...1.5)
            ParameterSliderView("Bounce Variation", value: collision.restitutionVariation, in: 0...1)
            ParameterSliderView("Friction", value: collision.friction, in: 0...1)
            ParameterSliderView("Friction Variation", value: collision.frictionVariation, in: 0...1)
            Toggle("Die on Collision", isOn: collision.diesOnCollision)
            ParameterSliderView("Radius", value: collision.radius, in: 0...0.5, format: .number.precision(.fractionLength(3)))
                .help("Particles collide as spheres of this radius instead of points, so large sprites and mesh particles rest on colliders instead of sinking in.")
            Toggle("Collide with Scene Depth", isOn: collision.collidesWithSceneDepth)
                .help("Bounce off whatever was drawn into the scene depth last frame (here, solid colliders). Only works on screen.")
        case .planeConstraint:
            Text("Keeps particles on the emitter's XY plane, for 2D effects or flat sheets.").font(.caption)
        case let .events(value):
            let events = payload($module, value, UpdateModule.events)
            Toggle("Report Collisions", isOn: events.reportsCollisions)
                .help("Report each collider hit to the app (ParticleSystemRuntime.recentEvents), for sounds, decals, or event bursts.")
            Toggle("Report Deaths", isOn: events.reportsDeaths)
                .help("Report each particle death to the app (ParticleSystemRuntime.recentEvents).")
        case let .subEmitters(value):
            LabeledContent("Sub-Emitters", value: "\(value.emitters.count)")
            Text("Select them in the outline to edit.").font(.caption)
        case let .triggers(value):
            LabeledContent("Triggers", value: "\(value.triggers.count)")
            Text("Select them in the outline to edit.").font(.caption)
        case let .function(value):
            LabeledContent("Function", value: value.function.name)
            Text("Edit in User Functions below.").font(.caption)
        case let .collisionFunction(value):
            LabeledContent("Function", value: value.function.name)
            Text("Edit in User Functions below.").font(.caption)
        case let .deathFunction(value):
            LabeledContent("Function", value: value.function.name)
            Text("Edit in User Functions below.").font(.caption)
        case let .stitched(value):
            StitchedModuleEditor(module: payload($module, value, UpdateModule.stitched).module)
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

// MARK: - Render

struct RenderModuleEditor: View {
    @Binding var module: RenderModule

    var body: some View {
        switch module {
        case let .sprite(value):
            let sprite = payload($module, value, RenderModule.sprite)
            KindPicker("Blend", selection: sprite.blendMode)
            KindPicker("Sort", selection: sprite.sortMode)
            KindPicker("Orientation", selection: sprite.orientation.kind)
            if value.orientation.kind == .velocityAligned {
                ParameterSliderView("Stretch", value: sprite.velocityStretch, in: 0...2)
            }
            Toggle("Lit", isOn: sprite.isLit)
            ParameterSliderView("Softness", value: sprite.softness, in: 0...1)
                .help("Soft particles: fade out over this distance in front of solid colliders instead of clipping hard. 0 turns it off.")
            ParameterSliderView("Minimum Screen Size", value: sprite.minimumScreenSize, in: 0...0.02, format: .number.precision(.fractionLength(4)))
                .help("Far particles never draw smaller than this: half their size as a fraction of the view height. 0 lets them shrink.")
        case let .colorOverLife(value):
            let color = payload($module, value, RenderModule.colorOverLife)
            ColorCurveEditorView(title: "Color", curve: color.color)
            FloatCurveEditorView(title: "Opacity", curve: color.opacity, range: 0...1)
            Toggle("Alternate Colors", isOn: color.hasAlternateColors)
                .help("Each particle blends between Color and this second gradient by its own random amount.")
            if value.hasAlternateColors {
                ColorCurveEditorView(title: "Alternate", curve: color.editableAlternate)
            }
        case let .sizeOverLife(value):
            FloatCurveEditorView(title: "Size", curve: payload($module, value, RenderModule.sizeOverLife).curve, range: 0...0.5)
        case let .colorBySpeed(value):
            let speed = payload($module, value, RenderModule.colorBySpeed)
            ColorCurveEditorView(title: "Speed Gradient", curve: speed.editableCurve)
            ParameterSliderView("Slow Speed", value: speed.minimum, in: 0...20)
            ParameterSliderView("Fast Speed", value: speed.maximum, in: 0...20)
        case let .colorByPosition(value):
            let position = payload($module, value, RenderModule.colorByPosition)
            ColorCurveEditorView(title: "Position Gradient", curve: position.editableCurve)
            VectorEditorView("Start", value: position.start, in: -5...5)
            VectorEditorView("End", value: position.end, in: -5...5)
            Toggle("Sample at Birth", isOn: position.atBirth)
                .help("Keep the color where each particle is born, instead of changing it as the particle moves.")
        case let .imageSequence(value):
            ImageSequenceEditorView(sequence: payload($module, value, RenderModule.imageSequence).sequence)
        case let .foil(value):
            let foil = payload($module, value, RenderModule.foil)
            ParameterSliderView("Glint", value: foil.foil.glint, in: 0...10)
            ParameterSliderView("Shininess", value: foil.foil.shininess, in: 1...200, format: .number.precision(.fractionLength(0)))
            ParameterSliderView("Iridescence", value: foil.foil.iridescence, in: 0...1)
        case let .mesh(value):
            LabeledContent("Mesh", value: value.mesh.label)
            Text("Change it with Draw As in Appearance.").font(.caption)
        case let .trail(value):
            let trail = payload($module, value, RenderModule.trail)
            ParameterSliderView("Points", value: trail.trail.editablePointCount, in: 2...64, format: .number.precision(.fractionLength(0)))
                .help("Positions kept per particle. Memory is 16 bytes per point per particle of every emitter.")
            ParameterSliderView("Point Interval", value: trail.trail.pointInterval, in: 0...0.2, format: .number.precision(.fractionLength(3)))
                .help("Seconds between recorded points, so trails cover the same time at any frame rate. 0 records one every step.")
            Toggle("Tapers", isOn: trail.trail.tapers)
            Toggle("Fades", isOn: trail.trail.fades)
        case let .ribbon(value):
            Toggle("Tapers", isOn: payload($module, value, RenderModule.ribbon).ribbon.tapers)
        case let .light(value):
            let light = payload($module, value, RenderModule.light)
            ParameterSliderView("Lights", value: light.light.editableCount, in: 1...32, format: .number.precision(.fractionLength(0)))
                .help("How many particles become lights, picked evenly across the emitter.")
            ColorPicker("Color", selection: light.light.color.color, supportsOpacity: false)
            ParameterSliderView("Intensity", value: light.light.intensity, in: 0...10)
            ParameterSliderView("Range", value: light.light.range, in: 0...10)
            Toggle("Brightest Particles", isOn: light.light.picksBrightest)
                .help("Each light takes the brightest particle in its share, so lights sit on the hottest sparks. Off is cheaper.")
        case let .levelOfDetail(value):
            let lod = payload($module, value, RenderModule.levelOfDetail)
            ParameterSliderView("Full Rate Within", value: lod.near, in: 0...50)
                .help("Distance from the camera within which the emitter emits at its full rate.")
            ParameterSliderView("Reduced Rate At", value: lod.far, in: 0...100)
                .help("Distance at which emission falls to the far rate. LOD is off unless this is farther than Full Rate Within.")
            ParameterSliderView("Far Rate", value: lod.farRateScale, in: 0...1)
            Toggle("Grow When Thinned", isOn: lod.scalesSize)
            ParameterSliderView("Culling Radius", value: lod.cullingRadius, in: 0...20)
                .help("A sphere around the emitter that holds its particles; when it is out of view the emitter is not drawn. 0 never culls.")
            if value.cullingRadius > 0 {
                Toggle("Simulate When Culled", isOn: lod.simulatesWhenCulled)
            }
        }
    }
}
