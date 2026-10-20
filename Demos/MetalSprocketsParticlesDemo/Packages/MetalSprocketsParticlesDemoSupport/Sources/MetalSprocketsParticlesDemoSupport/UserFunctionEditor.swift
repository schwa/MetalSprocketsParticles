import Metal
import MetalSprocketsParticles
import SwiftUI

/// The four places a user function plugs into the simulation, with a starting template for each.
enum UserFunctionSlot: String, CaseIterable, Identifiable {
    case update = "Update"
    case spawn = "Spawn"
    case collision = "Collision"
    case death = "Death"

    var id: Self { self }

    var detail: String {
        switch self {
        case .update: "Runs every step for every live particle."
        case .spawn: "Runs once when a particle is born."
        case .collision: "Runs when a particle hits a collider."
        case .death: "Runs as a particle dies."
        }
    }

    /// A function that compiles as is, with an example that uses a parameter.
    var template: ParticleFunction {
        let name = "\(rawValue.lowercased())Particle"
        let body = switch self {
        case .update:
            "    // A sideways wobble; parameters[0].x sets how strong.\n    particle.velocity.x += sin(time * 3 + float(particle.id)) * parameters[0].x * deltaTime;"
        case .spawn:
            "    // A random tint per particle; parameters[0].x mixes it in.\n    float hue = fract(float(particle.id) * 0.618034);\n    particle.color.rgb = mix(float3(1), float3(hue, 1 - hue, 0.5), parameters[0].x);"
        case .collision:
            "    // Bounce harder; parameters[0].x multiplies the speed.\n    particle.velocity *= 1 + parameters[0].x;"
        case .death:
            "    // Flash before going; parameters[0].x is how bright.\n    particle.color.rgb *= 1 + parameters[0].x;"
        }
        let source = "[[visible]] void \(name)(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {\n\(body)\n}\n"
        return ParticleFunction(source: source, name: name, parameters: [[0.5, 0, 0, 0]])
    }
}

/// The emitter's user functions: one editor per slot, plus how many custom attributes particles keep.
struct UserFunctionsSectionView: View {
    @Binding var modules: EmitterModules

    var body: some View {
        Section {
            ForEach(UserFunctionSlot.allCases) { slot in
                UserFunctionEditorView(slot: slot, modules: $modules)
            }
            ParameterSliderView("Custom Attributes", value: $modules.editableCustomAttributeCount, in: 1...4, format: .number.precision(.fractionLength(0)))
                .help("How many of ParticleState.custom through custom3 each particle keeps between steps.")
        } header: {
            Text("User Functions")
        } footer: {
            Text("Metal code run per particle. Source is compiled after ParticleFunction.prelude, which declares ParticleState.")
        }
    }
}

/// Edits one slot's function. Source and name are drafts until Compile & Apply, which checks them with the Metal
/// compiler first, so typing does not recompile (and restart) the effect on every key. Parameters apply at once.
struct UserFunctionEditorView: View {
    let slot: UserFunctionSlot
    @Binding var modules: EmitterModules
    @State private var draftSource = ""
    @State private var draftName = ""
    @State private var compileError: String?

    var body: some View {
        DisclosureGroup {
            Toggle("Enabled", isOn: $modules[hasFunction: slot])
                .help(slot.detail)
            if let current = function {
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
                    Button("Compile & Apply") { apply(to: current) }
                        .disabled(draftSource == current.source && draftName == current.name)
                    Button("Revert") { loadDrafts() }
                        .disabled(draftSource == current.source && draftName == current.name)
                }
                ParametersEditorView(parameters: $modules[editableFunction: slot].parameters)
            }
        } label: {
            Text(slot.rawValue + (function == nil ? "" : " ●"))
        }
        .onChange(of: function, initial: true) { _, _ in
            loadDrafts()
        }
    }

    private var function: ParticleFunction? {
        modules[function: slot]
    }

    private func loadDrafts() {
        draftSource = function?.source ?? ""
        draftName = function?.name ?? ""
        compileError = nil
    }

    private func apply(to current: ParticleFunction) {
        let candidate = ParticleFunction(source: draftSource, name: draftName, parameters: current.parameters)
        do {
            try candidate.validate(device: ParticleSystemRuntime.defaultDevice())
            compileError = nil
            modules[function: slot] = candidate
        } catch {
            compileError = error.localizedDescription
        }
    }
}

/// A function's parameters, four numbers each, read by the code as `parameters[i]`.
struct ParametersEditorView: View {
    @Binding var parameters: [SIMD4<Float>]

    var body: some View {
        // Parameters are positional (the code reads parameters[i]), so the index is their identity.
        ForEach(parameters.indices, id: \.self) { index in
            LabeledContent("parameters[\(index)]") {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { component in
                        TextField("", value: $parameters[index][component], format: .number.precision(.fractionLength(0...3)))
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }
            }
        }
        HStack {
            Button("Add Parameter", systemImage: "plus") { parameters.append(.zero) }
                .disabled(parameters.count >= ParticleFunction.minimumParameterCount)
            Button("Remove Last", systemImage: "minus") { parameters.removeLast() }
                .disabled(parameters.isEmpty)
        }
    }
}
