import Metal
import MetalSprocketsParticlesShaders
import simd

/// Draws each particle as a ribbon through its recent positions instead of a sprite (`ParticleEmitter.trail`): spark
/// trails, comets, swooshes. Width is the particle's size; color is its color, with textures running along the ribbon.
/// Each particle keeps `pointCount` positions: one per simulation step by default, so trails cover less time at higher
/// frame rates, or one per `pointInterval` seconds, so they cover the same time at any frame rate.
public struct ParticleTrail: Sendable, Equatable, Codable {
    /// Positions kept per particle, 2...64. Memory is 16 bytes per point per particle of every emitter in the system.
    public var pointCount: Int
    /// Narrows to a point at the tail.
    public var tapers: Bool
    /// Fades out toward the tail.
    public var fades: Bool
    /// Seconds between recorded points; the newest point always follows the particle. 0 records one every step.
    public var pointInterval: Float

    public init(pointCount: Int = 16, tapers: Bool = true, fades: Bool = true, pointInterval: Float = 0) {
        self.pointCount = pointCount
        self.tapers = tapers
        self.fades = fades
        self.pointInterval = pointInterval
    }

    private enum CodingKeys: String, CodingKey {
        case pointCount, tapers, fades, pointInterval
    }

    /// Missing keys keep their defaults, so trails saved before `pointInterval` still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.update(&pointCount, .pointCount)
        try container.update(&tapers, .tapers)
        try container.update(&fades, .fades)
        try container.update(&pointInterval, .pointInterval)
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
        let stride = allEmitters.compactMap { $0.resolved.trail?.clampedPointCount }.max() ?? 0
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
