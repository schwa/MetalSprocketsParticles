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
                    SidebarTabsView()
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
    /// Births and deaths per second (`ParticleSystemRuntime.birthsPerSecond` and `deathsPerSecond`).
    var birthsPerSecond: Double = 0
    var deathsPerSecond: Double = 0
    /// A finite effect has ended (see `ParticleSystemRuntime.isFinished`); Restart plays it again.
    var isFinished = false

    /// The widest rates shown; rates are sized for them, so the panel keeps its width.
    private static let birthTemplate = "+9,999,999/s"
    private static let deathTemplate = "\u{2212}9,999,999/s"

    var body: some View {
        // The panel is centered over the viewport, so each changing number sits in a slot sized for its widest value;
        // otherwise every change in digit count moves the whole panel.
        HStack(alignment: .firstTextBaseline) {
            FixedWidthText(alive.formatted(.number), template: capacity.formatted(.number))
                .font(.title.bold())
            Text("/ \(capacity, format: .number) particles")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                FixedWidthText("+\(birthsPerSecond.formatted(.number.precision(.fractionLength(0))))/s", template: Self.birthTemplate)
                FixedWidthText("\u{2212}\(deathsPerSecond.formatted(.number.precision(.fractionLength(0))))/s", template: Self.deathTemplate)
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .help("Particles born and died per second, over the last half second")
            // Space kept for the badge, so finishing does not widen the panel either.
            FixedWidthText(isFinished ? "Finished" : "", template: "Finished")
                .font(.title3.bold())
                .foregroundStyle(.orange)
        }
        .monospacedDigit()
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: .rect(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alive) of \(capacity) particles, \(Int(birthsPerSecond)) born and \(Int(deathsPerSecond)) died per second")
    }
}

/// `text`, right-aligned in the width `template` would take, so changing numbers do not change the layout.
struct FixedWidthText: View {
    let text: String
    let template: String

    init(_ text: String, template: String) {
        self.text = text
        self.template = template
    }

    var body: some View {
        Text(template)
            .hidden()
            .overlay(alignment: .trailing) {
                Text(text)
                    .fixedSize()
            }
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
    @AppStorage(RenderingDefaults.colorFormat) private var colorFormat: ViewportColorFormat = .srgb8
    @AppStorage(RenderingDefaults.framebufferOnly) private var framebufferOnly = true
    @AppStorage(RenderingDefaults.framesPerSecond) private var framesPerSecond = 120
    @AppStorage(RenderingDefaults.extendedDynamicRange) private var extendedDynamicRange = false
    @State private var cameraMatrix = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0])
    @State private var frameTiming: FrameTimingStatistics?
    @State private var aliveParticles = 0
    @State private var birthsPerSecond: Double = 0
    @State private var deathsPerSecond: Double = 0
    @State private var isFinished = false
    @State private var viewSize: CGSize = .zero

    /// Matches OffscreenRenderer, so golden images and particles-render show what the app shows.
    static let colorPixelFormat = ParticleSystemRuntime.colorPixelFormat

    var body: some View {
        if let system = model.system {
            RenderView(colorPixelFormat: colorFormat.pixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
                let aspect = Float(size.width / max(size.height, 1))
                // The demo owns its 3D camera (the orbit controls); in 2D the overlay camera maps one unit to one point of
                // the view. Either way it passes matrices to the player.
                let overlay = ParticleCamera.overlay.matrices(for: model.currentEffect, size: viewSize)
                let plainProjection = model.is2D ? overlay.projection : simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                let projection = model.reverseZ ? ParticleSystemRuntime.reversingDepth(plainProjection) : plainProjection
                let cameraToWorld = model.is2D ? overlay.cameraToWorld : cameraMatrix
                if let player = try model.player(projection: projection, cameraToWorld: cameraToWorld) {
                    try player.frame(
                        deltaTime: context.frameUniforms.deltaTime,
                        projection: projection,
                        view: cameraToWorld.inverse,
                        sceneDepth: player.sceneDepth(size: size),
                        wireframes: model.showColliders
                    )
                    .gpuTimed("Render")
                }
            }
            .metalFramebufferOnly(framebufferOnly)
            .metalPreferredFramesPerSecond(framesPerSecond)
            .metalWantsExtendedDynamicRangeContent(colorFormat.supportsExtendedDynamicRange && extendedDynamicRange)
            // Reverse Z clears depth to the far plane, 0.
            .metalClearDepth(model.reverseZ ? 0 : 1)
            // A new pixel format or depth convention needs new pipelines and drawables.
            .id("\(colorFormat.rawValue)-\(model.reverseZ)")
            .background(.black)
            .onFrameTimingChange { statistics in
                frameTiming = statistics
                aliveParticles = system.aliveParticleCount
                birthsPerSecond = system.birthsPerSecond
                deathsPerSecond = system.deathsPerSecond
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
                    ParticleCountView(
                        alive: aliveParticles,
                        capacity: system.capacity,
                        birthsPerSecond: birthsPerSecond,
                        deathsPerSecond: deathsPerSecond,
                        isFinished: isFinished
                    )
                        .padding()
                }
            }
        } else {
            ContentUnavailableView("Failed to create particle system", systemImage: "exclamationmark.triangle")
        }
    }
}
