#include <metal_stdlib>
#include "MetalSprocketsParticlesShaders.h"
using namespace metal;

// Flocking (boids) for one emitter, before the simulation step: a spatial hash of its live particles is built (clear,
// count, scan, scatter, sort each cell), then each particle sums separation, alignment, and cohesion over neighbors within the radius
// and writes the result to steering[], which the update kernel adds to velocity. Nothing reads velocities while they
// change, so there are no races.

namespace Flocking {

static bool isAlive(Particle p) {
    return p.velocity.w > 0 && p.position.w < p.velocity.w;
}

static int3 cellOf(float3 position, float cellSize) {
    return int3(floor(position / max(cellSize, 1e-4)));
}

static uint hashCell(int3 cell) {
    uint h = uint(cell.x) * 73856093u ^ uint(cell.y) * 19349663u ^ uint(cell.z) * 83492791u;
    return h % PARTICLE_FLOCK_TABLE_SIZE;
}

static uint slotIndex(constant FlockData &flock, uint offset) {
    return flock.sliceStart + (flock.windowStart + offset) % flock.capacity;
}

}

kernel void flockClear(device atomic_uint *cellCounts [[buffer(0)]], uint index [[thread_position_in_grid]]) {
    if (index < PARTICLE_FLOCK_TABLE_SIZE) {
        atomic_store_explicit(&cellCounts[index], 0, memory_order_relaxed);
    }
}

kernel void flockCount(
    const device Particle *particles [[buffer(0)]],
    constant FlockData &flock [[buffer(1)]],
    device atomic_uint *cellCounts [[buffer(2)]],
    device uint *particleCells [[buffer(3)]],
    uint offset [[thread_position_in_grid]]
) {
    if (offset >= flock.windowCount) {
        return;
    }
    Particle p = particles[Flocking::slotIndex(flock, offset)];
    if (!Flocking::isAlive(p)) {
        particleCells[offset] = 0xFFFFFFFFu;
        return;
    }
    uint cell = Flocking::hashCell(Flocking::cellOf(p.position.xyz, flock.radius));
    particleCells[offset] = cell;
    atomic_fetch_add_explicit(&cellCounts[cell], 1, memory_order_relaxed);
}

// One thread: turns counts into start offsets, and leaves cellCounts holding the starts as scatter cursors (after the
// scatter, each holds its cell's end).
kernel void flockScan(device uint *cellCounts [[buffer(0)]], device uint *cellStarts [[buffer(1)]], uint index [[thread_position_in_grid]]) {
    if (index != 0) {
        return;
    }
    uint total = 0;
    for (uint i = 0; i < PARTICLE_FLOCK_TABLE_SIZE; i++) {
        uint count = cellCounts[i];
        cellStarts[i] = total;
        cellCounts[i] = total;
        total += count;
    }
}

kernel void flockScatter(
    constant FlockData &flock [[buffer(0)]],
    device atomic_uint *cellCursors [[buffer(1)]],
    const device uint *particleCells [[buffer(2)]],
    device uint *scatteredOffsets [[buffer(3)]],
    uint offset [[thread_position_in_grid]]
) {
    if (offset >= flock.windowCount || particleCells[offset] == 0xFFFFFFFFu) {
        return;
    }
    uint position = atomic_fetch_add_explicit(&cellCursors[particleCells[offset]], 1, memory_order_relaxed);
    scatteredOffsets[position] = offset;
}

// One thread per particle: puts it in its cell in slot order, at the cell's start plus the number of the cell's
// particles before it. The scatter fills cells in whatever order the atomics run; this makes neighbor order, and so
// the neighbor cap and every sum, the same on every run. It used to be an insertion sort with one thread per cell,
// which in a dense pile (most particles in a few cells) took milliseconds on a single thread (#158); this spreads the
// same work over the cell's particles.
kernel void flockSortCells(
    constant FlockData &flock [[buffer(0)]],
    const device uint *cellStarts [[buffer(1)]],
    const device uint *cellEnds [[buffer(2)]],
    const device uint *particleCells [[buffer(3)]],
    const device uint *scatteredOffsets [[buffer(4)]],
    device uint *sortedOffsets [[buffer(5)]],
    uint offset [[thread_position_in_grid]]
) {
    if (offset >= flock.windowCount || particleCells[offset] == 0xFFFFFFFFu) {
        return;
    }
    uint cell = particleCells[offset];
    uint start = cellStarts[cell];
    uint end = cellEnds[cell];
    uint before = 0;
    for (uint i = start; i < end; i++) {
        before += scatteredOffsets[i] < offset ? 1 : 0;
    }
    sortedOffsets[start + before] = offset;
}

kernel void flockSteer(
    const device Particle *particles [[buffer(0)]],
    constant FlockData &flock [[buffer(1)]],
    const device uint *cellStarts [[buffer(2)]],
    const device uint *cellEnds [[buffer(3)]],
    const device uint *sortedOffsets [[buffer(4)]],
    device float4 *steering [[buffer(5)]],
    uint offset [[thread_position_in_grid]]
) {
    if (offset >= flock.windowCount) {
        return;
    }
    uint id = Flocking::slotIndex(flock, offset);
    Particle p = particles[id];
    if (!Flocking::isAlive(p)) {
        steering[id] = float4(0);
        return;
    }
    float3 position = p.position.xyz;
    float3 velocity = p.velocity.xyz;
    int3 home = Flocking::cellOf(position, flock.radius);
    float3 separation = 0;
    float3 averageVelocity = 0;
    float3 center = 0;
    uint neighbors = 0;
    uint visited[27];
    uint visitedCount = 0;
    float radiusSquared = flock.radius * flock.radius;
    float separationSquared = flock.separationRadius * flock.separationRadius;
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                uint cell = Flocking::hashCell(home + int3(x, y, z));
                bool seen = false;
                for (uint i = 0; i < visitedCount; i++) {
                    seen = seen || visited[i] == cell;
                }
                if (seen) {
                    continue;
                }
                visited[visitedCount++] = cell;
                for (uint i = cellStarts[cell]; i < cellEnds[cell] && neighbors < flock.maxNeighbors; i++) {
                    uint otherOffset = sortedOffsets[i];
                    if (otherOffset == offset) {
                        continue;
                    }
                    Particle other = particles[Flocking::slotIndex(flock, otherOffset)];
                    float3 away = position - other.position.xyz;
                    float distanceSquared = dot(away, away);
                    if (distanceSquared > radiusSquared) {
                        continue;
                    }
                    if (distanceSquared < separationSquared && distanceSquared > 1e-10) {
                        separation += away / distanceSquared;
                    }
                    averageVelocity += other.velocity.xyz;
                    center += other.position.xyz;
                    neighbors++;
                }
            }
        }
    }
    float3 steer = separation * flock.separation;
    if (neighbors > 0) {
        float count = float(neighbors);
        steer += (averageVelocity / count - velocity) * flock.alignment;
        steer += (center / count - position) * flock.cohesion;
    }
    steering[id] = float4(steer, 1);
}
