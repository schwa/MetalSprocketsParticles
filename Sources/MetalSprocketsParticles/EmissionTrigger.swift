import MetalSprocketsParticlesShaders
import simd

/// Makes an emitter react to something happening: an app event, a timer, an object or particles entering a volume, or
/// a collider being hit. Triggers are checked at the start of each `ParticleSystemRuntime.simulate`.
public struct EmissionTrigger: Sendable, Equatable, Codable {
    public enum Condition: Sendable, Equatable, Codable {
        /// `ParticleSystemRuntime.send(event:)` with this name.
        case event(String)
        /// Once, this many seconds of simulation time after the system starts or restarts.
        case after(seconds: Float)
        /// Every this many seconds of simulation time.
        case every(seconds: Float)
        /// A tracked object (`ParticleSystemRuntime.trackedObjects`) moves from outside to inside the volume.
        case objectEnters(name: String, volume: TriggerVolume)
        /// At least `count` particles, from any emitter, entered the volume since the last check. Counted on the GPU
        /// and read back, so it can lag the event by a frame or two while frames are in flight.
        case particlesEnter(volume: TriggerVolume, count: Int = 1)
        /// At least `count` particle hits on `ParticleSystemRuntime.colliders[index]` since the last check. Read back from the
        /// GPU like `particlesEnter`.
        case colliderHit(index: Int, count: Int = 1)
    }

    public enum Action: Sendable, Equatable, Codable {
        case burst(Int)
        /// Turns emission on.
        case start
        /// Turns emission off; existing particles live on.
        case stop
        /// Removes the emitter's particles and restarts its clock.
        case restart
    }

    public var condition: Condition
    public var action: Action

    public init(_ condition: Condition, _ action: Action) {
        self.condition = condition
        self.action = action
    }
}

/// A world-space region for triggers.
public enum TriggerVolume: Sendable, Equatable, Codable {
    case sphere(center: SIMD3<Float>, radius: Float)
    case box(center: SIMD3<Float>, halfExtents: SIMD3<Float>)

    public func contains(_ point: SIMD3<Float>) -> Bool {
        switch self {
        case let .sphere(center, radius):
            simd_distance(point, center) < radius
        case let .box(center, halfExtents):
            all(abs(point - center) .< halfExtents)
        }
    }

    var data: TriggerVolumeData {
        switch self {
        case let .sphere(center, radius):
            TriggerVolumeData(kind: .sphere, radius: radius, center: center, halfExtents: .zero)
        case let .box(center, halfExtents):
            TriggerVolumeData(kind: .box, radius: 0, center: center, halfExtents: halfExtents)
        }
    }
}
