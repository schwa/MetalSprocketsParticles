import MetalSprocketsParticles
import SwiftUI

/// A path an object moves along: the same choices emitter motion has.
struct PathMotionEditorView: View {
    @Binding var motion: EmitterMotion

    var body: some View {
        KindPicker("Path", selection: $motion.kind)
        if motion.kind != .still {
            ParameterSliderView("Path Radius", value: $motion.radius, in: 0...4)
            ParameterSliderView("Path Speed", value: $motion.speed, in: 0...5)
        }
        VectorEditorView("Offset", value: $motion.offset, in: -5...5)
        ParameterSliderView("Yaw", value: $motion.yaw, in: -.pi ... .pi)
        ParameterSliderView("Pitch", value: $motion.pitch, in: -.pi ... .pi)
    }
}

/// When one emitter's particles hit a collider or die, burst particles from another (EventBurst).
struct EventBurstsSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            ForEach($model.eventBurstItems) { $item in
                DisclosureGroup(summary(item)) {
                    Picker("When", selection: $item.sourceID) {
                        ForEach(model.emitters) { emitter in
                            Text(emitter.name).tag(emitter.id)
                        }
                    }
                    Picker("Particles", selection: $item.occasion) {
                        ForEach(EventBurst.Occasion.allCases, id: \.self) { occasion in
                            Text(occasion == .collision ? "Hit a Collider" : "Die").tag(occasion)
                        }
                    }
                    Picker("Burst From", selection: $item.targetID) {
                        ForEach(model.emitters) { emitter in
                            Text(emitter.name).tag(emitter.id)
                        }
                    }
                    Stepper("Count: \(item.count)", value: $item.count, in: 1...1_000)
                    if !sourceReports(item) {
                        Label("Turn on \(item.occasion == .collision ? "Report Collisions" : "Report Deaths") in the source emitter's Collision section, or this never fires.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    Button("Remove Burst", systemImage: "trash", role: .destructive) {
                        model.eventBurstItems.removeAll { $0.id == item.id }
                    }
                }
            }
            Button("Add Burst", systemImage: "plus") { model.addEventBurst() }
                .disabled(model.emitters.isEmpty)
        } header: {
            Text("Event Bursts")
        } footer: {
            Text("The source emitter must report its events: an Events module with Report Collisions or Report Deaths.")
        }
    }

    /// Whether the source emitter reports the events this burst waits for.
    private func sourceReports(_ item: EventBurstItem) -> Bool {
        guard let source = model.emitters.first(where: { $0.id == item.sourceID }) else {
            return false
        }
        return item.occasion == .collision ? source.modules.events?.reportsCollisions ?? false : source.modules.events?.reportsDeaths ?? false
    }

    private func summary(_ item: EventBurstItem) -> String {
        let source = model.emitters.first { $0.id == item.sourceID }?.name ?? "?"
        let target = model.emitters.first { $0.id == item.targetID }?.name ?? "?"
        return "\(source) \(item.occasion == .collision ? "hits" : "deaths") → \(item.count) from \(target)"
    }
}

/// Stand-ins for app objects that "object enters" triggers watch.
struct TrackedObjectsSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            ForEach($model.trackedObjectItems) { $item in
                DisclosureGroup(item.name) {
                    TextField("Name", text: $item.name)
                    PathMotionEditorView(motion: $item.motion)
                    Button("Remove Object", systemImage: "trash", role: .destructive) {
                        model.trackedObjectItems.removeAll { $0.id == item.id }
                    }
                }
            }
            Button("Add Object", systemImage: "plus") { model.addTrackedObject() }
        } header: {
            Text("Tracked Objects")
        } footer: {
            Text("Triggers on emitters fire when an object of that name enters their volume.")
        }
    }
}

/// Where the pointer goes when the mouse is away (and in renders and videos): what pointer-bound items follow.
struct ScriptedPointerSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Scripted Pointer") {
            DisclosureGroup("Path") {
                PathMotionEditorView(motion: $model.pointerMotion)
            }
            .help("Pointer-bound colliders, fields, and emitters follow this when the mouse is not over the view.")
        }
    }
}
