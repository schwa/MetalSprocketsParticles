import Foundation
import Metal
import MetalSprockets
import simd

// Layouts must match Particles.metal.
struct Particle {
    var position: SIMD4<Float>
    var velocity: SIMD4<Float>
    var color: SIMD4<Float>
}

struct SimulationUniforms {
    var emitterPosition: SIMD4<Float>
    var emitterVelocity: SIMD4<Float>
    var gravity: SIMD4<Float>
    var lifetime: SIMD4<Float>
    var colorStart: SIMD4<Float>
    var colorEnd: SIMD4<Float>
    var collision: SIMD4<Float>
    var random: SIMD4<UInt32>
}

struct ColliderData {
    var kind: SIMD4<Float>
    var a: SIMD4<Float>
    var b: SIMD4<Float>

    init(_ collider: Collider) {
        switch collider {
        case let .plane(normal, distance):
            kind = [1, 0, 0, 0]; a = SIMD4(simd_normalize(normal), distance); b = .zero
        case let .sphere(center, radius):
            kind = [2, 0, 0, 0]; a = SIMD4(center, radius); b = .zero
        case let .box(center, halfExtents):
            kind = [3, 0, 0, 0]; a = SIMD4(center, 0); b = SIMD4(halfExtents, 0)
        }
    }
}

struct RenderUniforms {
    var viewProjection: simd_float4x4
    var cameraRight: SIMD4<Float>
    var cameraUp: SIMD4<Float>
    var size: SIMD4<Float>
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

    public init() {}
}

/// Owns GPU particle state. Simulation and rendering are separate elements so callers can place them in
/// their own passes.
public final class ParticleSystem {
    public let capacity: Int
    public var emitter: ParticleEmitter
    public let seed: UInt32
    let buffer: MTLBuffer
    let library: ShaderLibrary
    /// Number of simulation steps run so far. Drives the GPU random sequence together with `seed`.
    private(set) var step: UInt32 = 0

    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        self.capacity = capacity
        self.emitter = emitter
        self.seed = seed
        guard let url = Bundle.module.url(forResource: "Particles", withExtension: "metal") else {
            throw CocoaError(.fileNoSuchFile)
        }
        library = try ShaderLibrary(source: String(contentsOf: url, encoding: .utf8), device: device)

        // Stagger first spawn across the max lifetime so emission is continuous from the start.
        let maxLifetime = emitter.lifetime.upperBound
        var generator = SplitMix64(seed: UInt64(seed))
        let particles = (0..<capacity).map { _ in
            Particle(position: [0, 0, 0, -Float.random(in: 0...maxLifetime, using: &generator)], velocity: .zero, color: .zero)
        }
        guard let buffer = particles.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.label = "Particles"
        self.buffer = buffer
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
            random: [seed, 0, 0, 0]
        )
    }

    /// Advances the simulation one step. Put this before the render pass that draws the particles.
    /// The result depends only on `seed`, emitter settings, and the sequence of `deltaTime` values.
    public func simulate(deltaTime: Float) throws -> some Element {
        var uniforms = simulationUniforms
        uniforms.random.y = step
        step &+= 1
        uniforms.lifetime.w = min(deltaTime, 1.0 / 30.0)
        let colliders = emitter.colliders.map(ColliderData.init)
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            try ComputePipeline(computeKernel: library.updateParticles) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: capacity, height: 1, depth: 1))
            }
            .parameter("particles", buffer: buffer)
            .parameter("uniforms", value: uniforms)
            // Never bind an empty array; the count in uniforms keeps the padding unused.
            .parameter("colliders", values: colliders.isEmpty ? [ColliderData(.plane(normal: [0, 1, 0], distance: 0))] : colliders)
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

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}
