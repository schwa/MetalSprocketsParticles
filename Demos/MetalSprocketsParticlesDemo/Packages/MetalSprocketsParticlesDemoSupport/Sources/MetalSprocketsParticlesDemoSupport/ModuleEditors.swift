import MetalSprocketsParticles
import SwiftUI

// One editor per module type (#225). A new module gets an editor by conforming here; StageModuleEditor finds it.

/// A module the inspector can edit.
protocol EditableModule: ParticleModule {
    associatedtype Editor: View
    @MainActor @ViewBuilder static func editor(_ module: Binding<Self>) -> Editor
}

/// The editor for whichever module `module` holds.
struct StageModuleEditor<Stage: StageModule>: View {
    @Binding var module: Stage

    var body: some View {
        if let editable = module.module as? any EditableModule {
            editor(for: editable)
        }
    }

    /// Opens the existential so the module's own editor gets a typed binding. Type-erased once, here, because the
    /// editor type depends on which module the slot holds at run time.
    private func editor<Module: EditableModule>(for value: Module) -> AnyView {
        let binding = Binding<Module>(
            get: { module.module as? Module ?? value },
            set: { newValue in
                if let wrapped = Stage(wrapping: newValue) {
                    module = wrapped
                }
            }
        )
        return AnyView(Module.editor(binding))
    }
}

/// For modules whose function is edited in the User Functions section.
struct FunctionModuleSummary: View {
    let name: String

    var body: some View {
        LabeledContent("Function", value: name)
        Text("Edit in User Functions below.").font(.caption)
    }
}

// MARK: - Spawn

extension ShapeModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ShapeModuleEditor(module: module)
    }
}

extension RateModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        RateModuleEditor(module: module)
    }
}

extension LifetimeModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Lifetime", value: module.average, in: 0.1...30)
            .help("Seconds each particle lives, on average. Type a value for longer lives.")
        ParameterSliderView("Lifetime Variation", value: module.variation, in: 0...15)
            .help("Each particle lives this many seconds more or less than Lifetime, at random.")
    }
}

extension VelocityModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        VectorEditorView("Velocity", value: module.velocity, in: -20...20)
        ParameterSliderView("Spread", value: module.spread, in: 0...10)
        ParameterSliderView("Speed Variation", value: module.speedVariation, in: 0...10)
        ParameterSliderView("Inherit Velocity", value: module.inherit, in: 0...1)
    }
}

extension RotationModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Angle", value: module.angle, in: -.pi ... .pi)
        ParameterSliderView("Angle Variation", value: module.angleVariation, in: 0 ... .pi)
        ParameterSliderView("Spin", value: module.angularSpeed, in: -20...20)
        ParameterSliderView("Spin Variation", value: module.angularSpeedVariation, in: 0...20)
    }
}

extension VariationModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Size", value: module.size, in: 0...1)
        ParameterSliderView("Hue", value: module.color.x, in: 0...0.5)
        ParameterSliderView("Saturation", value: module.color.y, in: 0...1)
        ParameterSliderView("Brightness", value: module.color.z, in: 0...1)
        ParameterSliderView("Alpha", value: module.color.w, in: 0...1)
    }
}

extension ColorImageModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ColorImageModuleEditor(image: module.image)
    }
}

extension SpawnFunctionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FunctionModuleSummary(name: module.wrappedValue.function.name)
    }
}

extension StitchedSpawnModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        StitchedModuleEditor(module: module.module)
    }
}

// MARK: - Update

extension GravityModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        VectorEditorView("Gravity", value: module.acceleration, in: -20...20)
    }
}

extension DragModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Drag", value: module.amount, in: 0...5)
    }
}

extension FlockingModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FlockingModuleEditor(flocking: module.flocking)
    }
}

extension CollisionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Bounce", value: module.restitution, in: 0...1.5)
        ParameterSliderView("Bounce Variation", value: module.restitutionVariation, in: 0...1)
        ParameterSliderView("Friction", value: module.friction, in: 0...1)
        ParameterSliderView("Friction Variation", value: module.frictionVariation, in: 0...1)
        Toggle("Die on Collision", isOn: module.diesOnCollision)
        ParameterSliderView("Radius", value: module.radius, in: 0...0.5, format: .number.precision(.fractionLength(3)))
            .help("Particles collide as spheres of this radius instead of points, so large sprites and mesh particles rest on colliders instead of sinking in.")
        Toggle("Collide with Scene Depth", isOn: module.collidesWithSceneDepth)
            .help("Bounce off whatever was drawn into the scene depth last frame (here, solid colliders). Only works on screen.")
    }
}

extension PlaneConstraintModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        Text("Keeps particles on the emitter's XY plane, for 2D effects or flat sheets.").font(.caption)
    }
}

extension EventsModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        Toggle("Report Collisions", isOn: module.reportsCollisions)
            .help("Report each collider hit to the app (ParticleSystemRuntime.recentEvents), for sounds, decals, or event bursts.")
        Toggle("Report Deaths", isOn: module.reportsDeaths)
            .help("Report each particle death to the app (ParticleSystemRuntime.recentEvents).")
    }
}

extension SubEmittersModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        LabeledContent("Sub-Emitters", value: "\(module.wrappedValue.emitters.count)")
        Text("Select them in the outline to edit.").font(.caption)
    }
}

extension TriggersModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        LabeledContent("Triggers", value: "\(module.wrappedValue.triggers.count)")
        Text("Select them in the outline to edit.").font(.caption)
    }
}

extension UpdateFunctionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FunctionModuleSummary(name: module.wrappedValue.function.name)
    }
}

extension CollisionFunctionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FunctionModuleSummary(name: module.wrappedValue.function.name)
    }
}

extension DeathFunctionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FunctionModuleSummary(name: module.wrappedValue.function.name)
    }
}

extension StitchedUpdateModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        StitchedModuleEditor(module: module.module)
    }
}

// MARK: - Render

extension SpriteModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        KindPicker("Blend", selection: module.blendMode)
        KindPicker("Sort", selection: module.sortMode)
        KindPicker("Orientation", selection: module.orientation.kind)
        if module.wrappedValue.orientation.kind == .velocityAligned {
            ParameterSliderView("Stretch", value: module.velocityStretch, in: 0...2)
        }
        ParameterSliderView("Softness", value: module.softness, in: 0...1)
            .help("Soft particles: fade out over this distance in front of solid colliders instead of clipping hard. 0 turns it off.")
        ParameterSliderView("Minimum Screen Size", value: module.minimumScreenSize, in: 0...0.02, format: .number.precision(.fractionLength(4)))
            .help("Far particles never draw smaller than this: half their size as a fraction of the view height. 0 lets them shrink.")
    }
}

extension ColorOverLifeModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ColorCurveEditorView(title: "Color", curve: module.color)
        FloatCurveEditorView(title: "Opacity", curve: module.opacity, range: 0...1)
        Toggle("Alternate Colors", isOn: module.hasAlternateColors)
            .help("Each particle blends between Color and this second gradient by its own random amount.")
        if module.wrappedValue.hasAlternateColors {
            ColorCurveEditorView(title: "Alternate", curve: module.editableAlternate)
        }
    }
}

extension SizeOverLifeModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        FloatCurveEditorView(title: "Size", curve: module.curve, range: 0...0.5)
    }
}

extension ColorBySpeedModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ColorCurveEditorView(title: "Speed Gradient", curve: module.editableCurve)
        ParameterSliderView("Slow Speed", value: module.minimum, in: 0...20)
        ParameterSliderView("Fast Speed", value: module.maximum, in: 0...20)
    }
}

extension ColorByPositionModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ColorCurveEditorView(title: "Position Gradient", curve: module.editableCurve)
        VectorEditorView("Start", value: module.start, in: -5...5)
        VectorEditorView("End", value: module.end, in: -5...5)
        Toggle("Sample at Birth", isOn: module.atBirth)
            .help("Keep the color where each particle is born, instead of changing it as the particle moves.")
    }
}

extension ImageSequenceModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ImageSequenceEditorView(sequence: module.sequence)
    }
}

extension ShadingModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ShadingModuleEditor(model: module.model)
        if module.wrappedValue.model != .unlit {
            Toggle("Per Pixel", isOn: module.perPixel)
                .help("Shade every pixel instead of every vertex: smooth highlights across large faces, at the cost of a function call per pixel.")
        }
    }
}

extension MeshModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        LabeledContent("Mesh", value: module.wrappedValue.mesh.label)
        Text("Change it with Draw As in Appearance.").font(.caption)
    }
}

extension TrailModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Points", value: module.trail.editablePointCount, in: 2...64, format: .number.precision(.fractionLength(0)))
            .help("Positions kept per particle. Memory is 16 bytes per point per particle of every emitter.")
        ParameterSliderView("Point Interval", value: module.trail.pointInterval, in: 0...0.2, format: .number.precision(.fractionLength(3)))
            .help("Seconds between recorded points, so trails cover the same time at any frame rate. 0 records one every step.")
        Toggle("Tapers", isOn: module.trail.tapers)
        Toggle("Fades", isOn: module.trail.fades)
    }
}

extension RibbonModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        Toggle("Tapers", isOn: module.ribbon.tapers)
    }
}

extension LightModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Lights", value: module.light.editableCount, in: 1...32, format: .number.precision(.fractionLength(0)))
            .help("How many particles become lights, picked evenly across the emitter.")
        ColorPicker("Color", selection: module.light.color.color, supportsOpacity: false)
        ParameterSliderView("Intensity", value: module.light.intensity, in: 0...10)
        ParameterSliderView("Range", value: module.light.range, in: 0...10)
        Toggle("Brightest Particles", isOn: module.light.picksBrightest)
            .help("Each light takes the brightest particle in its share, so lights sit on the hottest sparks. Off is cheaper.")
    }
}

extension LevelOfDetailModule: EditableModule {
    static func editor(_ module: Binding<Self>) -> some View {
        ParameterSliderView("Full Rate Within", value: module.near, in: 0...50)
            .help("Distance from the camera within which the emitter emits at its full rate.")
        ParameterSliderView("Reduced Rate At", value: module.far, in: 0...100)
            .help("Distance at which emission falls to the far rate. LOD is off unless this is farther than Full Rate Within.")
        ParameterSliderView("Far Rate", value: module.farRateScale, in: 0...1)
        Toggle("Grow When Thinned", isOn: module.scalesSize)
        ParameterSliderView("Culling Radius", value: module.cullingRadius, in: 0...20)
            .help("A sphere around the emitter that holds its particles; when it is out of view the emitter is not drawn. 0 never culls.")
        if module.wrappedValue.cullingRadius > 0 {
            Toggle("Simulate When Culled", isOn: module.simulatesWhenCulled)
        }
    }
}
