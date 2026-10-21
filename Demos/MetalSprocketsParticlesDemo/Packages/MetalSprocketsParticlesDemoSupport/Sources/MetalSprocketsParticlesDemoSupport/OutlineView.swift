import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import SwiftUI

/// An item in the outline sidebar. Sub-emitters and triggers have no ids in the library, so they are identified by
/// their emitter and position.
enum OutlineItem: Hashable {
    case scene
    case emitter(EmitterDescription.ID)
    case subEmitter(EmitterDescription.ID, Int)
    case trigger(EmitterDescription.ID, Int)
    /// A module in one of the emitter's stacks, by index.
    case module(EmitterDescription.ID, ModuleStage, Int)
    case collider(ColliderItem.ID)
    case forceField(ForceFieldItem.ID)

    /// The emitter this item belongs to, if any.
    var emitterID: EmitterDescription.ID? {
        switch self {
        case let .emitter(id), let .subEmitter(id, _), let .trigger(id, _), let .module(id, _, _): id
        default: nil
        }
    }
}

extension Array where Element: Identifiable {
    /// The element with `id`, for key-path bindings. Setting `nil` or an unknown id does nothing.
    subscript(id id: Element.ID) -> Element? {
        get { first { $0.id == id } }
        set {
            if let newValue, let index = firstIndex(where: { $0.id == id }) {
                self[index] = newValue
            }
        }
    }
}

/// The leading sidebar: everything in the scene, nested emitter children included.
struct OutlineView: View {
    @Environment(ParticlesDemoModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Label("Scene", systemImage: "cube.transparent")
                .tag(OutlineItem.scene)
            Section("Emitters") {
                ForEach(model.emitters) { emitter in
                    EmitterOutlineRow(emitter: emitter)
                }
            }
            Section("Colliders") {
                ForEach(model.colliders) { item in
                    Label(item.collider.kind.name, systemImage: "square.on.circle")
                        .tag(OutlineItem.collider(item.id))
                }
            }
            Section("Force Fields") {
                ForEach(model.forceFields) { item in
                    Label(item.field.kind.name, systemImage: "wind")
                        .tag(OutlineItem.forceField(item.id))
                }
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
        .onDeleteCommand { model.removeSelection() }
        #endif
        .toolbar {
            ToolbarItem {
                Menu("Add", systemImage: "plus") {
                    Button("Emitter") { model.addEmitter() }
                    if let emitterID = model.selection?.emitterID {
                        Button("Sub-Emitter") { model.addSubEmitter(to: emitterID) }
                        Button("Trigger") { model.addTrigger(to: emitterID) }
                    }
                    Menu("Collider") {
                        ForEach(ParticleColliderKind.allCases) { kind in
                            Button(kind.name) { model.addCollider(kind) }
                        }
                    }
                    Menu("Force Field") {
                        ForEach(ParticleForceFieldKind.allCases) { kind in
                            Button(kind.name) { model.addForceField(kind) }
                        }
                    }
                }
            }
        }
    }
}

struct EmitterOutlineRow: View {
    let emitter: EmitterDescription
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            // Collapsed at first: every emitter has several modules.
            DisclosureGroup("Modules") {
                ForEach(ModuleStage.allCases) { stage in
                    let labels = stage.labels(of: emitter.modules)
                    ForEach(labels.indices, id: \.self) { index in
                        Label("\(stage.rawValue): \(labels[index].title)", systemImage: labels[index].isEnabled ? "square.stack.3d.up" : "square.stack.3d.up.slash")
                            .tag(OutlineItem.module(emitter.id, stage, index))
                    }
                }
            }
            ForEach(emitter.modules.subEmitters.indices, id: \.self) { index in
                Label(emitter.modules.subEmitters[index].occasion.kind.name, systemImage: "sparkles")
                    .tag(OutlineItem.subEmitter(emitter.id, index))
            }
            ForEach(emitter.modules.triggers.indices, id: \.self) { index in
                let trigger = emitter.modules.triggers[index]
                Label("\(trigger.condition.kind.name) → \(trigger.action.kind.name)", systemImage: "bolt")
                    .tag(OutlineItem.trigger(emitter.id, index))
            }
        } label: {
            EmitterOutlineLabelView(emitter: emitter)
        }
    }
}

/// The emitter's row label: selectable, with actions to add children.
struct EmitterOutlineLabelView: View {
    @Environment(ParticlesDemoModel.self) private var model
    let emitter: EmitterDescription

    var body: some View {
        Label(emitter.name, systemImage: emitter.isEmitting ? "circle.dotted.circle" : "circle.dashed")
            .tag(OutlineItem.emitter(emitter.id))
            .contextMenu {
                Button("Add Sub-Emitter") { model.addSubEmitter(to: emitter.id) }
                Button("Add Trigger") { model.addTrigger(to: emitter.id) }
            }
    }
}
