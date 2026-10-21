import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

/// Boids for one emitter's particles (`FlockingModule`): each steers away from neighbors that are too close
/// (separation), toward their average velocity (alignment), and toward their center (cohesion), counting neighbors
/// within `radius`. A spatial hash grid of the emitter's particles is built on the GPU each frame, so the cost grows
/// with the particle count, not its square.
public struct ParticleFlocking: Sendable, Equatable, Codable {
    /// How far a particle sees its neighbors. Also the grid cell size: smaller is faster.
    public var radius: Float
    /// Closer than this, neighbors push apart.
    public var separationRadius: Float
    public var separation: Float
    public var alignment: Float
    public var cohesion: Float
    /// Speed is kept in this range after steering.
    public var speedRange: ClosedRange<Float>
    /// Neighbors counted per particle, to bound the cost in dense crowds.
    public var maxNeighbors: Int

    public init(
        radius: Float = 0.5,
        separationRadius: Float = 0.15,
        separation: Float = 0.02,
        alignment: Float = 1.5,
        cohesion: Float = 1,
        speedRange: ClosedRange<Float> = 0.5...2,
        maxNeighbors: Int = 32
    ) {
        self.radius = radius
        self.separationRadius = separationRadius
        self.separation = separation
        self.alignment = alignment
        self.cohesion = cohesion
        self.speedRange = speedRange
        self.maxNeighbors = maxNeighbors
    }
}

/// GPU buffers for flocking, sized for the largest flocking emitter, made when one first appears.
final class FlockingBuffers {
    let cellCounts: MTLBuffer
    let cellStarts: MTLBuffer
    let particleCells: MTLBuffer
    /// Each cell's particles in the order the scatter put them; `sortedOffsets` holds them in slot order.
    let scatteredOffsets: MTLBuffer
    let sortedOffsets: MTLBuffer
    /// Steering for every particle in the system, indexed like the particle buffer.
    let steering: MTLBuffer
    let capacity: Int
    let particleCount: Int

    init(device: MTLDevice, capacity: Int, particleCount: Int) throws {
        func make(_ length: Int, _ label: String) throws -> MTLBuffer {
            guard let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
                throw ParticleSystemRuntimeError.tooManyParticles
            }
            buffer.label = label
            return buffer
        }
        let table = Int(PARTICLE_FLOCK_TABLE_SIZE) * MemoryLayout<UInt32>.stride
        cellCounts = try make(table, "Flock cell counts")
        cellStarts = try make(table, "Flock cell starts")
        particleCells = try make(capacity * MemoryLayout<UInt32>.stride, "Flock particle cells")
        scatteredOffsets = try make(capacity * MemoryLayout<UInt32>.stride, "Flock scattered particles")
        sortedOffsets = try make(capacity * MemoryLayout<UInt32>.stride, "Flock sorted particles")
        steering = try make(particleCount * MemoryLayout<SIMD4<Float>>.stride, "Flock steering")
        self.capacity = capacity
        self.particleCount = particleCount
    }
}

extension ParticleSystemRuntime {
    /// The flocking passes for this frame, and buffers big enough for them.
    func planFlocking() throws -> [FlockData] {
        var flocks: [FlockData] = []
        for emitter in allEmitters {
            guard let flocking = emitter.resolved.flocking else {
                continue
            }
            let window = emitter.liveWindow
            flocks.append(FlockData(
                sliceStart: UInt32(emitter.range.lowerBound),
                capacity: UInt32(emitter.capacity),
                windowStart: UInt32(window.start),
                windowCount: UInt32(window.count),
                radius: max(flocking.radius, 1e-3),
                separationRadius: max(flocking.separationRadius, 0),
                separation: flocking.separation,
                alignment: flocking.alignment,
                cohesion: flocking.cohesion,
                maxNeighbors: UInt32(max(flocking.maxNeighbors, 0))
            ))
        }
        guard !flocks.isEmpty else {
            return []
        }
        let capacity = allEmitters.filter { $0.resolved.flocking != nil }.map(\.capacity).max() ?? 1
        let particleCount = buffer.length / MemoryLayout<Particle>.stride
        if flockingBuffers.map({ $0.capacity < capacity || $0.particleCount != particleCount }) ?? true {
            flockingBuffers = try FlockingBuffers(device: device, capacity: capacity, particleCount: particleCount)
        }
        return flocks
    }

    /// Builds each flocking emitter's grid and writes its steering, one emitter after another.
    func flockingPasses(_ flocks: [FlockData], buffers: FlockingBuffers, particles: MTLBuffer) throws -> some Element {
        let clear = try library.flockClear as ComputeKernel
        let count = try library.flockCount as ComputeKernel
        let scan = try library.flockScan as ComputeKernel
        let scatter = try library.flockScatter as ComputeKernel
        let sortCells = try library.flockSortCells as ComputeKernel
        let steer = try library.flockSteer as ComputeKernel
        let table = Int(PARTICLE_FLOCK_TABLE_SIZE)
        return ForEach(Array(flocks.indices), id: \.self) { index in
            let flock = flocks[index]
            let threads = max(Int(flock.windowCount), 1)
            if index > 0 {
                EncoderBarrier(after: .dispatch, before: .dispatch)
            }
            try ComputePipeline(computeKernel: clear) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: table, height: 1, depth: 1))
            }
            .parameter("cellCounts", buffer: buffers.cellCounts)
            EncoderBarrier(after: .dispatch, before: .dispatch)
            try ComputePipeline(computeKernel: count) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: threads, height: 1, depth: 1))
            }
            .parameter("particles", buffer: particles)
            .parameter("flock", value: flock)
            .parameter("cellCounts", buffer: buffers.cellCounts)
            .parameter("particleCells", buffer: buffers.particleCells)
            EncoderBarrier(after: .dispatch, before: .dispatch)
            try ComputePipeline(computeKernel: scan) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: 1, height: 1, depth: 1))
            }
            .parameter("cellCounts", buffer: buffers.cellCounts)
            .parameter("cellStarts", buffer: buffers.cellStarts)
            EncoderBarrier(after: .dispatch, before: .dispatch)
            try ComputePipeline(computeKernel: scatter) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: threads, height: 1, depth: 1))
            }
            .parameter("flock", value: flock)
            .parameter("cellCursors", buffer: buffers.cellCounts)
            .parameter("particleCells", buffer: buffers.particleCells)
            .parameter("scatteredOffsets", buffer: buffers.scatteredOffsets)
            EncoderBarrier(after: .dispatch, before: .dispatch)
            try ComputePipeline(computeKernel: sortCells) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: threads, height: 1, depth: 1))
            }
            .parameter("flock", value: flock)
            .parameter("cellStarts", buffer: buffers.cellStarts)
            .parameter("cellEnds", buffer: buffers.cellCounts)
            .parameter("particleCells", buffer: buffers.particleCells)
            .parameter("scatteredOffsets", buffer: buffers.scatteredOffsets)
            .parameter("sortedOffsets", buffer: buffers.sortedOffsets)
            EncoderBarrier(after: .dispatch, before: .dispatch)
            try ComputePipeline(computeKernel: steer) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: threads, height: 1, depth: 1))
            }
            .parameter("particles", buffer: particles)
            .parameter("flock", value: flock)
            .parameter("cellStarts", buffer: buffers.cellStarts)
            .parameter("cellEnds", buffer: buffers.cellCounts)
            .parameter("sortedOffsets", buffer: buffers.sortedOffsets)
            .parameter("steering", buffer: buffers.steering)
        }
    }
}
