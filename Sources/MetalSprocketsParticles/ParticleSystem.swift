import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

public enum SimulationState: Sendable, Hashable {
    case playing
    /// Particles freeze in place. Queued bursts wait until playback resumes.
    case paused
    /// All particles are removed and nothing emits. Switching back to `.playing` restarts every emitter.
    case stopped
}

/// Owns GPU particle state for any number of emitters. All emitters share one particle buffer, one simulation pass,
/// and one world of colliders and force fields. Each emitter owns a fixed slice of the buffer and draws with its own
/// blend mode and texture. Simulation and rendering are separate elements so callers can place them in their own
/// passes.
public final class ParticleSystem {
    /// Particle colors, curves, and blending are linear. Render to an sRGB target so the GPU encodes them for display;
    /// a non-sRGB target shows linear values as if they were sRGB, which looks darker and more saturated.
    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// One emitter in a system: its settings plus the runtime state that does not belong in a value type.
    public final class Emitter {
        public var settings: ParticleEmitter
        /// Premultiplied-alpha sprite, or a sprite sheet when `settings.imageSequence` is set. `nil` draws a soft dot.
        public var texture: MTLTexture?
        /// Emitter-to-world transform. Emitter position, velocity, and shape are in this space.
        public var transform = matrix_identity_float4x4
        public var simulationSpace: SimulationSpace = .world
        /// Turns emission off without affecting existing particles.
        public var isEmitting = true
        /// Triangles for `EmitterShape.mesh`.
        public var mesh: EmitterMesh?
        /// Particles this emitter can have alive at once.
        public let capacity: Int
        /// This emitter's slice of the shared particle buffer.
        public internal(set) var range: Range<Int>

        let seed: UInt32
        var spawner: Spawner
        var needsKill = false
        var needsWarmup = true
        var previousTransform: simd_float4x4?

        init(settings: ParticleEmitter, capacity: Int, range: Range<Int>, seed: UInt32) {
            self.settings = settings
            self.capacity = capacity
            self.range = range
            self.seed = seed
            spawner = Spawner(seed: seed)
        }

        /// Emits `count` particles on the next playing step, on top of the birth rate.
        public func burst(_ count: Int) {
            spawner.pendingBurst += max(count, 0)
        }

        /// Removes this emitter's particles, resets its emission clock, and runs its warmup again.
        public func restart() {
            spawner = Spawner(seed: seed)
            needsKill = true
            needsWarmup = true
        }

        /// Simulation space to world: the transform in local space, identity in world space.
        var modelTransform: simd_float4x4 {
            simulationSpace == .local ? transform : matrix_identity_float4x4
        }
    }

    public let seed: UInt32
    public private(set) var emitters: [Emitter] = []
    /// World-space colliders shared by every emitter. Update them per frame to move them; their velocity is derived
    /// from the change since the previous frame.
    public var colliders: [Collider] = []
    /// World-space force fields shared by every emitter.
    public var forceFields: [ForceField] = []
    /// Multiplies simulation time. 2 runs twice as fast; 0.5 is slow motion.
    public var speedFactor: Float = 1

    public var state: SimulationState = .playing {
        didSet {
            if state == .stopped {
                emitters.forEach { $0.needsKill = true }
            } else if oldValue == .stopped {
                emitters.forEach { $0.restart() }
            }
        }
    }

    public let device: MTLDevice
    private(set) var buffer: MTLBuffer
    let library: ShaderLibrary
    private let sampler: MTLSamplerState
    /// Bound in place of a missing texture; the shader ignores it.
    private let placeholderTexture: MTLTexture
    /// Bound in place of a missing emitter mesh; the counts in uniforms keep it unused.
    private let placeholderMesh: EmitterMesh
    /// Colliders from the previous frame, used to derive collider velocity.
    private var previousColliders: [Collider]?

    /// Total particles across all emitters.
    public var capacity: Int {
        emitters.reduce(0) { $0 + $1.capacity }
    }

    /// Creates a system with one emitter per entry in `emitters`, each with room for `capacity` particles.
    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, emitters: [ParticleEmitter], capacity: Int, seed: UInt32 = 0) throws {
        self.device = device
        self.seed = seed
        library = try ShaderLibrary(bundle: .metalSprocketsParticlesShaders(), device: device)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        self.sampler = sampler
        let placeholderDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholderTexture = device.makeTexture(descriptor: placeholderDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        placeholderTexture.label = "Particle placeholder texture"
        self.placeholderTexture = placeholderTexture
        placeholderMesh = try EmitterMesh(device: device, positions: [], indices: [])
        buffer = try Self.makeBuffer(device: device, count: 1)

        try setEmitters(emitters.map { ($0, capacity) })
    }

    /// Creates a system with a single emitter.
    public convenience init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: [emitter], capacity: capacity, seed: seed)
    }

    private static func makeBuffer(device: MTLDevice, count: Int) throws -> MTLBuffer {
        // All particles start dead (lifetime 0).
        let length = MemoryLayout<Particle>.stride * max(count, 1)
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: length)
        buffer.label = "Particles"
        return buffer
    }

    /// Emitter `index` uses the system seed offset by its index, so emitter 0 matches a single-emitter system.
    private func emitterSeed(_ index: Int) -> UInt32 {
        seed &+ UInt32(truncatingIfNeeded: index) &* 0x9E37_79B9
    }

    /// Replaces every emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    public func setEmitters(_ emitters: [(settings: ParticleEmitter, capacity: Int)]) throws -> [Emitter] {
        var start = 0
        var created: [Emitter] = []
        for (index, entry) in emitters.enumerated() {
            let capacity = max(entry.capacity, 1)
            created.append(Emitter(settings: entry.settings, capacity: capacity, range: start..<(start + capacity), seed: emitterSeed(index)))
            start += capacity
        }
        buffer = try Self.makeBuffer(device: device, count: start)
        self.emitters = created
        return created
    }

    /// Adds an emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    public func addEmitter(_ settings: ParticleEmitter, capacity: Int) throws -> Emitter {
        let existing = emitters
        try setEmitters(existing.map { ($0.settings, $0.capacity) } + [(settings, capacity)])
        // Keep runtime state that is not part of the settings.
        for (old, new) in zip(existing, emitters) {
            new.texture = old.texture
            new.transform = old.transform
            new.simulationSpace = old.simulationSpace
            new.isEmitting = old.isEmitting
        }
        return emitters[emitters.count - 1]
    }

    /// Removes all particles from every emitter, resets their clocks, and runs warmup again.
    public func restart() {
        emitters.forEach { $0.restart() }
        if state != .playing {
            state = .playing
        }
    }

    // MARK: Single-emitter conveniences. These act on the first emitter.

    public var emitter: ParticleEmitter {
        get { emitters[0].settings }
        set { emitters[0].settings = newValue }
    }

    public var texture: MTLTexture? {
        get { emitters[0].texture }
        set { emitters[0].texture = newValue }
    }

    public var transform: simd_float4x4 {
        get { emitters[0].transform }
        set { emitters[0].transform = newValue }
    }

    public var simulationSpace: SimulationSpace {
        get { emitters[0].simulationSpace }
        set { emitters[0].simulationSpace = newValue }
    }

    public var isEmitting: Bool {
        get { emitters[0].isEmitting }
        set { emitters[0].isEmitting = newValue }
    }

    public func burst(_ count: Int) {
        emitters.first?.burst(count)
    }

    // MARK: Simulation

    /// Colliders matched by index with last frame's get the velocity implied by their motion.
    private func colliderData(deltaTime: Float) -> [ColliderData] {
        let current = colliders
        defer { previousColliders = current }
        guard let previous = previousColliders, previous.count == current.count else {
            return current.map { ColliderData($0) }
        }
        return zip(previous, current).map { previous, collider in
            ColliderData(collider, velocity: collider.velocity(from: previous, deltaTime: deltaTime))
        }
    }

    /// Where an emitter is in simulation space for one step.
    private struct EmitterMotion {
        var transform = matrix_identity_float4x4
        var previousOrigin: SIMD3<Float> = .zero
        var inheritedVelocity: SIMD3<Float> = .zero
    }

    /// One compute dispatch: an emitter's slice for one step.
    private struct Dispatch {
        var uniforms: SimulationUniforms
        var capacity: Int
        var mesh: EmitterMesh?
        /// The previous dispatch wrote the same slice.
        var followsSameEmitter: Bool
    }

    private func makeStep(_ emitter: Emitter, deltaTime: Float, motion: EmitterMotion) -> SimulationUniforms {
        let settings = emitter.settings
        let playing = state == .playing
        let deltaTime = playing ? deltaTime : 0
        let spawn = playing
            ? emitter.spawner.advance(deltaTime: deltaTime, emitter: settings, capacity: emitter.capacity, isEmitting: emitter.isEmitting)
            : Spawner.Step(cursor: emitter.spawner.cursor, count: 0, serial: emitter.spawner.serial)
        let model = emitter.modelTransform
        let uniforms = SimulationUniforms(
            emitterTransform: motion.transform,
            simulationToWorld: model,
            worldToSimulation: model.inverse,
            previousEmitterOrigin: SIMD4(motion.previousOrigin, 0),
            inheritedVelocity: SIMD4(motion.inheritedVelocity, 0),
            emitterPosition: SIMD4(settings.position, 0),
            shape: [settings.shape.kind.rawValue, settings.birthLocation.rawValue, settings.birthDirection.rawValue, 0],
            shapeParameters: {
                var parameters = settings.shape.parameters
                parameters.w = max(settings.sweepAngle, 0)
                return parameters
            }(),
            meshCounts: settings.shape == .mesh ? [UInt32(emitter.mesh?.triangleCount ?? 0), UInt32(emitter.mesh?.vertexCount ?? 0), 0, 0] : .zero,
            emitterVelocity: SIMD4(settings.velocity, settings.velocitySpread),
            gravity: SIMD4(settings.gravity, settings.drag),
            lifetime: [settings.lifetime.lowerBound, settings.lifetime.upperBound, 0, deltaTime],
            collision: [settings.restitution, settings.friction, Float(colliders.count), settings.diesOnCollision ? 1 : 0],
            rotation: [settings.angle, settings.angleVariation, settings.angularSpeed, settings.angularSpeedVariation],
            imageSequence: settings.imageSequence.map {
                [$0.initialFrame, $0.initialFrameVariation, $0.frameRate, $0.frameRateVariation]
            } ?? .zero,
            // The emitter clock, not wall time, so turbulence stays deterministic.
            fields: [Float(forceFields.count), emitter.spawner.time, 0, 0],
            variation: [max(settings.sizeVariation, 0), max(settings.restitutionVariation, 0), max(settings.frictionVariation, 0), max(settings.speedVariation, 0)],
            colorVariation: simd_max(settings.colorVariation, .zero),
            random: [emitter.seed, UInt32(emitter.capacity), UInt32(emitter.range.lowerBound), 0],
            spawn: [spawn.cursor, spawn.count, spawn.serial, emitter.needsKill ? 1 : 0]
        )
        emitter.needsKill = false
        return uniforms
    }

    private func dispatches(_ emitter: Emitter, frameDeltaTime: Float) -> [Dispatch] {
        // In local space the emitter is the origin of its own space and never moves.
        let spawnTransform = emitter.simulationSpace == .world ? emitter.transform : matrix_identity_float4x4
        let origin = spawnTransform.columns.3.xyz
        let previousOrigin = emitter.simulationSpace == .world ? (emitter.previousTransform?.columns.3.xyz ?? origin) : origin
        emitter.previousTransform = emitter.transform
        let emitterVelocity = frameDeltaTime > 0 ? (origin - previousOrigin) / frameDeltaTime : .zero

        var steps: [SimulationUniforms] = []
        if emitter.needsWarmup {
            emitter.needsWarmup = false
            let still = EmitterMotion(transform: spawnTransform, previousOrigin: origin)
            let warmupStep: Float = 1.0 / 60.0
            var remaining = emitter.settings.warmupDuration
            while remaining > 0 {
                steps.append(makeStep(emitter, deltaTime: min(warmupStep, remaining), motion: still))
                remaining -= warmupStep
            }
        }
        steps.append(makeStep(emitter, deltaTime: frameDeltaTime, motion: EmitterMotion(
            transform: spawnTransform,
            previousOrigin: previousOrigin,
            inheritedVelocity: emitterVelocity * emitter.settings.inheritVelocity
        )))
        return steps.enumerated().map { index, uniforms in
            Dispatch(uniforms: uniforms, capacity: emitter.capacity, mesh: emitter.mesh, followsSameEmitter: index > 0)
        }
    }

    /// Advances every emitter one frame in a single compute pass. Put this before the render pass that draws the
    /// particles. The result depends only on `seed`, settings, playback calls, and the sequence of `deltaTime` values.
    /// Pass `colliders` to replace `self.colliders` this frame.
    public func simulate(deltaTime: Float, colliders: [Collider]? = nil) throws -> some Element {
        if let colliders {
            self.colliders = colliders
        }
        let frameDeltaTime = min(deltaTime, 1.0 / 30.0) * max(speedFactor, 0)
        let dispatches = emitters.flatMap { dispatches($0, frameDeltaTime: frameDeltaTime) }
        let colliderData = colliderData(deltaTime: state == .playing ? frameDeltaTime : 0)
        let forceFieldData = forceFields.map(ForceFieldData.init)
        let placeholderMesh = placeholderMesh
        let kernel = try library.updateParticles as ComputeKernel
        let buffer = buffer
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            ForEach(Array(dispatches.indices), id: \.self) { index in
                // Slices are disjoint, so only consecutive steps of one emitter depend on each other.
                if dispatches[index].followsSameEmitter {
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                }
                try ComputePipeline(computeKernel: kernel) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: dispatches[index].capacity, height: 1, depth: 1))
                }
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: dispatches[index].uniforms)
                // Never bind an empty array; the counts in uniforms keep the padding unused.
                .parameter("colliders", values: colliderData.isEmpty ? [ColliderData(.plane(normal: [0, 1, 0], distance: 0))] : colliderData)
                .parameter("forceFields", values: forceFieldData.isEmpty ? [ForceFieldData(.wind(velocity: .zero, strength: 0))] : forceFieldData)
                .parameter("meshTriangles", buffer: (dispatches[index].mesh ?? placeholderMesh).triangles)
                .parameter("meshVertices", buffer: (dispatches[index].mesh ?? placeholderMesh).vertices)
            }
        }
        .barrierAfterPass(after: .dispatch, beforeQueueStages: .vertex)
        .gpuTimed("Simulate")
    }

    // MARK: Rendering

    /// Draws every emitter's particles, in emitter order. Place inside a `RenderPass`.
    public func render(projection: simd_float4x4, view: simd_float4x4) throws -> some Element {
        let cameraToWorld = view.inverse
        let draws = emitters.map { emitter in
            EmitterDraw(emitter: emitter, viewProjection: projection * view, cameraToWorld: cameraToWorld)
        }
        let buffer = buffer
        let vertexShader = try library.particleVertex as VertexShader
        let fragmentShader = try library.particleFragment as FragmentShader
        let placeholderTexture = placeholderTexture
        let sampler = sampler
        return ForEach(Array(draws.indices), id: \.self) { index in
            let draw = draws[index]
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: draw.capacity, baseInstance: draw.baseInstance)
                }
            }
            .parameter("particles", buffer: buffer)
            .parameter("uniforms", value: draw.uniforms)
            .parameter("colorCurve", values: draw.colorCurve)
            .parameter("sizeCurve", values: draw.sizeCurve)
            .parameter("sprite", texture: draw.texture ?? placeholderTexture)
            .parameter("spriteSampler", samplerState: sampler)
            .renderPipelineDescriptorTransformer { descriptor in
                draw.blendMode.configure(descriptor.colorAttachments[0]!)
            }
        }
    }
}

/// Everything one emitter's draw needs, captured when the render element is built.
private struct EmitterDraw {
    var uniforms: RenderUniforms
    var colorCurve: [SIMD4<Float>]
    var sizeCurve: [Float]
    var texture: MTLTexture?
    var blendMode: ParticleBlendMode
    var capacity: Int
    var baseInstance: Int

    init(emitter: ParticleSystem.Emitter, viewProjection: simd_float4x4, cameraToWorld: simd_float4x4) {
        let settings = emitter.settings
        let sequence = emitter.texture == nil ? ImageSequence() : settings.imageSequence ?? ImageSequence()
        let opacity = settings.opacityOverLife.baked()
        colorCurve = zip(settings.colorOverLife.baked(), opacity).map { color, opacity in
            SIMD4(color.x, color.y, color.z, color.w * opacity)
        }
        sizeCurve = settings.sizeOverLife.baked()
        texture = emitter.texture
        blendMode = settings.blendMode
        capacity = emitter.capacity
        baseInstance = emitter.range.lowerBound
        uniforms = RenderUniforms(
            viewProjection: viewProjection,
            model: emitter.modelTransform,
            cameraRight: SIMD4(simd_normalize(cameraToWorld.columns.0.xyz), 0),
            cameraUp: SIMD4(simd_normalize(cameraToWorld.columns.1.xyz), 0),
            options: [
                settings.blendMode.rawValue,
                emitter.texture == nil ? 0 : 1,
                UInt32(max(sequence.columns, 1)),
                UInt32(max(sequence.rows, 1)),
            ],
            imageSequence: [UInt32(max(sequence.frameCount, 1)), sequence.mode.rawValue, 0, 0],
            cameraPosition: SIMD4(cameraToWorld.columns.3.xyz, 1),
            orientation: settings.orientation.parameters,
            orientationMode: [settings.orientation.mode.rawValue, 0, 0, 0]
        )
    }
}

extension ParticleBlendMode {
    // The fragment shader outputs premultiplied color, so every blended mode uses `.one` for the source.
    func configure(_ attachment: MTL4RenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.blendingState = .disabled
            return
        case .additive:
            attachment.destinationRGBBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        case .screen:
            attachment.destinationRGBBlendFactor = .oneMinusSourceColor
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        default:
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        attachment.blendingState = .enabled
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}
