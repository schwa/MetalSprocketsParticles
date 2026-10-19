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

        // Effect files name the event ("event": { "name": "boom" }) instead of Swift's default "_0". Codable needs
        // these key enums nested in the enum they describe.
        // swiftlint:disable:next nesting
        private enum EventCodingKeys: String, CodingKey {
            case _0 = "name" // swiftlint:disable:this identifier_name
        }

        private enum CodingKeys: String, CodingKey {
            case event, after, every, objectEnters, particlesEnter, colliderHit
        }

        // swiftlint:disable:next nesting
        private enum ValueKeys: String, CodingKey {
            case name, legacyName = "_0", seconds, volume, count, index
        }

        /// Reads the event's "name", and "_0" from files saved before it was named; the other cases as written.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let key = container.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected a trigger condition"))
            }
            let values = try container.nestedContainer(keyedBy: ValueKeys.self, forKey: key)
            switch key {
            case .event:
                self = .event(try values.decodeIfPresent(String.self, forKey: .name) ?? values.decode(String.self, forKey: .legacyName))
            case .after:
                self = .after(seconds: try values.decode(Float.self, forKey: .seconds))
            case .every:
                self = .every(seconds: try values.decode(Float.self, forKey: .seconds))
            case .objectEnters:
                self = .objectEnters(name: try values.decode(String.self, forKey: .name), volume: try values.decode(TriggerVolume.self, forKey: .volume))
            case .particlesEnter:
                self = .particlesEnter(volume: try values.decode(TriggerVolume.self, forKey: .volume), count: try values.decodeIfPresent(Int.self, forKey: .count) ?? 1)
            case .colliderHit:
                self = .colliderHit(index: try values.decode(Int.self, forKey: .index), count: try values.decodeIfPresent(Int.self, forKey: .count) ?? 1)
            }
        }
    }

    public enum Action: Sendable, Equatable, Codable {
        case burst(Int)
        /// Turns emission on.
        case start
        /// Turns emission off; existing particles live on.
        case stop
        /// Removes the emitter's particles and restarts its clock.
        case restart

        // Effect files name the count ("burst": { "count": 150 }) instead of Swift's default "_0".
        // swiftlint:disable:next nesting
        private enum BurstCodingKeys: String, CodingKey {
            case _0 = "count" // swiftlint:disable:this identifier_name
        }

        private enum CodingKeys: String, CodingKey {
            case burst, start, stop, restart
        }

        // swiftlint:disable:next nesting
        private enum BurstValueKeys: String, CodingKey {
            case count
            case legacy = "_0"
        }

        /// Reads "count", and "_0" from files saved before it was named.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let key = container.allKeys.first else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected burst, start, stop, or restart"))
            }
            switch key {
            case .burst:
                let values = try container.nestedContainer(keyedBy: BurstValueKeys.self, forKey: .burst)
                self = .burst(try values.decodeIfPresent(Int.self, forKey: .count) ?? values.decode(Int.self, forKey: .legacy))
            case .start: self = .start
            case .stop: self = .stop
            case .restart: self = .restart
            }
        }
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
