import Metal
import MetalSprocketsParticlesShaders
import simd

/// Something that happened to a particle on the GPU, reported back to the app. See
/// `ParticleEmitter.reportsCollisions`, `ParticleEmitter.reportsDeaths`, and `ParticleSystemRuntime.recentEvents`.
public struct ParticleEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Hit the collider at this index in `ParticleSystemRuntime.colliders`; -1 for the scene depth.
        case collision(colliderIndex: Int)
        case death
    }

    /// Events the GPU keeps between reads; more than this many in one frame are dropped (oldest first).
    public static let capacity = Int(PARTICLE_EVENT_CAPACITY)

    public var kind: Kind
    /// World space, after the bounce for collisions.
    public var position: SIMD3<Float>
    /// World units per second, after the bounce for collisions.
    public var velocity: SIMD3<Float>
    /// The emitter's simulation time when it happened.
    public var time: Float
    /// Index in `ParticleSystemRuntime.emitters`; sub-emitter children have indices after all emitters.
    public var emitterIndex: Int

    public init(kind: Kind, position: SIMD3<Float>, velocity: SIMD3<Float>, time: Float, emitterIndex: Int) {
        self.kind = kind
        self.position = position
        self.velocity = velocity
        self.time = time
        self.emitterIndex = emitterIndex
    }
}

extension ParticleSystemRuntime {
    /// Reads events the GPU has finished writing since the last read into `recentEvents`.
    func readEvents() {
        let cursor = eventCursor.contents().load(as: UInt32.self)
        let records = eventRecords.contents().bindMemory(to: ParticleEventRecord.self, capacity: ParticleEvent.capacity)
        var events: [ParticleEvent] = []
        var sequence = lastEventSequence
        // Sequence numbers wrap after 4 billion events; the subtraction keeps working across the wrap.
        let pending = Int(cursor &- sequence)
        if pending > ParticleEvent.capacity {
            droppedEventCount += pending - ParticleEvent.capacity
            sequence = cursor &- UInt32(ParticleEvent.capacity)
        }
        while sequence != cursor {
            let next = sequence &+ 1
            let record = records[Int((next &- 1) % UInt32(ParticleEvent.capacity))]
            // Not finished yet (a frame still in flight): stop here and pick it up next time.
            guard record.sequence == next else {
                break
            }
            events.append(ParticleEvent(record))
            sequence = next
        }
        lastEventSequence = sequence
        recentEvents = events
    }
}

extension ParticleEvent {
    init(_ record: ParticleEventRecord) {
        self.init(
            kind: record.kind == .collision
                ? .collision(colliderIndex: record.colliderIndex == PARTICLE_EVENT_SCENE_DEPTH_COLLIDER ? -1 : Int(record.colliderIndex))
                : .death,
            position: SIMD3(record.position.x, record.position.y, record.position.z),
            velocity: SIMD3(record.velocity.x, record.velocity.y, record.velocity.z),
            time: record.position.w,
            emitterIndex: Int(record.emitterIndex)
        )
    }
}
