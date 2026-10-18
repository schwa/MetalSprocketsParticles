import MetalSprocketsParticlesShaders

/// Particles spawned by another emitter's particles when something happens to them: fireworks that burst when the
/// rocket dies, splashes where rain hits, trails behind sparks.
///
/// Each parent particle owns `countPerEvent` child slots. A new event overwrites that parent's earlier children, so a
/// parent never has more than `countPerEvent` children alive at once. Children live in world space.
public struct SubEmitter: Sendable, Equatable, Codable {
    public enum Occasion: Sendable, Equatable, Codable {
        case onBirth
        /// When the parent's lifetime ends, or it dies on collision.
        case onDeath
        case onCollision
        /// One child every `interval` seconds of the parent's life, reusing the parent's slots in turn: a trail of
        /// `countPerEvent` points.
        case whileAlive(interval: Float)
        /// Once, when the parent is `seconds` old.
        case atAge(seconds: Float)
    }

    public var occasion: Occasion
    public var countPerEvent: Int
    /// Fraction of the parent's velocity added to each child.
    public var velocityFactor: Float
    /// The children's settings. Their shape is centered on the parent particle; birth rate, timing, warmup, and nested
    /// sub-emitters are ignored.
    public var settings: ParticleEmitter
    /// How the children are drawn. Soft dots by default.
    public var sprite: ParticleSprite = .softDot
    /// The parent dies when it spawns children, so it turns into them: a transition to another particle type.
    public var replacesParent = false
    /// Children take the parent's age and lifetime instead of starting a new life, so over-life curves carry on from
    /// where the parent was and the child dies when the parent would have.
    public var continuesParentLife = false

    public init(occasion: Occasion, countPerEvent: Int, velocityFactor: Float = 0, settings: ParticleEmitter) {
        self.occasion = occasion
        self.countPerEvent = countPerEvent
        self.velocityFactor = velocityFactor
        self.settings = settings
    }

    /// The parent turns into one particle with `settings` and `sprite` when `occasion` happens, keeping its position
    /// and velocity. Set the child's own velocity and spread to zero to keep exactly the parent's motion.
    /// With `continuesLife`, the child also keeps the parent's age and lifetime (see `continuesParentLife`).
    public static func transition(
        on occasion: Occasion,
        into settings: ParticleEmitter,
        sprite: ParticleSprite = .softDot,
        continuesLife: Bool = false
    ) -> Self {
        var transition = Self(occasion: occasion, countPerEvent: 1, velocityFactor: 1, settings: settings)
        transition.sprite = sprite
        transition.replacesParent = true
        transition.continuesParentLife = continuesLife
        return transition
    }

    private enum CodingKeys: String, CodingKey {
        case occasion, countPerEvent, velocityFactor, settings, sprite, replacesParent, continuesParentLife
    }

    /// Missing keys keep their defaults, so effects saved before a setting existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            occasion: try container.decode(Occasion.self, forKey: .occasion),
            countPerEvent: try container.decode(Int.self, forKey: .countPerEvent),
            velocityFactor: try container.decodeIfPresent(Float.self, forKey: .velocityFactor) ?? 0,
            settings: try container.decode(ParticleEmitter.self, forKey: .settings)
        )
        try container.update(&sprite, .sprite)
        try container.update(&replacesParent, .replacesParent)
        try container.update(&continuesParentLife, .continuesParentLife)
    }

    var interval: Float {
        switch occasion {
        case let .whileAlive(interval): interval
        case let .atAge(seconds): seconds
        default: 0
        }
    }
}
