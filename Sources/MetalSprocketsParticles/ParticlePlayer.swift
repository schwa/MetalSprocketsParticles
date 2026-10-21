import CoreGraphics
import Metal
import MetalSprockets
import simd

/// Plays a particle system over time: owns a runtime and a clock, and turns each frame's step into simulate and render
/// elements. It works out what changes per frame (animated and spinning colliders, force fields, emitter motion,
/// tracked objects, pointer bindings) and the scene depth for solid colliders.
///
/// ```swift
/// let player = try ParticlePlayer(system: campfire)
/// // Each frame, at the top level of the frame (not inside a RenderPass):
/// try player.frame(deltaTime: deltaTime, size: viewSize, scale: displayScale)
/// ```
///
/// The player is a convenience. Hosts that own their camera, depth, and render passes (a scene graph, for example) can
/// use `frame(deltaTime:projection:view:sceneDepth:wireframes:)`, or drive `runtime` directly.
public final class ParticlePlayer {
    public let runtime: ParticleSystemRuntime
    /// The description being played. Change it with `update(_:)`.
    public private(set) var system: ParticleSystem
    public var camera: ParticleCamera = .system
    /// Where pointer-bound items go, in world space; nil follows `system.pointerMotion`.
    public var pointer: SIMD3<Float>?
    /// Seconds played. Advances only while the runtime is playing, scaled by its `speedFactor`.
    public private(set) var time: Float = 0
    private var ownedSceneDepth: SceneDepth?

    /// A new runtime with `system` loaded.
    public init(system: ParticleSystem, device: MTLDevice = ParticleSystemRuntime.defaultDevice(), seed: UInt32 = 0) throws {
        runtime = try ParticleSystemRuntime(device: device, capacity: 1, seed: seed)
        self.system = system
        try runtime.load(system)
    }

    /// Plays `system` in a runtime you made and loaded yourself.
    public init(runtime: ParticleSystemRuntime, system: ParticleSystem) {
        self.runtime = runtime
        self.system = system
    }

    /// Replaces the description. Particles stay unless the emitter layout changes (emitters added, removed, reordered,
    /// or resized), which rebuilds; settings, colliders, fields, lights, and bindings take effect on the next frame.
    public func update(_ system: ParticleSystem) throws {
        try runtime.apply(system)
        self.system = system
    }

    /// Starts over: the clock goes back to zero and every particle is removed.
    public func restart() {
        time = 0
        runtime.restart()
    }

    /// The camera's matrices for a view of `size` (in points for the overlay camera).
    public func matrices(size: CGSize) -> (projection: simd_float4x4, view: simd_float4x4) {
        let matrices = camera.matrices(for: system, size: size)
        let projection = runtime.reverseZ ? ParticleSystemRuntime.reversingDepth(matrices.projection) : matrices.projection
        return (projection, matrices.cameraToWorld.inverse)
    }

    /// One frame with the player's camera: simulate, then draw into a view of `size` points at `scale` pixels per
    /// point. Makes and resizes the scene depth for solid colliders itself.
    public func frame(deltaTime: Float, size: CGSize, scale: CGFloat = 1, wireframes: Bool = false) throws -> some Element {
        let matrices = matrices(size: size)
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        return try frame(deltaTime: deltaTime, projection: matrices.projection, view: matrices.view, sceneDepth: sceneDepth(size: pixels), wireframes: wireframes)
    }

    /// One frame with your camera and scene depth: simulate, then draw. Pass `sceneDepth` to soften particles against
    /// solid colliders or your own geometry.
    public func frame(
        deltaTime: Float,
        projection: simd_float4x4,
        view: simd_float4x4,
        sceneDepth: SceneDepth? = nil,
        wireframes: Bool = false
    ) throws -> some Element {
        // The clock moves first, so what this step is given (colliders above all) is where it is at the step's end. The
        // runtime turns the change since the last step into velocity and spin using this step's deltaTime; positions
        // from before the step would be one frame behind, and with uneven frames (a short one after a long one) the
        // spin would come out several times too fast and fling particles. The step is the simulation's capped one, so
        // a long frame does not move colliders ahead of the particles either.
        switch runtime.state {
        case .playing:
            time += min(deltaTime, ParticleSystemRuntime.maximumStep) * max(runtime.speedFactor, 0)
        case .stopped:
            // Play after stop restarts the emitters; the clock starts over with them.
            time = 0
        default:
            break
        }
        let pointer = self.pointer
        runtime.forceFields = system.forceFields(at: time, pointer: pointer)
        runtime.trackedObjects = system.trackedObjectPositions(at: time)
        let colliders = system.colliders(at: time, pointer: pointer)
        let transforms = system.transforms(at: time, pointer: pointer)
        runtime.applyEventBursts(system.eventBursts)
        return try Group {
            try runtime.simulate(deltaTime: deltaTime, colliders: colliders, transforms: transforms, view: view)
            try runtime.renderScene(projection: projection, view: view, sceneDepth: sceneDepth, wireframes: wireframes)
        }
    }

    /// A scene depth texture of `size` pixels when the system draws its colliders, kept between frames. For callers of
    /// `frame(deltaTime:projection:view:sceneDepth:wireframes:)` that have no depth of their own.
    public func sceneDepth(size: CGSize) throws -> SceneDepth? {
        guard system.drawsColliders else {
            return nil
        }
        let width = Int(size.width)
        let height = Int(size.height)
        if let ownedSceneDepth, ownedSceneDepth.width == width, ownedSceneDepth.height == height {
            return ownedSceneDepth
        }
        ownedSceneDepth = try SceneDepth(device: runtime.device, width: width, height: height)
        return ownedSceneDepth
    }
}
