import MetalSprocketsParticlesShaders
import simd

// Adding a setting:
// 1. The property here, with its default.
// 2. A `container.update` line in `init(from:)` (DecodingCoverageTests fails if it is missing).
// 3. If the GPU needs it: a field in SimulationUniforms or RenderUniforms (ParticleTypes.h), set in
//    FramePlan.uniforms(for:) or the render draw, and used in Particles.metal.
// 4. A control in the demo inspector, and in ParticleKind.swift if it is a new enum kind.

/// Settings for one emitter. Colliders and force fields are shared by all emitters and live on `ParticleSystemRuntime`.
public struct ParticleEmitter: Sendable, Equatable, Codable {
    /// Center of `shape` in emitter space.
    public var position: SIMD3<Float> = .zero
    public var shape: EmitterShape = .sphere(radius: 0.05)
    public var birthLocation: ParticleBirthLocation = .volume
    public var birthDirection: ParticleBirthDirection = .velocity
    /// Limits sphere, disc, cylinder, cone, and torus shapes to this angle around +Y, in radians.
    public var sweepAngle: Float = 2 * .pi

    /// The sphere radius. Setting it makes the shape a sphere.
    public var radius: Float {
        get {
            if case let .sphere(radius) = shape {
                return radius
            }
            return 0
        }
        set { shape = .sphere(radius: newValue) }
    }

    /// Base velocity. With `birthDirection` `.normal`, only its length is used, as the speed along the shape normal.
    public var velocity: SIMD3<Float> = [0, 4, 0]
    public var velocitySpread: Float = 1.5
    public var lifetime: ClosedRange<Float> = 1.5...3
    /// Color by normalized age. Alpha is further multiplied by `opacityOverLife`.
    public var colorOverLife = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.7, 0.2, 1], to: [0.8, 0.1, 0.05, 0])
    /// Half-width of the quad in world units, by normalized age.
    public var sizeOverLife = ParticleCurve<Float>.linear(from: 0.04, to: 0.01)
    /// Multiplies color alpha by normalized age.
    public var opacityOverLife = ParticleCurve<Float>.constant(1)

    /// First keyframe of `colorOverLife`.
    public var colorStart: SIMD4<Float> {
        get { colorOverLife.start }
        set { colorOverLife.start = newValue }
    }
    /// Last keyframe of `colorOverLife`.
    public var colorEnd: SIMD4<Float> {
        get { colorOverLife.end }
        set { colorOverLife.end = newValue }
    }
    /// First keyframe of `sizeOverLife`.
    public var sizeStart: Float {
        get { sizeOverLife.start }
        set { sizeOverLife.start = newValue }
    }
    /// Last keyframe of `sizeOverLife`.
    public var sizeEnd: Float {
        get { sizeOverLife.end }
        set { sizeOverLife.end = newValue }
    }
    /// World-space acceleration, in every simulation space.
    public var gravity: SIMD3<Float> = [0, -9.8, 0]
    public var drag: Float = 0.1
    public var restitution: Float = 0.4
    /// Per-particle offset range for `restitution`, picked at birth.
    public var restitutionVariation: Float = 0
    public var friction: Float = 0.2
    /// Per-particle offset range for `friction`, picked at birth.
    public var frictionVariation: Float = 0
    /// Removes particles the moment they touch a collider, instead of bouncing. Good for rain and sparks on walls.
    public var diesOnCollision = false
    /// Per-particle offset range in m/s for initial speed, applied after `velocitySpread`.
    public var speedVariation: Float = 0
    /// Per-particle size multiplier range as a fraction: 0.25 scales `sizeOverLife` by 0.75...1.25.
    public var sizeVariation: Float = 0
    /// Per-particle offset ranges for hue (in turns, wraps), saturation, brightness, and alpha, applied to
    /// `colorOverLife`.
    public var colorVariation: SIMD4<Float> = .zero

    /// Initial rotation in radians, ± `angleVariation`.
    public var angle: Float = 0
    public var angleVariation: Float = 0
    /// Initial spin in radians per second, ± `angularSpeedVariation`.
    public var angularSpeed: Float = 0
    public var angularSpeedVariation: Float = 0

    public var blendMode: ParticleBlendMode = .alpha
    /// Back-to-front sorting for alpha blending. Additive blending does not need it.
    public var sortMode: ParticleSortMode = .none

    /// Treats the emitter's texture as a grid of animation frames. Ignored without a texture.
    public var imageSequence: ImageSequence?

    public var orientation: ParticleOrientation = .billboard

    /// Particles spawned per second while emitting. When the emitter's slice is full, its oldest particles are recycled.
    public var birthRate: Float = 1_000
    /// Offset range for `birthRate`, picked once per emission cycle (once overall when emission does not loop).
    public var birthRateVariation: Float = 0
    /// Fraction of the emitter's own velocity (from its transform's motion) given to newborn particles. World
    /// simulation space only.
    public var inheritVelocity: Float = 0
    /// Seconds of emission per cycle. `nil` emits forever.
    public var emissionDuration: Float?
    /// Seconds without emission after each emission period. Only used when `emissionDuration` is set.
    public var idleDuration: Float = 0
    /// Repeats the emission/idle cycle. When false, emission ends after the first `emissionDuration`.
    public var loops = true
    /// Seconds simulated before the first rendered frame, and again after `restart()`.
    public var warmupDuration: Float = 0
    /// Shapes emission over time: a multiplier on `birthRate`, keyed in seconds since the emitter started (warmup
    /// included). After the last keyframe the last value holds, so a curve ending at 0 makes a finite effect: for
    /// example (0 s, 1), (10 s, 1), (12 s, 0) runs fully for 10 seconds and fades out by 12. The default, constant 1,
    /// emits forever. Multiplies with `emissionDuration` cycles; bursts are not affected.
    public var emissionOverTime = ParticleCurve<Float>.constant(1)

    /// Emitters driven by this emitter's particles. Adding or removing sub-emitters, or changing `countPerEvent`,
    /// rebuilds the system's buffer on the next `simulate`, which removes all particles.
    public var subEmitters: [SubEmitter] = []

    /// Reactions to events, timers, volumes, and collider hits.
    public var triggers: [EmissionTrigger] = []
    /// Colliders apply when their `categoryBitMask` shares a bit with this. All bits by default.
    public var collisionMask: UInt32 = .max
    /// Force fields apply when their `categoryBitMask` shares a bit with this. All bits by default.
    public var fieldMask: UInt32 = .max
    /// Shades particles with `ParticleSystemRuntime.lights` and `ambientLight`. Off by default: particles keep their colors.
    public var isLit = false
    /// Soft particles: fade out over this many world units in front of the scene depth passed to
    /// `ParticleSystemRuntime.render(projection:view:sceneDepth:)`, instead of clipping hard. 0 turns it off.
    public var softness: Float = 0
    /// Runs for every live particle each step, after gravity, force fields, and drag, before collisions.
    public var updateFunction: ParticleFunction?
    /// Keeps particles on the emitter's XY plane (through its position, facing its local Z axis): spread, shapes,
    /// turbulence, fields, and collisions cannot move them off it. With no emitter transform that is the world's
    /// z = 0 plane, for 2D effects; in 3D it follows the emitter, for flat sheets or effects on a wall.
    public var constrainsToPlane = false
    /// Runs once for each new particle, after the built-in spawn. It may change position, velocity, and lifetime.
    /// Sub-emitter children are not passed through it.
    public var spawnFunction: ParticleFunction?
    /// Runs when a particle hits a collider this step, after the bounce. It may change position, velocity, age, and
    /// lifetime; setting age to lifetime kills the particle.
    public var collisionFunction: ParticleFunction?
    /// Runs on the step a particle dies (age reaches lifetime), before on-death sub-emitters. Raising lifetime above
    /// age keeps it alive.
    public var deathFunction: ParticleFunction?
    /// Reports each collider hit to the app in `ParticleSystemRuntime.recentEvents`, with where, how fast, and which
    /// collider. For sounds, decals, or game logic.
    public var reportsCollisions = false
    /// Reports each particle death in `ParticleSystemRuntime.recentEvents`.
    public var reportsDeaths = false
    /// Distance LOD: emission is full up to `lodNearDistance` from the camera and falls to `lodFarRateScale` times
    /// the birth rate at `lodFarDistance`. Off while `lodFarDistance` is not greater than `lodNearDistance`.
    public var lodNearDistance: Float = 0
    public var lodFarDistance: Float = 0
    public var lodFarRateScale: Float = 0.25
    /// A sphere around the emitter's position that holds its particles. When it is outside the view the emitter is not
    /// drawn. 0 never culls.
    public var cullingRadius: Float = 0
    /// Keeps simulating while culled, so the effect is right when it comes back into view. Off saves the GPU work but
    /// freezes the effect until it is visible again.
    public var simulatesWhenCulled = true
    /// Makes some of this emitter's particles light the scene.
    public var light: ParticleLightEmission?

    public init() {}
}

extension ParticleEmitter {
    /// Missing keys keep their defaults, so effects saved before a setting existed still load.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.update(&position, .position)
        try container.update(&shape, .shape)
        try container.update(&birthLocation, .birthLocation)
        try container.update(&birthDirection, .birthDirection)
        try container.update(&sweepAngle, .sweepAngle)
        try container.update(&velocity, .velocity)
        try container.update(&velocitySpread, .velocitySpread)
        try container.update(&lifetime, .lifetime)
        try container.update(&colorOverLife, .colorOverLife)
        try container.update(&sizeOverLife, .sizeOverLife)
        try container.update(&opacityOverLife, .opacityOverLife)
        try container.update(&gravity, .gravity)
        try container.update(&drag, .drag)
        try container.update(&restitution, .restitution)
        try container.update(&restitutionVariation, .restitutionVariation)
        try container.update(&friction, .friction)
        try container.update(&frictionVariation, .frictionVariation)
        try container.update(&diesOnCollision, .diesOnCollision)
        try container.update(&speedVariation, .speedVariation)
        try container.update(&sizeVariation, .sizeVariation)
        try container.update(&colorVariation, .colorVariation)
        try container.update(&angle, .angle)
        try container.update(&angleVariation, .angleVariation)
        try container.update(&angularSpeed, .angularSpeed)
        try container.update(&angularSpeedVariation, .angularSpeedVariation)
        try container.update(&blendMode, .blendMode)
        try container.update(&sortMode, .sortMode)
        try container.update(&imageSequence, .imageSequence)
        try container.update(&orientation, .orientation)
        try container.update(&birthRate, .birthRate)
        try container.update(&birthRateVariation, .birthRateVariation)
        try container.update(&inheritVelocity, .inheritVelocity)
        try container.update(&emissionDuration, .emissionDuration)
        try container.update(&idleDuration, .idleDuration)
        try container.update(&loops, .loops)
        try container.update(&warmupDuration, .warmupDuration)
        try container.update(&subEmitters, .subEmitters)
        try container.update(&triggers, .triggers)
        try container.update(&collisionMask, .collisionMask)
        try container.update(&fieldMask, .fieldMask)
        try container.update(&emissionOverTime, .emissionOverTime)
        try container.update(&isLit, .isLit)
        try container.update(&softness, .softness)
        updateFunction = try container.decodeIfPresent(ParticleFunction.self, forKey: .updateFunction)
        try container.update(&constrainsToPlane, .constrainsToPlane)
        spawnFunction = try container.decodeIfPresent(ParticleFunction.self, forKey: .spawnFunction)
        collisionFunction = try container.decodeIfPresent(ParticleFunction.self, forKey: .collisionFunction)
        deathFunction = try container.decodeIfPresent(ParticleFunction.self, forKey: .deathFunction)
        try container.update(&reportsCollisions, .reportsCollisions)
        try container.update(&reportsDeaths, .reportsDeaths)
        try container.update(&lodNearDistance, .lodNearDistance)
        try container.update(&lodFarDistance, .lodFarDistance)
        try container.update(&lodFarRateScale, .lodFarRateScale)
        try container.update(&cullingRadius, .cullingRadius)
        try container.update(&simulatesWhenCulled, .simulatesWhenCulled)
        light = try container.decodeIfPresent(ParticleLightEmission.self, forKey: .light)
    }
}

extension KeyedDecodingContainer {
    /// Replaces `value` when `key` is present; otherwise leaves it alone.
    func update<T: Decodable>(_ value: inout T, _ key: Key) throws {
        if contains(key) {
            value = try decode(T.self, forKey: key)
        }
    }
}
