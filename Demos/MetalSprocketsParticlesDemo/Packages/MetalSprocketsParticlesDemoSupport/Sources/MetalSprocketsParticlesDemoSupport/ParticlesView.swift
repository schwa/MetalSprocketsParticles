import Interaction3D
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

public struct ParticlesView: View {
    @State private var model = ParticlesDemoModel()
    @State private var isInspectorPresented = true
    @AppStorage(ParticleViewportView.showsOverlaysKey) private var showsOverlays = true
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        NavigationSplitView {
            OutlineView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            ParticleViewportView()
                .inspector(isPresented: $isInspectorPresented) {
                    EmitterInspectorView()
                        .inspectorColumnWidth(min: 300, ideal: 340)
                }
                .toolbar {
                    SceneToolbarContent()
                    ToolbarItem {
                        Button("2D Overlay", systemImage: "square.on.square") {
                            openWindow(id: OverlayDemoView.windowID)
                        }
                        .help("Open the 2D overlay demo")
                    }
                    ToolbarItem {
                        Toggle("Overlays", systemImage: "square.text.square", isOn: $showsOverlays)
                            .keyboardShortcut("h", modifiers: [.command, .shift])
                            .help("Show or hide the frame timing and particle count over the viewport (⇧⌘H)")
                    }
                    ToolbarItem {
                        Button("Inspector", systemImage: "sidebar.trailing") {
                            isInspectorPresented.toggle()
                        }
                    }
                }
        }
        .environment(model)
    }
}

/// The live particle count, large and high-contrast so it reads over any effect.
struct ParticleCountView: View {
    let alive: Int
    let capacity: Int
    /// A finite effect has ended (see `ParticleSystemRuntime.isFinished`); Restart plays it again.
    var isFinished = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(alive, format: .number)
                .font(.title.bold())
            Text("/ \(capacity, format: .number) particles")
                .font(.title3)
                .foregroundStyle(.secondary)
            if isFinished {
                Text("Finished")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }
        }
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alive) of \(capacity) particles")
    }
}

#Preview("Particle Count") {
    ParticleCountView(alive: 44_970, capacity: 100_000)
        .padding()
        .background(.orange)
}

/// The 3D view: simulates and draws the model's particle system each frame, with an orbit camera and frame timing.
struct ParticleViewportView: View {
    /// The user default for showing the frame timing and particle count, shared with the toolbar toggle.
    static let showsOverlaysKey = "showsViewportOverlays"

    @Environment(ParticlesDemoModel.self) private var model
    @AppStorage(showsOverlaysKey) private var showsOverlays = true
    @State private var cameraMatrix = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0])
    @State private var frameTiming: FrameTimingStatistics?
    @State private var aliveParticles = 0
    @State private var isFinished = false
    @State private var viewSize: CGSize = .zero

    /// Matches OffscreenRenderer, so golden images and particles-render show what the app shows.
    static let colorPixelFormat = ParticleSystemRuntime.colorPixelFormat

    var body: some View {
        if let system = model.system {
            RenderView(colorPixelFormat: Self.colorPixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
                let aspect = Float(size.width / max(size.height, 1))
                let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                // The demo owns its camera (the orbit controls), so it passes matrices to the player.
                if let player = try model.player(projection: projection, cameraToWorld: cameraMatrix) {
                    try player.frame(
                        deltaTime: context.frameUniforms.deltaTime,
                        projection: projection,
                        view: cameraMatrix.inverse,
                        sceneDepth: player.sceneDepth(size: size),
                        wireframes: model.showColliders
                    )
                    .gpuTimed("Render")
                }
            }
            .background(.black)
            .onFrameTimingChange { statistics in
                frameTiming = statistics
                aliveParticles = system.aliveParticleCount
                isFinished = system.isFinished
            }
            .interactiveCamera(cameraMatrix: $cameraMatrix, target: model.cameraTarget)
            .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
            // Pointer bindings follow the mouse while it is over the view.
            .onContinuousHover { phase in
                switch phase {
                case let .active(location) where viewSize.width > 0 && viewSize.height > 0:
                    model.pointerLocation = CGPoint(x: location.x / viewSize.width, y: location.y / viewSize.height)
                default:
                    model.pointerLocation = nil
                }
            }
            .onChange(of: model.presetName) {
                cameraMatrix = simd_float4x4(lookingFrom: model.cameraEye, at: model.cameraTarget)
            }
            .overlay(alignment: .topLeading) {
                // Frame timing: FPS, frame time, and GPU time per pass (Simulate, Render).
                if showsOverlays, let frameTiming {
                    // Dark, so its panel and text contrast with the black viewport and bright particles.
                    FrameTimingView(statistics: frameTiming, options: .all)
                        .environment(\.colorScheme, .dark)
                        .padding()
                }
            }
            .overlay(alignment: .top) {
                if showsOverlays {
                    ParticleCountView(alive: aliveParticles, capacity: system.capacity, isFinished: isFinished)
                        .padding()
                }
            }
        } else {
            ContentUnavailableView("Failed to create particle system", systemImage: "exclamationmark.triangle")
        }
    }
}
