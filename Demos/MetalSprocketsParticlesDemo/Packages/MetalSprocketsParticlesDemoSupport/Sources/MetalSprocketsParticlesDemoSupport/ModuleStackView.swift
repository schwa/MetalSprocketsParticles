import MetalSprocketsParticles
import SwiftUI

/// The emitter's module stacks (#196): turn modules on and off, reorder, add, and remove them. The sections below
/// edit the settings of the modules that are present.
struct ModuleStacksSectionView: View {
    @Binding var modules: EmitterModules

    var body: some View {
        Section {
            ModuleStackView(title: "Spawn", stack: $modules.spawn)
            ModuleStackView(title: "Update", stack: $modules.update)
            ModuleStackView(title: "Render", stack: $modules.render)
        } header: {
            Text("Modules")
        } footer: {
            Text("Built-in modules run in the simulation's fixed order; stitched user modules run in stack order.")
        }
    }
}

struct ModuleStackView<Module: StageModule>: View {
    let title: String
    @Binding var stack: [ModuleSlot<Module>]

    var body: some View {
        DisclosureGroup("\(title) (\(stack.count))") {
            ForEach(stack.indices, id: \.self) { index in
                HStack {
                    Toggle(Self.label(stack[index].module), isOn: $stack[index].isEnabled)
                        .disabled(stack[index].module.isRequired)
                    Spacer()
                    Button("Move Up", systemImage: "chevron.up") { stack.swapAt(index, index - 1) }
                        .disabled(index == 0)
                    Button("Move Down", systemImage: "chevron.down") { stack.swapAt(index, index + 1) }
                        .disabled(index == stack.count - 1)
                    Button("Remove", systemImage: "minus.circle", role: .destructive) { stack.remove(at: index) }
                        .disabled(stack[index].module.isRequired)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            let present = Set(stack.map(\.module.kind))
            let missing = Module.addable.filter { !present.contains($0.kind) }
            if !missing.isEmpty {
                Menu("Add \(title) Module") {
                    ForEach(missing.indices, id: \.self) { index in
                        Button(Self.label(missing[index])) { stack.append(ModuleSlot(missing[index])) }
                    }
                }
            }
        }
    }

    /// "colorOverLife" as "Color Over Life".
    static func label(_ module: Module) -> String {
        switch module.module {
        case let stitched as StitchedUpdateModule: return "Stitched: \(stitched.module.name)"
        case let stitched as StitchedSpawnModule: return "Stitched: \(stitched.module.name)"
        default: break
        }
        let kind = module.kind
        var words = ""
        for character in kind {
            if character.isUppercase {
                words += " "
            }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
