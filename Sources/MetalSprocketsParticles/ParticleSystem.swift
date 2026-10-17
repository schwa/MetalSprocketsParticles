import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

extension ColliderData {
    init(_ collider: Collider, velocity: SIMD3<Float> = .zero) {
        let velocity = SIMD4(velocity, 0)
        let identity: SIMD4<Float> = [0, 0, 0, 1]
        switch collider {
        case let .plane(normal, distance):
            self.init(kind: [1, 0, 0, 0], a: SIMD4(simd_normalize(normal), distance), b: .zero, velocity: velocity, rotation: identity)
        case let .sphere(center, radius):
            self.init(kind: [2, 0, 0, 0], a: SIMD4(center, radius), b: .zero, velocity: velocity, rotation: identity)
        case let .box(center, halfExtents, rotation):
            self.init(kind: [3, 0, 0, 0], a: SIMD4(center, 0), b: SIMD4(halfExtents, 0), velocity: velocity, rotation: simd_normalize(rotation).vector)
        case let .capsule(start, end, radius):
            self.init(kind: [4, 0, 0, 0], a: SIMD4(start, radius), b: SIMD4(end, 0), velocity: velocity, rotation: identity)
        }
    }
}

public enum Collider: Sendable, Equatable {
    case plane(normal: SIMD3<Float>, distance: Float)
    case sphere(center: SIMD3<Float>, radius: Float)
    case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    /// A line segment from `start` to `end` with rounded ends.
    case capsule(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float)
}

extension Collider {
    /// Linear velocity implied by moving from `previous` to `self` over `deltaTime`. Zero if the shape changed kind
    /// or orientation, or if no time passed. Rotation is not turned into velocity: spinning boxes do not fling particles.
    func velocity(from previous: Collider, deltaTime: Float) -> SIMD3<Float> {
        guard deltaTime > 0 else {
            return .zero
        }
        switch (previous, self) {
        case let (.plane(oldNormal, oldDistance), .plane(normal, distance)) where simd_normalize(oldNormal) == simd_normalize(normal):
            return simd_normalize(normal) * (distance - oldDistance) / deltaTime
        case let (.sphere(oldCenter, _), .sphere(center, _)):
            return (center - oldCenter) / deltaTime
        case let (.box(oldCenter, _, _), .box(center, _, _)):
            return (center - oldCenter) / deltaTime
        case let (.capsule(oldStart, oldEnd, _), .capsule(start, end, _)):
            return ((start + end) - (oldStart + oldEnd)) / 2 / deltaTime
        default:
            return .zero
        }
    }
}

public struct ParticleEmitter: Sendable, Equatable {
    public var position: SIMD3<Float> = .zero
    public var radius: Float = 0.05
    public var velocity: SIMD3<Float> = [0, 4, 0]
    public var velocitySpread: Float = 1.5
    public var lifetime: ClosedRange<Float> = 1.5...3
    /// Color by normalized age. Alpha is further multiplied by `opacityOverLife`.
    public var colorOverLife = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.7, 0.2, 1], to: [0.8, 0.1, 0.05, 0])
    /// Half-width of the quad in world units, by normalized age.
    public var sizeOverLife = ParticleCurve<Float>.linear(from: 0.04, to: 0.01)
    /// Multiplies color alpha by normalized age.
    public var opacityOverLife = ParticleCurve<Float>.constant(1)

    /// First keyframe of `colorOverLife`.
    public var colorStart: SIMD4<Float> {
        get { colorOverLife.start }
        set { colorOverLife.start = newValue }
    }
    /// Last keyframe of `colorOverLife`.
    public var colorEnd: SIMD4<Float> {
        get { colorOverLife.end }
        set { colorOverLife.end = newValue }
    }
    /// First keyframe of `sizeOverLife`.
    public var sizeStart: Float {
        get { sizeOverLife.start }
        set { sizeOverLife.start = newValue }
    }
    /// Last keyframe of `sizeOverLife`.
    public var sizeEnd: Float {
        get { sizeOverLife.end }
        set { sizeOverLife.end = newValue }
    }
    public var gravity: SIMD3<Float> = [0, -9.8, 0]
    public var drag: Float = 0.1
    public var restitution: Float = 0.4
    /// Per-particle offset range for `restitution`, picked at birth.
    public var restitutionVariation: Float = 0
    public var friction: Float = 0.2
    /// Per-particle offset range for `friction`, picked at birth.
    public var frictionVariation: Float = 0
    /// Per-particle offset range in m/s for initial speed, applied after `velocitySpread`.
    public var speedVariation: Float = 0
    /// Per-particle size multiplier range as a fraction: 0.25 scales `sizeOverLife` by 0.75...1.25.
    public var sizeVariation: Float = 0
    /// Per-particle offset ranges for hue (in turns, wraps), saturation, brightness, and alpha, applied to
    /// `colorOverLife`.
    public var colorVariation: SIMD4<Float> = .zero
    public var colliders: [Collider] = [.plane(normal: [0, 1, 0], distance: 0)]

    /// Initial rotation in radians, ± `angleVariation`.
    public var angle: Float = 0
    public var angleVariation: Float = 0
    /// Initial spin in radians per second, ± `angularSpeedVariation`.
    public var angularSpeed: Float = 0
    public var angularSpeedVariation: Float = 0

    public var blendMode: ParticleBlendMode = .alpha

    /// Treats `ParticleSystem.texture` as a grid of animation frames. Ignored without a texture.
    public var imageSequence: ImageSequence?

    public var forceFields: [ForceField] = []

    public var orientation: ParticleOrientation = .billboard

    /// Particles spawned per second while emitting. When the ring is full, the oldest particles are recycled.
    public var birthRate: Float = 1_000
    /// Offset range for `birthRate`, picked once per emission cycle (once overall when emission does not loop).
    public var birthRateVariation: Float = 0
    /// Fraction of the emitter's own velocity (from `ParticleSystem.transform` motion) given to newborn particles.
    /// World simulation space only.
    public var inheritVelocity: Float = 0
    /// Seconds of emission per cycle. `nil` emits forever.
    public var emissionDuration: Float?
    /// Seconds without emission after each emission period. Only used when `emissionDuration` is set.
    public var idleDuration: Float = 0
    /// Repeats the emission/idle cycle. When false, emission ends after the first `emissionDuration`.
    public var loops = true
    /// Seconds simulated before the first rendered frame, and again after `restart()`.
    public var warmupDuration: Float = 0

    public init() {}
}

public enum SimulationState: Sendable, Hashable {
    case playing
    /// Particles freeze in place. Queued bursts wait until playback resumes.
    case paused
    /// All particles are removed and nothing emits. Switching back to `.playing` restarts the emitter.
    case stopped
}

/// Owns GPU particle state. Simulation and rendering are separate elements so callers can place them in
/// their own passes.
public final class ParticleSystem {
    /// Particle colors, curves, and blending are linear. Render to an sRGB target so the GPU encodes them for display;
    /// a non-sRGB target shows linear values as if they were sRGB, which looks darker and more saturated.
    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    public let capacity: Int
    public var emitter: ParticleEmitter
    public let seed: UInt32
    let buffer: MTLBuffer
    let library: ShaderLibrary
    /// Premultiplied-alpha sprite, or a sprite sheet when `emitter.imageSequence` is set. `nil` draws a soft dot.
    public var texture: MTLTexture?
    public var device: MTLDevice { buffer.device }
    private let sampler: MTLSamplerState
    /// Bound in place of `texture` when there is none; the shader ignores it.
    private let placeholderTexture: MTLTexture
    private(set) var spawner: Spawner
    private var needsKill = false
    private var needsWarmup = true
    /// Colliders from the previous frame, used to derive collider velocity.
    private var previousColliders: [Collider]?

    public var state: SimulationState = .playing {
        didSet {
            if state == .stopped {
                needsKill = true
            } else if oldValue == .stopped {
                restart()
            }
        }
    }
    /// Turns emission off without affecting existing particles.
    public var isEmitting = true
    /// Emitter-to-world transform. Emitter position, velocity, and shape are in this space.
    public var transform = matrix_identity_float4x4
    public var simulationSpace: SimulationSpace = .world
    private var previousTransform: simd_float4x4?

    /// Simulation space to world: the emitter transform in local space, identity in world space.
    var modelTransform: simd_float4x4 {
        simulationSpace == .local ? transform : matrix_identity_float4x4
    }
    /// Multiplies simulation time. 2 runs twice as fast; 0.5 is slow motion.
    public var speedFactor: Float = 1

    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        self.capacity = capacity
        self.emitter = emitter
        self.seed = seed
        spawner = Spawner(seed: seed)
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

        // All particles start dead (lifetime 0).
        let length = MemoryLayout<Particle>.stride * capacity
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: length)
        buffer.label = "Particles"
        self.buffer = buffer
    }

    /// Colliders matched by index with last frame's get the velocity implied by their motion.
    private func colliderData(deltaTime: Float) -> [ColliderData] {
        let current = emitter.colliders
        defer { previousColliders = current }
        guard let previous = previousColliders, previous.count == current.count else {
            return current.map { ColliderData($0) }
        }
        return zip(previous, current).map { previous, collider in
            ColliderData(collider, velocity: collider.velocity(from: previous, deltaTime: deltaTime))
        }
    }

    /// Emits `count` particles on the next playing step, on top of the birth rate.
    public func burst(_ count: Int) {
        spawner.pendingBurst += max(count, 0)
    }

    /// Removes all particles, resets the emission clock, and runs warmup again.
    public func restart() {
        spawner = Spawner(seed: seed)
        needsKill = true
        needsWarmup = true
        if state != .playing {
            state = .playing
        }
    }

    /// Where the emitter is in simulation space for one step.
    private struct EmitterMotion {
        var transform = matrix_identity_float4x4
        var previousOrigin: SIMD3<Float> = .zero
        var inheritedVelocity: SIMD3<Float> = .zero

        static let still = EmitterMotion()
    }

    private func makeStep(deltaTime: Float, motion: EmitterMotion) -> SimulationUniforms {
        var uniforms = simulationUniforms
        uniforms.emitterTransform = motion.transform
        uniforms.previousEmitterOrigin = SIMD4(motion.previousOrigin, 0)
        uniforms.inheritedVelocity = SIMD4(motion.inheritedVelocity, 0)
        let playing = state == .playing
        let deltaTime = playing ? deltaTime : 0
        let spawn = playing
            ? spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: capacity, isEmitting: isEmitting)
            : Spawner.Step(cursor: spawner.cursor, count: 0, serial: spawner.serial)
        uniforms.lifetime.w = deltaTime
        // The emitter clock, not wall time, so turbulence stays deterministic.
        uniforms.fields.y = spawner.time
        uniforms.spawn = [spawn.cursor, spawn.count, spawn.serial, needsKill ? 1 : 0]
        needsKill = false
        return uniforms
    }

    var simulationUniforms: SimulationUniforms {
        SimulationUniforms(
            emitterTransform: matrix_identity_float4x4,
            previousEmitterOrigin: .zero,
            inheritedVelocity: .zero,
            emitterPosition: SIMD4(emitter.position, emitter.radius),
            emitterVelocity: SIMD4(emitter.velocity, emitter.velocitySpread),
            gravity: SIMD4(emitter.gravity, emitter.drag),
            lifetime: [emitter.lifetime.lowerBound, emitter.lifetime.upperBound, 0, 0],
            collision: [emitter.restitution, emitter.friction, Float(emitter.colliders.count), 0],
            rotation: [emitter.angle, emitter.angleVariation, emitter.angularSpeed, emitter.angularSpeedVariation],
            imageSequence: emitter.imageSequence.map {
                [$0.initialFrame, $0.initialFrameVariation, $0.frameRate, $0.frameRateVariation]
            } ?? .zero,
            fields: [Float(emitter.forceFields.count), 0, 0, 0],
            variation: [max(emitter.sizeVariation, 0), max(emitter.restitutionVariation, 0), max(emitter.frictionVariation, 0), max(emitter.speedVariation, 0)],
            colorVariation: simd_max(emitter.colorVariation, .zero),
            random: [seed, UInt32(capacity), 0, 0],
            spawn: .zero
        )
    }

    /// Advances the simulation one frame. Put this before the render pass that draws the particles.
    /// The result depends only on `seed`, emitter settings, playback calls, and the sequence of `deltaTime` values.
    /// Pass `colliders` to move them this frame; their velocity is derived from the change since the previous frame.
    public func simulate(deltaTime: Float, colliders: [Collider]? = nil) throws -> some Element {
        if let colliders {
            emitter.colliders = colliders
        }
        let frameDeltaTime = min(deltaTime, 1.0 / 30.0) * max(speedFactor, 0)
        // In local space the emitter is the origin of its own space and never moves.
        let spawnTransform = simulationSpace == .world ? transform : matrix_identity_float4x4
        let origin = spawnTransform.columns.3.xyz
        let previousOrigin = simulationSpace == .world ? (previousTransform?.columns.3.xyz ?? origin) : origin
        previousTransform = transform
        let emitterVelocity = frameDeltaTime > 0 ? (origin - previousOrigin) / frameDeltaTime : .zero
        let still = EmitterMotion(transform: spawnTransform, previousOrigin: origin)

        var steps: [SimulationUniforms] = []
        if needsWarmup {
            needsWarmup = false
            let warmupStep: Float = 1.0 / 60.0
            var remaining = emitter.warmupDuration
            while remaining > 0 {
                steps.append(makeStep(deltaTime: min(warmupStep, remaining), motion: still))
                remaining -= warmupStep
            }
        }
        steps.append(makeStep(deltaTime: frameDeltaTime, motion: EmitterMotion(
            transform: spawnTransform,
            previousOrigin: previousOrigin,
            inheritedVelocity: emitterVelocity * emitter.inheritVelocity
        )))

        let colliders = colliderData(deltaTime: steps.last?.lifetime.w ?? 0)
        let forceFields = emitter.forceFields.map(ForceFieldData.init)
        let kernel = try library.updateParticles as ComputeKernel
        let buffer = buffer
        let capacity = capacity
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            ForEach(Array(steps.indices), id: \.self) { index in
                if index > 0 {
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                }
                try ComputePipeline(computeKernel: kernel) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: capacity, height: 1, depth: 1))
                }
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: steps[index])
                // Never bind an empty array; the count in uniforms keeps the padding unused.
                .parameter("colliders", values: colliders.isEmpty ? [ColliderData(.plane(normal: [0, 1, 0], distance: 0))] : colliders)
                .parameter("forceFields", values: forceFields.isEmpty ? [ForceFieldData(.wind(velocity: .zero, strength: 0))] : forceFields)
            }
        }
        .barrierAfterPass(after: .dispatch, beforeQueueStages: .vertex)
        .gpuTimed("Simulate")
    }

    /// Draws the particles as camera-facing billboards. Place inside a `RenderPass`.
    public func render(projection: simd_float4x4, view: simd_float4x4) throws -> some Element {
        let sequence = texture == nil ? ImageSequence() : emitter.imageSequence ?? ImageSequence()
        let opacity = emitter.opacityOverLife.baked()
        let colorCurve = zip(emitter.colorOverLife.baked(), opacity).map { color, opacity in
            SIMD4(color.x, color.y, color.z, color.w * opacity)
        }
        let cameraToWorld = view.inverse
        let uniforms = RenderUniforms(
            viewProjection: projection * view,
            model: modelTransform,
            cameraRight: SIMD4(simd_normalize(cameraToWorld.columns.0.xyz), 0),
            cameraUp: SIMD4(simd_normalize(cameraToWorld.columns.1.xyz), 0),
            options: [
                emitter.blendMode.rawValue,
                texture == nil ? 0 : 1,
                UInt32(max(sequence.columns, 1)),
                UInt32(max(sequence.rows, 1)),
            ],
            imageSequence: [UInt32(max(sequence.frameCount, 1)), sequence.mode.rawValue, 0, 0],
            cameraPosition: SIMD4(cameraToWorld.columns.3.xyz, 1),
            orientation: emitter.orientation.parameters,
            orientationMode: [emitter.orientation.mode.rawValue, 0, 0, 0]
        )
        let capacity = capacity
        let blendMode = emitter.blendMode
        return try RenderPipeline(vertexShader: library.particleVertex, fragmentShader: library.particleFragment) {
            Draw { encoder in
                encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: capacity)
            }
        }
        .parameter("particles", buffer: buffer)
        .parameter("uniforms", value: uniforms)
        .parameter("colorCurve", values: colorCurve)
        .parameter("sizeCurve", values: emitter.sizeOverLife.baked())
        .parameter("sprite", texture: texture ?? placeholderTexture)
        .parameter("spriteSampler", samplerState: sampler)
        .renderPipelineDescriptorTransformer { descriptor in
            blendMode.configure(descriptor.colorAttachments[0]!)
        }
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
