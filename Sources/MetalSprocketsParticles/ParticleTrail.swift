import Metal
import MetalSprocketsParticlesShaders
import simd

/// Draws each particle as a ribbon through its recent positions instead of a sprite (`ParticleEmitter.trail`): spark
/// trails, comets, swooshes. Width is the particle's size; color is its color, with textures running along the ribbon.
/// Each particle keeps `pointCount` positions, one per simulation step, so trails are longer at lower frame rates.
public struct ParticleTrail: Sendable, Equatable, Codable {
    /// Positions kept per particle, 2...64. Memory is 16 bytes per point per particle of every emitter in the system.
    public var pointCount: Int
    /// Narrows to a point at the tail.
    public var tapers: Bool
    /// Fades out toward the tail.
    public var fades: Bool

    public init(pointCount: Int = 16, tapers: Bool = true, fades: Bool = true) {
        self.pointCount = pointCount
        self.tapers = tapers
        self.fades = fades
    }

    static let maximumPointCount = 64

    var clampedPointCount: Int {
        min(max(pointCount, 2), Self.maximumPointCount)
    }
}

extension ParticleSystemRuntime {
    /// Makes the trail buffer when an emitter has a trail: `trailStride` points for every particle in the system.
    /// Called after planning (which may rebuild the particle buffer); returns the stride to put in the uniforms.
    func makeTrailsIfNeeded() throws -> Int {
        let stride = allEmitters.compactMap { $0.settings.trail?.clampedPointCount }.max() ?? 0
        guard stride > 0 else {
            return 0
        }
        let particleCount = buffer.length / MemoryLayout<Particle>.stride
        let length = particleCount * stride * MemoryLayout<SIMD4<Float>>.stride
        if let trails, trails.length == length {
            return stride
        }
        guard let trails = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw ParticleSystemRuntimeError.tooManyParticles
        }
        trails.label = "Particle trails"
        self.trails = trails
        return stride
    }
}
