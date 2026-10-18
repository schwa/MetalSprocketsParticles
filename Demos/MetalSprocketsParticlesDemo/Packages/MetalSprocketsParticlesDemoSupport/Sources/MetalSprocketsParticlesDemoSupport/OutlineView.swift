import MetalSprocketsParticles
import SwiftUI

/// An item in the outline sidebar. Sub-emitters and triggers have no ids in the library, so they are identified by
/// their emitter and position.
enum OutlineItem: Hashable {
    case scene
    case emitter(EmitterDescription.ID)
    case subEmitter(EmitterDescription.ID, Int)
    case trigger(EmitterDescription.ID, Int)
    case collider(ColliderItem.ID)
    case forceField(ForceFieldItem.ID)

    /// The emitter this item belongs to, if any.
    var emitterID: EmitterDescription.ID? {
        switch self {
        case let .emitter(id), let .subEmitter(id, _), let .trigger(id, _): id
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
    @Bindable var model: ParticlesDemoModel

    var body: some View {
        List(selection: $model.selection) {
            Label("Scene", systemImage: "cube.transparent")
                .tag(OutlineItem.scene)
            Section("Emitters") {
                ForEach(model.emitters) { emitter in
                    EmitterOutlineRow(model: model, emitter: emitter)
                }
            }
            Section("Colliders") {
                ForEach(model.colliders) { item in
                    Label(item.collider.kind.rawValue, systemImage: "square.on.circle")
                        .tag(OutlineItem.collider(item.id))
                }
            }
            Section("Force Fields") {
                ForEach(model.forceFields) { item in
                    Label(item.field.kind.rawValue, systemImage: "wind")
                        .tag(OutlineItem.forceField(item.id))
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { model.removeSelection() }
        .toolbar {
            ToolbarItem {
                Menu("Add", systemImage: "plus") {
                    Button("Emitter") { model.addEmitter() }
                    if let emitterID = model.selection?.emitterID {
                        Button("Sub-Emitter") { model.addSubEmitter(to: emitterID) }
                        Button("Trigger") { model.addTrigger(to: emitterID) }
                    }
                    Menu("Collider") {
                        ForEach(ColliderKind.allCases) { kind in
                            Button(kind.rawValue) { model.addCollider(kind) }
                        }
                    }
                    Menu("Force Field") {
                        ForEach(ForceFieldKind.allCases) { kind in
                            Button(kind.rawValue) { model.addForceField(kind) }
                        }
                    }
                }
            }
        }
    }
}

struct EmitterOutlineRow: View {
    let model: ParticlesDemoModel
    let emitter: EmitterDescription
    @State private var isExpanded = true

    var body: some View {
        let children = emitter.settings.subEmitters.count + emitter.settings.triggers.count
        if children == 0 {
            emitterLabel
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(emitter.settings.subEmitters.indices, id: \.self) { index in
                    Label(emitter.settings.subEmitters[index].occasionKind.rawValue, systemImage: "sparkles")
                        .tag(OutlineItem.subEmitter(emitter.id, index))
                }
                ForEach(emitter.settings.triggers.indices, id: \.self) { index in
                    let trigger = emitter.settings.triggers[index]
                    Label("\(trigger.conditionKind.rawValue) → \(trigger.actionKind.rawValue)", systemImage: "bolt")
                        .tag(OutlineItem.trigger(emitter.id, index))
                }
            } label: {
                emitterLabel
            }
        }
    }

    private var emitterLabel: some View {
        Label(emitter.name, systemImage: emitter.isEmitting ? "circle.dotted.circle" : "circle.dashed")
            .tag(OutlineItem.emitter(emitter.id))
            .contextMenu {
                Button("Add Sub-Emitter") { model.addSubEmitter(to: emitter.id) }
                Button("Add Trigger") { model.addTrigger(to: emitter.id) }
            }
    }
}
