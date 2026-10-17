import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

extension ColliderData {
    init(_ collider: Collider) {
        switch collider {
        case let .plane(normal, distance):
            self.init(kind: [1, 0, 0, 0], a: SIMD4(simd_normalize(normal), distance), b: .zero)
        case let .sphere(center, radius):
            self.init(kind: [2, 0, 0, 0], a: SIMD4(center, radius), b: .zero)
        case let .box(center, halfExtents):
            self.init(kind: [3, 0, 0, 0], a: SIMD4(center, 0), b: SIMD4(halfExtents, 0))
        }
    }
}

public enum Collider: Sendable, Equatable {
    case plane(normal: SIMD3<Float>, distance: Float)
    case sphere(center: SIMD3<Float>, radius: Float)
    case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>)
}

public struct ParticleEmitter: Sendable, Equatable {
    public var position: SIMD3<Float> = .zero
    public var radius: Float = 0.05
    public var velocity: SIMD3<Float> = [0, 4, 0]
    public var velocitySpread: Float = 1.5
    public var lifetime: ClosedRange<Float> = 1.5...3
    public var colorStart: SIMD4<Float> = [1, 0.7, 0.2, 1]
    public var colorEnd: SIMD4<Float> = [0.8, 0.1, 0.05, 0]
    public var sizeStart: Float = 0.04
    public var sizeEnd: Float = 0.01
    public var gravity: SIMD3<Float> = [0, -9.8, 0]
    public var drag: Float = 0.1
    public var restitution: Float = 0.4
    public var friction: Float = 0.2
    public var colliders: [Collider] = [.plane(normal: [0, 1, 0], distance: 0)]

    /// Initial rotation in radians, ± `angleVariation`.
    public var angle: Float = 0
    public var angleVariation: Float = 0
    /// Initial spin in radians per second, ± `angularSpeedVariation`.
    public var angularSpeed: Float = 0
    public var angularSpeedVariation: Float = 0

    /// Particles spawned per second while emitting. When the ring is full, the oldest particles are recycled.
    public var birthRate: Float = 1_000
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

public enum SimulationState: Sendable, Equatable {
    case playing
    /// Particles freeze in place. Queued bursts wait until playback resumes.
    case paused
    /// All particles are removed and nothing emits. Switching back to `.playing` restarts the emitter.
    case stopped
}

/// Owns GPU particle state. Simulation and rendering are separate elements so callers can place them in
/// their own passes.
public final class ParticleSystem {
    public let capacity: Int
    public var emitter: ParticleEmitter
    public let seed: UInt32
    let buffer: MTLBuffer
    let library: ShaderLibrary
    private(set) var spawner = Spawner()
    private var needsKill = false
    private var needsWarmup = true

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
    /// Multiplies simulation time. 2 runs twice as fast; 0.5 is slow motion.
    public var speedFactor: Float = 1

    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        self.capacity = capacity
        self.emitter = emitter
        self.seed = seed
        library = try ShaderLibrary(bundle: .metalSprocketsParticlesShaders(), device: device)

        // All particles start dead (lifetime 0).
        let length = MemoryLayout<Particle>.stride * capacity
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: length)
        buffer.label = "Particles"
        self.buffer = buffer
    }

    /// Emits `count` particles on the next playing step, on top of the birth rate.
    public func burst(_ count: Int) {
        spawner.pendingBurst += max(count, 0)
    }

    /// Removes all particles, resets the emission clock, and runs warmup again.
    public func restart() {
        spawner = Spawner()
        needsKill = true
        needsWarmup = true
        if state != .playing {
            state = .playing
        }
    }

    private func makeStep(deltaTime: Float) -> SimulationUniforms {
        var uniforms = simulationUniforms
        let playing = state == .playing
        let deltaTime = playing ? deltaTime : 0
        let spawn = playing
            ? spawner.advance(deltaTime: deltaTime, emitter: emitter, capacity: capacity, isEmitting: isEmitting)
            : Spawner.Step(cursor: spawner.cursor, count: 0, serial: spawner.serial)
        uniforms.lifetime.w = deltaTime
        uniforms.spawn = [spawn.cursor, spawn.count, spawn.serial, needsKill ? 1 : 0]
        needsKill = false
        return uniforms
    }

    var simulationUniforms: SimulationUniforms {
        SimulationUniforms(
            emitterPosition: SIMD4(emitter.position, emitter.radius),
            emitterVelocity: SIMD4(emitter.velocity, emitter.velocitySpread),
            gravity: SIMD4(emitter.gravity, emitter.drag),
            lifetime: [emitter.lifetime.lowerBound, emitter.lifetime.upperBound, 0, 0],
            colorStart: emitter.colorStart,
            colorEnd: emitter.colorEnd,
            collision: [emitter.restitution, emitter.friction, Float(emitter.colliders.count), 0],
            rotation: [emitter.angle, emitter.angleVariation, emitter.angularSpeed, emitter.angularSpeedVariation],
            random: [seed, UInt32(capacity), 0, 0],
            spawn: .zero
        )
    }

    /// Advances the simulation one frame. Put this before the render pass that draws the particles.
    /// The result depends only on `seed`, emitter settings, playback calls, and the sequence of `deltaTime` values.
    public func simulate(deltaTime: Float) throws -> some Element {
        var steps: [SimulationUniforms] = []
        if needsWarmup {
            needsWarmup = false
            let warmupStep: Float = 1.0 / 60.0
            var remaining = emitter.warmupDuration
            while remaining > 0 {
                steps.append(makeStep(deltaTime: min(warmupStep, remaining)))
                remaining -= warmupStep
            }
        }
        steps.append(makeStep(deltaTime: min(deltaTime, 1.0 / 30.0) * max(speedFactor, 0)))

        let colliders = emitter.colliders.map(ColliderData.init)
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
            }
        }
        .barrierAfterPass(after: .dispatch, beforeQueueStages: .vertex)
        .gpuTimed("Simulate")
    }

    /// Draws the particles as camera-facing billboards. Place inside a `RenderPass`.
    public func render(projection: simd_float4x4, view: simd_float4x4) throws -> some Element {
        let cameraToWorld = view.inverse
        let uniforms = RenderUniforms(
            viewProjection: projection * view,
            cameraRight: SIMD4(simd_normalize(cameraToWorld.columns.0.xyz), 0),
            cameraUp: SIMD4(simd_normalize(cameraToWorld.columns.1.xyz), 0),
            size: [emitter.sizeStart, emitter.sizeEnd, 0, 0]
        )
        let capacity = capacity
        return try RenderPipeline(vertexShader: library.particleVertex, fragmentShader: library.particleFragment) {
            Draw { encoder in
                encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: capacity)
            }
        }
        .parameter("particles", buffer: buffer)
        .parameter("uniforms", value: uniforms)
        .renderPipelineDescriptorTransformer { descriptor in
            let attachment = descriptor.colorAttachments[0]!
            attachment.blendingState = .enabled
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}
