import simd

public enum SpawnModule: StageModule {
    case shape(ShapeModule)
    case rate(RateModule)
    case lifetime(LifetimeModule)
    case velocity(VelocityModule)
    case rotation(RotationModule)
    case variation(VariationModule)
    case colorImage(ColorImageModule)
    case function(SpawnFunctionModule)
    case stitched(StitchedSpawnModule)

    public static let types: [any ParticleModule.Type] = [
        ShapeModule.self, RateModule.self, LifetimeModule.self, VelocityModule.self, RotationModule.self, VariationModule.self,
        ColorImageModule.self, SpawnFunctionModule.self, StitchedSpawnModule.self,
    ]

    public init?(wrapping module: any ParticleModule) {
        switch module {
        case let module as ShapeModule: self = .shape(module)
        case let module as RateModule: self = .rate(module)
        case let module as LifetimeModule: self = .lifetime(module)
        case let module as VelocityModule: self = .velocity(module)
        case let module as RotationModule: self = .rotation(module)
        case let module as VariationModule: self = .variation(module)
        case let module as ColorImageModule: self = .colorImage(module)
        case let module as SpawnFunctionModule: self = .function(module)
        case let module as StitchedSpawnModule: self = .stitched(module)
        default: return nil
        }
    }

    public var module: any ParticleModule {
        switch self {
        case let .shape(module): module
        case let .rate(module): module
        case let .lifetime(module): module
        case let .velocity(module): module
        case let .rotation(module): module
        case let .variation(module): module
        case let .colorImage(module): module
        case let .function(module): module
        case let .stitched(module): module
        }
    }
}

/// Where particles are born and which way they head.
public struct ShapeModule: ParticleModule {
    public static let kind = "shape"
    public static let isRequired = true
    public var position: SIMD3<Float>
    public var shape: EmitterShape
    public var birthLocation: ParticleBirthLocation
    public var birthDirection: ParticleBirthDirection
    public var sweepAngle: Float

    public init(position: SIMD3<Float> = .zero, shape: EmitterShape = .sphere(radius: 0.05), birthLocation: ParticleBirthLocation = .volume, birthDirection: ParticleBirthDirection = .velocity, sweepAngle: Float = 2 * .pi) {
        self.position = position
        self.shape = shape
        self.birthLocation = birthLocation
        self.birthDirection = birthDirection
        self.sweepAngle = sweepAngle
    }
}

/// How many particles are born, and when.
public struct RateModule: ParticleModule {
    public static let kind = "rate"
    public static let isRequired = true
    public var birthRate: Float
    public var variation: Float
    public var emissionDuration: Float?
    public var idleDuration: Float
    public var loops: Bool
    public var warmupDuration: Float
    public var overTime: ParticleCurve<Float>

    public init(birthRate: Float = 1_000, variation: Float = 0, emissionDuration: Float? = nil, idleDuration: Float = 0, loops: Bool = true, warmupDuration: Float = 0, overTime: ParticleCurve<Float> = .constant(1)) {
        self.birthRate = birthRate
        self.variation = variation
        self.emissionDuration = emissionDuration
        self.idleDuration = idleDuration
        self.loops = loops
        self.warmupDuration = warmupDuration
        self.overTime = overTime
    }
}

/// How long particles live, in seconds.
public struct LifetimeModule: ParticleModule {
    public static let kind = "lifetime"
    public static let isRequired = true
    public var range: ClosedRange<Float>

    public init(range: ClosedRange<Float> = 1.5...3) {
        self.range = range
    }
}

/// Initial velocity.
public struct VelocityModule: ParticleModule {
    public static let kind = "velocity"
    public static let added: Self? = Self(velocity: [0, 2, 0], spread: 0.5)
    public var velocity: SIMD3<Float>
    public var spread: Float
    public var speedVariation: Float
    public var inherit: Float

    public init(velocity: SIMD3<Float>, spread: Float = 0, speedVariation: Float = 0, inherit: Float = 0) {
        self.velocity = velocity
        self.spread = spread
        self.speedVariation = speedVariation
        self.inherit = inherit
    }
}

/// Initial angle and spin.
public struct RotationModule: ParticleModule {
    public static let kind = "rotation"
    public static let added: Self? = Self(angleVariation: .pi, angularSpeed: 1)
    public var angle: Float
    public var angleVariation: Float
    public var angularSpeed: Float
    public var angularSpeedVariation: Float

    public init(angle: Float = 0, angleVariation: Float = 0, angularSpeed: Float = 0, angularSpeedVariation: Float = 0) {
        self.angle = angle
        self.angleVariation = angleVariation
        self.angularSpeed = angularSpeed
        self.angularSpeedVariation = angularSpeedVariation
    }
}

/// Per-particle random size and color offsets.
public struct VariationModule: ParticleModule {
    public static let kind = "variation"
    public static let added: Self? = Self(size: 0.2, color: [0.1, 0.1, 0.1, 0])
    public var size: Float
    public var color: SIMD4<Float>

    public init(size: Float = 0, color: SIMD4<Float> = .zero) {
        self.size = size
        self.color = color
    }
}

/// Multiplies color by an image laid over the world.
public struct ColorImageModule: ParticleModule {
    public static let kind = "colorImage"
    public var image: ParticleColorImage

    public init(image: ParticleColorImage) {
        self.image = image
    }
}

/// A user `[[visible]]` function run once per new particle.
public struct SpawnFunctionModule: ParticleModule {
    public static let kind = "function"
    public var function: ParticleFunction

    public init(function: ParticleFunction) {
        self.function = function
    }
}

/// A user `[[stitchable]]` module in the spawn stack. Lifting adds these separately, one per module.
public struct StitchedSpawnModule: ParticleModule {
    public static let kind = "stitched"
    /// Spawn modules run with a deltaTime of 0, so the template sets a value instead of integrating one.
    public static let added: Self? = Self(module: StitchedModule(source: """
    [[stitchable]] constant float4 *tint(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
        // A random tint per particle; parameters[0].x mixes it in.
        float hue = fract(float(particle.id) * 0.618034);
        particle.color.rgb = mix(float3(1), float3(hue, 1 - hue, 0.5), parameters[0].x);
        return parameters + 1;
    }
    """, name: "tint", parameters: [[0.5, 0, 0, 0]]))
    public var module: StitchedModule

    public init(module: StitchedModule) {
        self.module = module
    }
}
