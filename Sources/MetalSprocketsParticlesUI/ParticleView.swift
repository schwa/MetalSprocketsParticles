import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

/// Shows a particle system with no MetalSprockets setup: no render passes, simulate or render calls, or camera
/// matrices.
///
/// ```swift
/// ParticleView(try ParticleSystem(contentsOf: campfireURL))
/// ```
///
/// The view uses the system's camera, draws colliders as solids when the system asks for it, and moves pointer-bound
/// colliders, force fields, and emitters with the mouse. To restart, pause, change speed, or send events, make the
/// runtime yourself and pass it with `init(runtime:system:)`.
public struct ParticleView: View {
    private let system: ParticleSystem
    private let runtime: ParticleSystemRuntime?
    private var cameraEye: SIMD3<Float>?
    private var cameraTarget: SIMD3<Float>?
    @State private var state: ParticleViewState
    @State private var viewSize: CGSize = .zero

    /// Shows `system` in a runtime the view makes. A different system (by name) starts over.
    public init(_ system: ParticleSystem, seed: UInt32 = 0) {
        self.system = system
        self.runtime = nil
        _state = State(initialValue: ParticleViewState(seed: seed))
    }

    /// Shows your `runtime`, which should have `system` loaded. The view simulates and draws it; you keep control of
    /// playback (`state`, `speedFactor`, `restart()`) and events (`send(event:)`).
    public init(runtime: ParticleSystemRuntime, system: ParticleSystem) {
        self.system = system
        self.runtime = runtime
        _state = State(initialValue: ParticleViewState(seed: 0))
    }

    /// Looks from `eye` at `target` instead of the system's camera.
    public func camera(eye: SIMD3<Float>, target: SIMD3<Float>) -> Self {
        var view = self
        view.cameraEye = eye
        view.cameraTarget = target
        return view
    }

    public var body: some View {
        let eye = cameraEye ?? system.cameraEye
        let target = cameraTarget ?? system.cameraTarget
        RenderView(colorPixelFormat: ParticleSystemRuntime.colorPixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
            let frame = try state.frame(
                system: system,
                runtime: runtime,
                camera: (eye, target),
                drawableSize: size,
                time: context.frameUniforms.time
            )
            try frame.runtime.simulate(
                deltaTime: context.frameUniforms.deltaTime,
                colliders: frame.colliders,
                transforms: frame.transforms,
                trackedObjects: frame.trackedObjects,
                view: frame.view
            )
            try frame.runtime.renderScene(projection: frame.projection, view: frame.view, sceneDepth: frame.sceneDepth)
        }
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

/// What one frame needs, worked out by `ParticleViewState`.
struct ParticleViewFrame {
    var runtime: ParticleSystemRuntime
    var projection: simd_float4x4
    var view: simd_float4x4
    var sceneDepth: SceneDepth?
    var colliders: [Collider]
    var transforms: [simd_float4x4]
    var trackedObjects: [String: SIMD3<Float>]
}

/// The view's long-lived state: its own runtime (when the caller passes none), the scene depth texture, and the
/// pointer. Rendering reads and writes it every frame, so nothing here is observed.
final class ParticleViewState {
    private let seed: UInt32
    private(set) var ownedRuntime: ParticleSystemRuntime?
    private var loadedSystemName: String?
    private var sceneDepth: SceneDepth?
    /// The mouse location as a fraction of the view (0...1, origin top left), or nil when it is outside.
    var pointerLocation: CGPoint?

    init(seed: UInt32) {
        self.seed = seed
    }

    func frame(
        system: ParticleSystem,
        runtime callerRuntime: ParticleSystemRuntime?,
        camera: (eye: SIMD3<Float>, target: SIMD3<Float>),
        drawableSize: CGSize,
        time: Float
    ) throws -> ParticleViewFrame {
        let (eye, target) = camera
        let runtime = try callerRuntime ?? ownRuntime(for: system)
        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
        let cameraToWorld = simd_float4x4(lookingFrom: eye, at: target)
        let pointer = pointerLocation.flatMap {
            PointerProjection.worldPosition(of: $0, in: CGSize(width: 1, height: 1), projection: projection, cameraToWorld: cameraToWorld, planePoint: target)
        }
        runtime.forceFields = system.forceFields(at: time, pointer: pointer)
        return ParticleViewFrame(
            runtime: runtime,
            projection: projection,
            view: cameraToWorld.inverse,
            sceneDepth: try sceneDepth(for: system, device: runtime.device, size: drawableSize),
            colliders: system.colliders(at: time, pointer: pointer),
            transforms: system.transforms(at: time, pointer: pointer),
            trackedObjects: system.trackedObjectPositions(at: time)
        )
    }

    /// The view's own runtime, loaded with `system`; a different system starts over.
    func ownRuntime(for system: ParticleSystem) throws -> ParticleSystemRuntime {
        if let ownedRuntime, loadedSystemName == system.name {
            return ownedRuntime
        }
        let runtime = try ParticleSystemRuntime(emitters: [], capacity: 1, seed: seed)
        try runtime.load(system)
        ownedRuntime = runtime
        loadedSystemName = system.name
        return runtime
    }

    /// A scene depth texture of the drawable's size when the system draws colliders.
    func sceneDepth(for system: ParticleSystem, device: MTLDevice, size: CGSize) throws -> SceneDepth? {
        guard system.drawsColliders else {
            return nil
        }
        let width = Int(size.width)
        let height = Int(size.height)
        if let sceneDepth, sceneDepth.width == width, sceneDepth.height == height {
            return sceneDepth
        }
        sceneDepth = try SceneDepth(device: device, width: width, height: height)
        return sceneDepth
    }
}
