import Metal
import MetalSprocketsParticles
import SwiftUI

/// The right sidebar: the inspector for the outline's selection, or the viewport's rendering settings.
struct SidebarTabsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case inspector = "inspector-tab"
        case rendering = "rendering-tab"

        var id: Self { self }

        var name: String {
            switch self {
            case .inspector: "Inspector"
            case .rendering: "Rendering"
            }
        }
    }

    @AppStorage("sidebarTab") private var tab: Tab = .inspector

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.name).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch tab {
            case .inspector:
                EmitterInspectorView()
            case .rendering:
                RenderingSettingsView()
            }
        }
    }
}

/// Color formats the viewport can render to.
enum ViewportColorFormat: String, CaseIterable, Identifiable {
    // Stored in user defaults, so the raw values are spelled out.
    /// What golden images and particles-render use.
    case srgb8 = "srgb-8"
    case linear8 = "linear-8"
    case tenBit = "rgb-10"
    case float16 = "float-16"

    var id: Self { self }

    var name: String {
        switch self {
        case .srgb8: "8-bit sRGB"
        case .linear8: "8-bit Linear"
        case .tenBit: "10-bit"
        case .float16: "16-bit Float"
        }
    }

    var pixelFormat: MTLPixelFormat {
        switch self {
        case .srgb8: ParticleSystemRuntime.colorPixelFormat
        case .linear8: .bgra8Unorm
        case .tenBit: .bgr10a2Unorm
        case .float16: .rgba16Float
        }
    }

    /// Extended dynamic range needs a float format.
    var supportsExtendedDynamicRange: Bool {
        self == .float16
    }
}

/// User defaults for the viewport's rendering, shared by the settings and the viewport.
enum RenderingDefaults {
    static let colorFormat = "renderingColorFormat"
    static let framebufferOnly = "renderingFramebufferOnly"
    static let framesPerSecond = "renderingFramesPerSecond"
    static let extendedDynamicRange = "renderingExtendedDynamicRange"
}

/// Settings for how the viewport renders, not what the effect is: pixel format, drawable options, frame rate, depth,
/// and debug views.
struct RenderingSettingsView: View {
    @Environment(ParticlesDemoModel.self) private var model
    @AppStorage(RenderingDefaults.colorFormat) private var colorFormat: ViewportColorFormat = .srgb8
    @AppStorage(RenderingDefaults.framebufferOnly) private var framebufferOnly = true
    @AppStorage(RenderingDefaults.framesPerSecond) private var framesPerSecond = 120
    @AppStorage(RenderingDefaults.extendedDynamicRange) private var extendedDynamicRange = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Drawable") {
                Picker("Pixel Format", selection: $colorFormat) {
                    ForEach(ViewportColorFormat.allCases) { format in
                        Text(format.name).tag(format)
                    }
                }
                .help("The viewport's color format. 8-bit sRGB matches golden images and particles-render.")
                Toggle("Framebuffer Only", isOn: $framebufferOnly)
                    .help("Drawables only render; off lets them be read or copied, which can cost speed.")
                if colorFormat.supportsExtendedDynamicRange {
                    Toggle("Extended Dynamic Range", isOn: $extendedDynamicRange)
                        .help("Show values above 1 as brighter than white on displays that support it.")
                }
                Picker("Frame Rate", selection: $framesPerSecond) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("120").tag(120)
                }
                .help("Frames per second the viewport asks for.")
            }
            Section("Depth") {
                Toggle("Reverse Z", isOn: $model.reverseZ)
                    .help("Depth from 1 (near) to 0 (far), for better precision at a distance.")
            }
            Section("Debug") {
                Picker("Debug View", selection: $model.debugView) {
                    ForEach(ParticleDebugView.allCases, id: \.self) { view in
                        Text(view.name).tag(view)
                    }
                }
                .help("Draw particles in false colors or as wireframes instead of their own colors.")
                Toggle("Wireframes", isOn: $model.showColliders)
                    .help("Colliders, force fields, trigger volumes, and emitter shapes as lines.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }
}
