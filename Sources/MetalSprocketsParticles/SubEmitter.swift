import MetalSprocketsParticlesShaders

/// Particles spawned by another emitter's particles when something happens to them: fireworks that burst when the
/// rocket dies, splashes where rain hits, trails behind sparks.
///
/// Each parent particle owns `countPerEvent` child slots. A new event overwrites that parent's earlier children, so a
/// parent never has more than `countPerEvent` children alive at once. Children live in world space.
public struct SubEmitter: Sendable, Equatable {
    public enum Occasion: Sendable, Equatable {
        case onBirth
        /// When the parent's lifetime ends, or it dies on collision.
        case onDeath
        case onCollision
        /// One child every `interval` seconds of the parent's life, reusing the parent's slots in turn: a trail of
        /// `countPerEvent` points.
        case whileAlive(interval: Float)
    }

    public var occasion: Occasion
    public var countPerEvent: Int
    /// Fraction of the parent's velocity added to each child.
    public var velocityFactor: Float
    /// The children's settings. Their shape is centered on the parent particle; birth rate, timing, warmup, and nested
    /// sub-emitters are ignored.
    public var settings: ParticleEmitter

    public init(occasion: Occasion, countPerEvent: Int, velocityFactor: Float = 0, settings: ParticleEmitter) {
        self.occasion = occasion
        self.countPerEvent = countPerEvent
        self.velocityFactor = velocityFactor
        self.settings = settings
    }

    var interval: Float {
        if case let .whileAlive(interval) = occasion {
            return interval
        }
        return 0
    }
}
