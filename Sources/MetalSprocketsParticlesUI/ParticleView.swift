import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

/// Shows a particle system with no MetalSprockets setup: no render passes, simulate or render calls, or camera
/// matrices. It plays the system with a `ParticlePlayer`.
///
/// ```swift
/// ParticleView(try ParticleSystem(contentsOf: campfireURL))
/// ```
///
/// The view is transparent, so it can sit over other SwiftUI content; give it a `.background` for a solid color. It uses
/// the system's camera unless you choose another (`camera(_:)`), draws colliders as solids when the system asks for it,
/// and moves pointer-bound colliders, force fields, and emitters with the mouse. To restart, pause, change speed, or send
/// events, make the runtime yourself and pass it with `init(runtime:system:)`.
///
/// Make the system once (a stored property or `@State`), not in `body`. A system built in `body` gets new emitter ids
/// each time SwiftUI updates the view, and the view starts the effect over.
///
/// For effects over an app's UI, use the overlay camera and let hits pass through:
///
/// ```swift
/// content.overlay {
///     ParticleView(confetti).camera(.overlay).allowsHitTesting(false)
/// }
/// ```
public struct ParticleView: View {
    private let system: ParticleSystem
    private let runtime: ParticleSystemRuntime?
    private let seed: UInt32
    private var camera: ParticleCamera = .system
    @State private var state = ParticleViewState()
    @State private var viewSize: CGSize = .zero

    /// Shows `system` in a runtime the view makes. A different system (by name) starts over.
    public init(_ system: ParticleSystem, seed: UInt32 = 0) {
        self.system = system
        self.runtime = nil
        self.seed = seed
    }

    /// Shows your `runtime`, which should have `system` loaded. The view simulates and draws it; you keep control of
    /// playback (`state`, `speedFactor`, `restart()`) and events (`send(event:)`).
    public init(runtime: ParticleSystemRuntime, system: ParticleSystem) {
        self.system = system
        self.runtime = runtime
        self.seed = 0
    }

    /// Uses `camera` instead of the system's camera.
    public func camera(_ camera: ParticleCamera) -> Self {
        var view = self
        view.camera = camera
        return view
    }

    /// Looks from `eye` at `target` instead of the system's camera.
    public func camera(eye: SIMD3<Float>, target: SIMD3<Float>) -> Self {
        camera(.lookAt(eye: eye, target: target))
    }

    public var body: some View {
        let system = system
        let runtime = runtime
        let seed = seed
        let camera = camera
        let sizeInPoints = viewSize
        RenderView(colorPixelFormat: ParticleSystemRuntime.colorPixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
            // Before the first layout pass the view's size is unknown; treat pixels as points until then.
            let points = sizeInPoints.width > 0 ? sizeInPoints : size
            let player = try state.player(system: system, runtime: runtime, seed: seed, camera: camera, size: points)
            try player.frame(deltaTime: context.frameUniforms.deltaTime, size: points, scale: size.width / max(points.width, 1))
        }
        // Transparent, so the view composites over whatever is behind it.
        .metalClearColor(MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0))
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .onContinuousHover { phase in
            switch phase {
            case let .active(location) where viewSize.width > 0 && viewSize.height > 0:
                state.pointerLocation = CGPoint(x: location.x / viewSize.width, y: location.y / viewSize.height)
            default:
                state.pointerLocation = nil
            }
        }
    }
}
