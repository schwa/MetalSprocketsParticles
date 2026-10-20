import MetalSprocketsParticles
import SwiftUI

// Emitter settings that are not modules: capacity, sprite, what particles are drawn as, and how the emitter moves.

struct CapacityView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @Binding var emitter: EmitterDescription

    var body: some View {
        LabeledContent("Max Particles") {
            // Each new capacity rebuilds the buffer and restarts the effect, so only a finished number is applied.
            CommittedNumberField("Max Particles", value: $emitter.editableCapacity)
                .frame(width: 110)
        }
        .help("Particles this emitter can have alive at once. Changing it restarts the effect. The limit is the GPU's largest buffer (80 bytes a particle).")
        if let capacityError = model.capacityError {
            Label(capacityError, systemImage: "xmark.octagon")
                .font(.caption)
                .foregroundStyle(.red)
        }
        if let needed = emitter.modules.particlesNeeded(capacity: emitter.capacity) {
            Label("Needs about \(needed.formatted()) at this rate and lifetime; newest particles replace the oldest early.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct AppearanceSectionView: View {
    @Binding var emitter: EmitterDescription
    @State private var isChoosingColorImage = false
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        Section("Appearance") {
            KindPicker("Sprite", selection: $emitter.sprite)
            Picker("Draw As", selection: $emitter.modules.drawing) {
                ForEach(ParticleDrawing.allCases.filter { $0 != .custom || emitter.modules.drawing == .custom }) { drawing in
                    Text(drawing.rawValue).tag(drawing)
                }
            }
            .help("Sprites, or a small mesh per particle (lit, turned by the particle's orientation and spin).")
            if !hasColorImage {
                Button("Add Color Image…") { isChoosingColorImage = true }
                    .help("Multiplies each particle's color by an image laid over the world, under the particle.")
            }
        }
        .fileImporter(isPresented: $isChoosingColorImage, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let image = try ParticleColorImage.choosing(data: Data(contentsOf: url), replacing: nil)
                emitter.modules.spawn.append(ModuleSlot(.colorImage(ColorImageModule(image: image))))
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
    }

    private var hasColorImage: Bool {
        emitter.modules.spawn.contains { if case .colorImage = $0.module { true } else { false } }
    }
}

/// How the emitter itself moves, and the space its particles live in.
struct EmitterMotionSectionView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @Binding var emitter: EmitterDescription

    var body: some View {
        @Bindable var model = model
        Section("Emitter Motion") {
            Toggle("Follow Pointer", isOn: $model.selectedEmitterFollowsPointer)
            KindPicker("Path", selection: $emitter.motion.kind)
            if emitter.motion.kind != .still {
                ParameterSliderView("Path Radius", value: $emitter.motion.radius, in: 0...4)
                ParameterSliderView("Path Speed", value: $emitter.motion.speed, in: 0...5)
            }
            DisclosureGroup("Placement") {
                VectorEditorView("Offset", value: $emitter.motion.offset, in: -5...5)
                ParameterSliderView("Yaw", value: $emitter.motion.yaw, in: -.pi ... .pi)
                ParameterSliderView("Pitch", value: $emitter.motion.pitch, in: -.pi ... .pi)
                ParameterSliderView("Spin", value: $emitter.motion.spin, in: -10...10)
            }
            KindPicker("Simulation Space", selection: $emitter.simulationSpace)
        }
    }
}

extension EmitterModules {
    /// The enabled shape module's shape.
    var shape: EmitterShape? {
        for slot in spawn where slot.isEnabled {
            if case let .shape(module) = slot.module {
                return module.shape
            }
        }
        return nil
    }
}
