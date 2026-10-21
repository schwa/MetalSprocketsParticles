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
        /// When the parent moves into `volume` (world space) during a step.
        case onEntering(TriggerVolume)
        /// When the parent flashes: its foil glint, as the camera sees it, rises past `threshold` (0...1) during a step.
        /// Sparkles on confetti. The parent needs `ParticleEmitter.foil` and to turn (tumbling sprites or mesh
        /// particles), and the runtime a camera: `ParticleSystemRuntime.simulate(view:)` or a `ParticlePlayer`.
        case onGlint(threshold: Float = 0.8)
    }

    public var occasion: Occasion
    public var countPerEvent: Int
    /// Fraction of the parent's velocity added to each child.
    public var velocityFactor: Float
    /// The children's modules. Their shape is centered on the parent particle; birth rate, timing, and warmup are
    /// ignored. Their own sub-emitters work, down to `ParticleSystemRuntime.maxSubEmitterDepth` levels, so a particle can change
    /// type several times. Capacity multiplies at each level (parent capacity × countPerEvent).
    public var modules: EmitterModules
    /// The children's modules as flat settings, for code that still edits those (#228). Reading lowers; setting
    /// replaces the modules, keeping disabled ones.
    var settings: ParticleEmitter {
        get { modules.lowered() }
        set { modules = modules.merging(EmitterModules(newValue)) }
    }
    /// How the children are drawn. Soft dots by default.
    public var sprite: ParticleSprite = .softDot
    /// The parent dies when it spawns children, so it turns into them: a transition to another particle type.
    public var replacesParent = false
    /// Children take the parent's age and lifetime instead of starting a new life, so over-life curves carry on from
    /// where the parent was and the child dies when the parent would have.
    public var continuesParentLife = false

    init(occasion: Occasion, countPerEvent: Int, velocityFactor: Float = 0, settings: ParticleEmitter) {
        self.occasion = occasion
        self.countPerEvent = countPerEvent
        self.velocityFactor = velocityFactor
        modules = EmitterModules(settings)
    }

    public init(occasion: Occasion, countPerEvent: Int, velocityFactor: Float = 0, modules: EmitterModules) {
        self.occasion = occasion
        self.countPerEvent = countPerEvent
        self.velocityFactor = velocityFactor
        self.modules = modules
    }

    /// The parent turns into one particle with `settings` and `sprite` when `occasion` happens, keeping its position
    /// and velocity. Set the child's own velocity and spread to zero to keep exactly the parent's motion.
    /// With `continuesLife`, the child also keeps the parent's age and lifetime (see `continuesParentLife`).
    static func transition(
        on occasion: Occasion,
        into settings: ParticleEmitter,
        sprite: ParticleSprite = .softDot,
        continuesLife: Bool = false
    ) -> Self {
        transition(on: occasion, into: EmitterModules(settings), sprite: sprite, continuesLife: continuesLife)
    }

    /// The parent turns into one particle with `modules` and `sprite` when `occasion` happens; see the settings version.
    public static func transition(
        on occasion: Occasion,
        into modules: EmitterModules,
        sprite: ParticleSprite = .softDot,
        continuesLife: Bool = false
    ) -> Self {
        var transition = Self(occasion: occasion, countPerEvent: 1, velocityFactor: 1, modules: modules)
        transition.sprite = sprite
        transition.replacesParent = true
        transition.continuesParentLife = continuesLife
        return transition
    }

    private enum CodingKeys: String, CodingKey {
        case occasion, countPerEvent, velocityFactor, modules, sprite, replacesParent, continuesParentLife
    }

    /// Missing keys keep their defaults, so effects saved before a setting existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modules = try container.decode(EmitterModules.self, forKey: .modules)
        self.init(
            occasion: try container.decode(Occasion.self, forKey: .occasion),
            countPerEvent: try container.decode(Int.self, forKey: .countPerEvent),
            velocityFactor: try container.decodeIfPresent(Float.self, forKey: .velocityFactor) ?? 0,
            modules: modules
        )
        try container.update(&sprite, .sprite)
        try container.update(&replacesParent, .replacesParent)
        try container.update(&continuesParentLife, .continuesParentLife)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(occasion, forKey: .occasion)
        try container.encode(countPerEvent, forKey: .countPerEvent)
        try container.encode(velocityFactor, forKey: .velocityFactor)
        try container.encode(modules, forKey: .modules)
        try container.encode(sprite, forKey: .sprite)
        try container.encode(replacesParent, forKey: .replacesParent)
        try container.encode(continuesParentLife, forKey: .continuesParentLife)
    }

    /// The volume for `.onEntering`; an empty sphere otherwise.
    var volume: TriggerVolumeData {
        if case let .onEntering(volume) = occasion {
            return volume.data
        }
        return TriggerVolume.sphere(center: .zero, radius: 0).data
    }

    var interval: Float {
        switch occasion {
        case let .whileAlive(interval): interval
        case let .atAge(seconds): seconds
        case let .onGlint(threshold): threshold
        default: 0
        }
    }
}
