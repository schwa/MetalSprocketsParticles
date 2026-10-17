#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// Back-to-front sort of one emitter's live particles: an 8-bit LSD radix sort over a 16-bit depth key, two passes.
// The histogram, scan, and stable scatter kernels are ported from MetalSprocketsGaussianSplats (SplatGPUSort.metal),
// without its culling and compaction: the live window is sorted as is, and dead particles get the largest key.

namespace ParticleSort {

constant uint RADIX = 256;

// Maps a half's bits to a ushort that sorts ascending, negatives included.
inline ushort floatFlip16(ushort f) {
    ushort mask = ushort(short(f) >> 15) | 0x8000u;
    return f ^ mask;
}

kernel void buildSortRecords(
    device const Particle *particles [[buffer(0)]],
    device uint2 *records [[buffer(1)]],
    constant ParticleSortKeyParams &p [[buffer(2)]],
    uint i [[thread_position_in_grid]]
) {
    uint count = p.window.y;
    if (i >= count) {
        return;
    }
    uint index = p.window.w + (p.window.x + i) % p.window.z;
    Particle particle = particles[index];
    bool alive = particle.velocity.w > 0 && particle.position.w < particle.velocity.w;
    // Farther first: sort ascending on negated view depth. Dead particles go last.
    ushort key = 0xFFFFu;
    if (alive) {
        float3 world = (p.model * float4(particle.position.xyz, 1)).xyz;
        float depth = dot(world - p.cameraPosition.xyz, p.cameraForward.xyz);
        key = min(floatFlip16(as_type<ushort>(half(-depth))), ushort(0xFFFEu));
    }
    records[i] = uint2(key, index);
}

// One threadgroup per tile: digit histogram in threadgroup memory. Layout is digit-major: hist[digit * numTiles + tile].
kernel void radixHistogram(
    device const uint2 *records [[buffer(0)]],
    device uint *hist [[buffer(1)]],
    constant ParticleRadixParams &p [[buffer(2)]],
    uint tile [[threadgroup_position_in_grid]],
    uint lid [[thread_position_in_threadgroup]],
    uint tsize [[threads_per_threadgroup]]
) {
    threadgroup atomic_uint tgHist[256];
    for (uint d = lid; d < RADIX; d += tsize) {
        atomic_store_explicit(&tgHist[d], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint start = tile * p.elementsPerTile;
    uint end = min(start + p.elementsPerTile, p.numElements);
    for (uint i = start + lid; i < end; i += tsize) {
        uint digit = (records[i].x >> p.shift) & 0xFFu;
        atomic_fetch_add_explicit(&tgHist[digit], 1u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint d = lid; d < RADIX; d += tsize) {
        hist[d * p.numTiles + tile] = atomic_load_explicit(&tgHist[d], memory_order_relaxed);
    }
}

// One thread per digit: exclusive prefix sum of that digit's counts across tiles, and the digit total.
kernel void radixScanOffsets(
    device const uint *hist [[buffer(0)]],
    device uint *offset [[buffer(1)]],
    device uint *total [[buffer(2)]],
    constant ParticleRadixParams &p [[buffer(3)]],
    uint digit [[thread_position_in_grid]]
) {
    if (digit >= RADIX) {
        return;
    }
    uint running = 0;
    uint base = digit * p.numTiles;
    for (uint t = 0; t < p.numTiles; t++) {
        offset[base + t] = running;
        running += hist[base + t];
    }
    total[digit] = running;
}

// Single thread: exclusive prefix sum of the 256 digit totals.
kernel void radixScanDigitBase(
    device const uint *total [[buffer(0)]],
    device uint *digitBase [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0) {
        return;
    }
    uint running = 0;
    for (uint d = 0; d < RADIX; d++) {
        digitBase[d] = running;
        running += total[d];
    }
}

// One SIMD-group per tile: stable scatter. Lane order and chunk order match input order.
kernel void radixScatter(
    device const uint2 *inRecords [[buffer(0)]],
    device uint2 *outRecords [[buffer(1)]],
    device const uint *offset [[buffer(2)]],
    device const uint *digitBase [[buffer(3)]],
    constant ParticleRadixParams &p [[buffer(4)]],
    uint tile [[threadgroup_position_in_grid]],
    uint lane [[thread_position_in_threadgroup]],
    uint tsize [[threads_per_threadgroup]]
) {
    threadgroup uint cursor[256];
    for (uint d = lane; d < RADIX; d += tsize) {
        cursor[d] = digitBase[d] + offset[d * p.numTiles + tile];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint start = tile * p.elementsPerTile;
    uint end = min(start + p.elementsPerTile, p.numElements);
    uint n = end > start ? end - start : 0u;
    for (uint chunk = 0; chunk < p.elementsPerTile; chunk += tsize) {
        uint local = chunk + lane;
        bool active = local < n;
        uint2 record = active ? inRecords[start + local] : uint2(0u, 0u);
        uint digit = active ? ((record.x >> p.shift) & 0xFFu) : 0u;
        // Peers: active lanes with the same digit, found with one ballot per bit. Keeps lane order, so stable.
        uint peers = uint((simd_vote::vote_t)simd_ballot(active));
        for (uint b = 0; b < 8; b++) {
            bool bit = (digit >> b) & 1u;
            uint ball = uint((simd_vote::vote_t)simd_ballot(bit));
            peers &= bit ? ball : ~ball;
        }
        uint rank = popcount(peers & ((1u << lane) - 1u));
        uint total = popcount(peers);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint base = active ? cursor[digit] : 0u;
        if (active) {
            outRecords[base + rank] = record;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (active && rank == 0) {
            cursor[digit] += total;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
}

} // namespace ParticleSort
