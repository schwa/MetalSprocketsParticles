import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

/// Shows a particle effect with no MetalSprockets setup: no render passes, simulate or render calls, or camera
/// matrices.
///
/// ```swift
/// ParticleView(try ParticlePreset(contentsOf: campfireURL))
/// ```
///
/// The view uses the preset's camera, draws colliders as solids when the preset asks for it, and moves pointer-bound
/// colliders, force fields, and emitters with the mouse. To restart, pause, change speed, or send events, make the
/// system yourself and pass it with `init(system:preset:)`.
public struct ParticleView: View {
    private let preset: ParticlePreset
    private let system: ParticleSystem?
    private var cameraEye: SIMD3<Float>?
    private var cameraTarget: SIMD3<Float>?
    @State private var state: ParticleViewState
    @State private var viewSize: CGSize = .zero

    /// Shows `preset` in a system the view makes. A different preset (by name) starts over.
    public init(_ preset: ParticlePreset, seed: UInt32 = 0) {
        self.preset = preset
        self.system = nil
        _state = State(initialValue: ParticleViewState(seed: seed))
    }

    /// Shows your `system`, which should have `preset` loaded. The view simulates and draws it; you keep control of
    /// playback (`state`, `speedFactor`, `restart()`) and events (`send(event:)`).
    public init(system: ParticleSystem, preset: ParticlePreset) {
        self.preset = preset
        self.system = system
        _state = State(initialValue: ParticleViewState(seed: 0))
    }

    /// Looks from `eye` at `target` instead of the preset's camera.
    public func camera(eye: SIMD3<Float>, target: SIMD3<Float>) -> Self {
        var view = self
        view.cameraEye = eye
        view.cameraTarget = target
        return view
    }

    public var body: some View {
        let eye = cameraEye ?? preset.cameraEye
        let target = cameraTarget ?? preset.cameraTarget
        RenderView(colorPixelFormat: ParticleSystem.colorPixelFormat, depthStencilPixelFormat: .depth32Float) { context, size in
            let frame = try state.frame(
                preset: preset,
                system: system,
                camera: (eye, target),
                drawableSize: size,
                time: context.frameUniforms.time
            )
            try frame.system.simulate(
                deltaTime: context.frameUniforms.deltaTime,
                colliders: frame.colliders,
                transforms: frame.transforms,
                trackedObjects: frame.trackedObjects,
                view: frame.view
            )
            try frame.system.renderScene(projection: frame.projection, view: frame.view, sceneDepth: frame.sceneDepth)
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
    var system: ParticleSystem
    var projection: simd_float4x4
    var view: simd_float4x4
    var sceneDepth: SceneDepth?
    var colliders: [Collider]
    var transforms: [simd_float4x4]
    var trackedObjects: [String: SIMD3<Float>]
}

/// The view's long-lived state: its own system (when the caller passes none), the scene depth texture, and the pointer.
/// Rendering reads and writes it every frame, so nothing here is observed.
final class ParticleViewState {
    private let seed: UInt32
    private(set) var ownedSystem: ParticleSystem?
    private var loadedPresetName: String?
    private var sceneDepth: SceneDepth?
    /// The mouse location as a fraction of the view (0...1, origin top left), or nil when it is outside.
    var pointerLocation: CGPoint?

    init(seed: UInt32) {
        self.seed = seed
    }

    func frame(
        preset: ParticlePreset,
        system callerSystem: ParticleSystem?,
        camera: (eye: SIMD3<Float>, target: SIMD3<Float>),
        drawableSize: CGSize,
        time: Float
    ) throws -> ParticleViewFrame {
        let (eye, target) = camera
        let system = try callerSystem ?? ownSystem(for: preset)
        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
        let cameraToWorld = simd_float4x4(lookingFrom: eye, at: target)
        let pointer = pointerLocation.flatMap {
            PointerProjection.worldPosition(of: $0, in: CGSize(width: 1, height: 1), projection: projection, cameraToWorld: cameraToWorld, planePoint: target)
        }
        system.forceFields = preset.forceFields(at: time, pointer: pointer)
        return ParticleViewFrame(
            system: system,
            projection: projection,
            view: cameraToWorld.inverse,
            sceneDepth: try sceneDepth(for: preset, device: system.device, size: drawableSize),
            colliders: preset.colliders(at: time, pointer: pointer),
            transforms: preset.transforms(at: time, pointer: pointer),
            trackedObjects: preset.trackedObjectPositions(at: time)
        )
    }

    /// The view's own system, loaded with `preset`; a different preset starts over.
    func ownSystem(for preset: ParticlePreset) throws -> ParticleSystem {
        if let ownedSystem, loadedPresetName == preset.name {
            return ownedSystem
        }
        let system = try ParticleSystem(emitters: [], capacity: 1, seed: seed)
        try system.load(preset)
        ownedSystem = system
        loadedPresetName = preset.name
        return system
    }

    /// A scene depth texture of the drawable's size when the preset draws colliders.
    func sceneDepth(for preset: ParticlePreset, device: MTLDevice, size: CGSize) throws -> SceneDepth? {
        guard preset.drawsColliders else {
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
