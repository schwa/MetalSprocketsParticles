import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

/// Draw order of one emitter's particles.
public enum ParticleSortMode: String, CaseIterable, Identifiable, Sendable {
    /// Buffer order. Right for additive blending, which does not depend on order, and the cheapest.
    case none = "None"
    /// Farthest first, so alpha blending composites correctly. Needs the camera: pass `view` to
    /// `ParticleSystem.simulate(deltaTime:colliders:transforms:view:)`.
    case backToFront = "Back to Front"

    public var id: Self { self }
}

/// Scratch buffers for one emitter's radix sort, sized for its capacity.
final class ParticleSortBuffers {
    static let elementsPerTile = 1_024

    let recordsA: MTLBuffer
    let recordsB: MTLBuffer
    let histogram: MTLBuffer
    let offsets: MTLBuffer
    let digitTotals: MTLBuffer
    let digitBase: MTLBuffer
    let capacity: Int

    init(device: MTLDevice, capacity: Int) throws {
        self.capacity = capacity
        let tiles = (capacity + Self.elementsPerTile - 1) / Self.elementsPerTile
        func buffer(_ length: Int, _ label: String) throws -> MTLBuffer {
            // Shared so tests can read the sorted records; on unified memory it costs the same as private.
            guard let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
                throw CocoaError(.featureUnsupported)
            }
            buffer.label = label
            return buffer
        }
        recordsA = try buffer(capacity * MemoryLayout<SIMD2<UInt32>>.stride, "Particle sort records A")
        recordsB = try buffer(capacity * MemoryLayout<SIMD2<UInt32>>.stride, "Particle sort records B")
        histogram = try buffer(256 * tiles * 4, "Particle sort histogram")
        offsets = try buffer(256 * tiles * 4, "Particle sort offsets")
        digitTotals = try buffer(256 * 4, "Particle sort digit totals")
        digitBase = try buffer(256 * 4, "Particle sort digit base")
    }
}

/// Everything one emitter's sort needs this frame, captured when the compute element is built.
struct EmitterSort {
    var buffers: ParticleSortBuffers
    var keyParameters: ParticleSortKeyParams
    var count: Int

    var numTiles: Int {
        (count + ParticleSortBuffers.elementsPerTile - 1) / ParticleSortBuffers.elementsPerTile
    }

    func radixParameters(shift: UInt32) -> ParticleRadixParams {
        ParticleRadixParams(numElements: UInt32(count), numTiles: UInt32(numTiles), elementsPerTile: UInt32(ParticleSortBuffers.elementsPerTile), shift: shift)
    }
}

/// The kernels of the radix sort in ParticleSort.metal.
struct ParticleSortKernels {
    var buildRecords: ComputeKernel
    var histogram: ComputeKernel
    var scanOffsets: ComputeKernel
    var scanDigitBase: ComputeKernel
    var scatter: ComputeKernel

    init(library: ShaderLibrary) throws {
        let functions = library.namespaced("ParticleSort")
        buildRecords = try functions.buildSortRecords
        histogram = try functions.radixHistogram
        scanOffsets = try functions.radixScanOffsets
        scanDigitBase = try functions.radixScanDigitBase
        scatter = try functions.radixScatter
    }

    /// Builds records into A, then sorts 16-bit keys in two passes: A to B, then B to A. Ends with sorted records in A.
    func element(_ sort: EmitterSort, particles: MTLBuffer) throws -> some Element {
        let buffers = sort.buffers
        let tiles = MTLSize(width: max(sort.numTiles, 1), height: 1, depth: 1)
        let simdGroup = MTLSize(width: 32, height: 1, depth: 1)
        let single = MTLSize(width: 1, height: 1, depth: 1)
        return try Group {
            try ComputePipeline(computeKernel: buildRecords) {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: max(sort.count, 1), height: 1, depth: 1))
            }
            .parameter("particles", buffer: particles)
            .parameter("records", buffer: buffers.recordsA)
            .parameter("p", value: sort.keyParameters)
            ForEach([(UInt32(0), buffers.recordsA, buffers.recordsB), (UInt32(8), buffers.recordsB, buffers.recordsA)], id: \.0) { shift, source, destination in
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(computeKernel: histogram) {
                    try ComputeDispatch(threadgroups: tiles, threadsPerThreadgroup: simdGroup)
                }
                .parameter("records", buffer: source)
                .parameter("hist", buffer: buffers.histogram)
                .parameter("p", value: sort.radixParameters(shift: shift))
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(computeKernel: scanOffsets) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: 256, height: 1, depth: 1))
                }
                .parameter("hist", buffer: buffers.histogram)
                .parameter("offset", buffer: buffers.offsets)
                .parameter("total", buffer: buffers.digitTotals)
                .parameter("p", value: sort.radixParameters(shift: shift))
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(computeKernel: scanDigitBase) {
                    try ComputeDispatch(threadsPerGrid: single, threadsPerThreadgroup: single)
                }
                .parameter("total", buffer: buffers.digitTotals)
                .parameter("digitBase", buffer: buffers.digitBase)
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(computeKernel: scatter) {
                    try ComputeDispatch(threadgroups: tiles, threadsPerThreadgroup: simdGroup)
                }
                .parameter("inRecords", buffer: source)
                .parameter("outRecords", buffer: destination)
                .parameter("offset", buffer: buffers.offsets)
                .parameter("digitBase", buffer: buffers.digitBase)
                .parameter("p", value: sort.radixParameters(shift: shift))
            }
        }
    }
}
