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
            Text("Built-in modules run at fixed points in the simulation. Stitched user modules run in their order, after the particles move.")
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
                    // Only user modules have an order; built-ins run at fixed points (Documentation/Modules.md).
                    if stack[index].module.kind == "stitched" {
                        let previous = stack[..<index].lastIndex { $0.module.kind == "stitched" }
                        let next = stack[(index + 1)...].firstIndex { $0.module.kind == "stitched" }
                        Button("Move Up", systemImage: "chevron.up") { previous.map { stack.swapAt(index, $0) } }
                            .disabled(previous == nil)
                        Button("Move Down", systemImage: "chevron.down") { next.map { stack.swapAt(index, $0) } }
                            .disabled(next == nil)
                    }
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
