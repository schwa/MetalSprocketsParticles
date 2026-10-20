public enum RenderModule: StageModule {
    case sprite(SpriteModule)
    case foil(FoilModule)
    case mesh(MeshModule)
    case trail(TrailModule)
    case ribbon(RibbonModule)
    case light(LightModule)
    case levelOfDetail(LevelOfDetailModule)

    public static let types: [any ParticleModule.Type] = [
        SpriteModule.self, FoilModule.self, MeshModule.self, TrailModule.self, RibbonModule.self, LightModule.self, LevelOfDetailModule.self,
    ]

    public init?(wrapping module: any ParticleModule) {
        switch module {
        case let module as SpriteModule: self = .sprite(module)
        case let module as FoilModule: self = .foil(module)
        case let module as MeshModule: self = .mesh(module)
        case let module as TrailModule: self = .trail(module)
        case let module as RibbonModule: self = .ribbon(module)
        case let module as LightModule: self = .light(module)
        case let module as LevelOfDetailModule: self = .levelOfDetail(module)
        default: return nil
        }
    }

    public var module: any ParticleModule {
        switch self {
        case let .sprite(module): module
        case let .foil(module): module
        case let .mesh(module): module
        case let .trail(module): module
        case let .ribbon(module): module
        case let .light(module): module
        case let .levelOfDetail(module): module
        }
    }
}

/// How each particle is drawn.
public struct SpriteModule: ParticleModule {
    public static let kind = "sprite"
    public static let isRequired = true
    public var blendMode: ParticleBlendMode
    public var sortMode: ParticleSortMode
    public var orientation: ParticleOrientation
    public var softness: Float
    public var isLit: Bool
    public var minimumScreenSize: Float

    public init(blendMode: ParticleBlendMode = .alpha, sortMode: ParticleSortMode = .none, orientation: ParticleOrientation = .billboard, softness: Float = 0, isLit: Bool = false, minimumScreenSize: Float = 0) {
        self.blendMode = blendMode
        self.sortMode = sortMode
        self.orientation = orientation
        self.softness = softness
        self.isLit = isLit
        self.minimumScreenSize = minimumScreenSize
    }

    public init?(lifting emitter: ParticleEmitter) {
        self.init(blendMode: emitter.blendMode, sortMode: emitter.sortMode, orientation: emitter.orientation, softness: emitter.softness, isLit: emitter.isLit, minimumScreenSize: emitter.minimumScreenSize)
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.blendMode = blendMode
        emitter.sortMode = sortMode
        emitter.orientation = orientation
        emitter.softness = softness
        emitter.isLit = isLit
        emitter.minimumScreenSize = minimumScreenSize
    }
}

public struct FoilModule: ParticleModule {
    public static let kind = "foil"
    public static let added: Self? = Self(foil: ParticleFoil())
    public var foil: ParticleFoil

    public init(foil: ParticleFoil) {
        self.foil = foil
    }

    public init?(lifting emitter: ParticleEmitter) {
        guard let foil = emitter.foil else {
            return nil
        }
        self.foil = foil
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.foil = foil
    }
}

public struct MeshModule: ParticleModule {
    public static let kind = "mesh"
    public var mesh: ParticleMesh

    public init(mesh: ParticleMesh) {
        self.mesh = mesh
    }

    public init?(lifting emitter: ParticleEmitter) {
        guard let mesh = emitter.particleMesh else {
            return nil
        }
        self.mesh = mesh
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.particleMesh = mesh
    }
}

public struct TrailModule: ParticleModule {
    public static let kind = "trail"
    public static let added: Self? = Self(trail: ParticleTrail())
    public var trail: ParticleTrail

    public init(trail: ParticleTrail) {
        self.trail = trail
    }

    public init?(lifting emitter: ParticleEmitter) {
        guard let trail = emitter.trail else {
            return nil
        }
        self.trail = trail
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.trail = trail
    }
}

public struct RibbonModule: ParticleModule {
    public static let kind = "ribbon"
    public static let added: Self? = Self(ribbon: ParticleRibbon())
    public var ribbon: ParticleRibbon

    public init(ribbon: ParticleRibbon) {
        self.ribbon = ribbon
    }

    public init?(lifting emitter: ParticleEmitter) {
        guard let ribbon = emitter.ribbon else {
            return nil
        }
        self.ribbon = ribbon
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.ribbon = ribbon
    }
}

public struct LightModule: ParticleModule {
    public static let kind = "light"
    public static let added: Self? = Self(light: ParticleLightEmission())
    public var light: ParticleLightEmission

    public init(light: ParticleLightEmission) {
        self.light = light
    }

    public init?(lifting emitter: ParticleEmitter) {
        guard let light = emitter.light else {
            return nil
        }
        self.light = light
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.light = light
    }
}

/// Fewer, or no, particles far from the camera.
public struct LevelOfDetailModule: ParticleModule {
    public static let kind = "levelOfDetail"
    public static let added: Self? = Self(near: 5, far: 20)
    public var near: Float
    public var far: Float
    public var farRateScale: Float
    public var scalesSize: Bool
    public var cullingRadius: Float
    public var simulatesWhenCulled: Bool

    public init(near: Float = 0, far: Float = 0, farRateScale: Float = 0.25, scalesSize: Bool = false, cullingRadius: Float = 0, simulatesWhenCulled: Bool = true) {
        self.near = near
        self.far = far
        self.farRateScale = farRateScale
        self.scalesSize = scalesSize
        self.cullingRadius = cullingRadius
        self.simulatesWhenCulled = simulatesWhenCulled
    }

    public init?(lifting emitter: ParticleEmitter) {
        self.init(near: emitter.lodNearDistance, far: emitter.lodFarDistance, farRateScale: emitter.lodFarRateScale, scalesSize: emitter.lodScalesSize, cullingRadius: emitter.cullingRadius, simulatesWhenCulled: emitter.simulatesWhenCulled)
        guard self != Self() else {
            return nil
        }
    }

    public func apply(to emitter: inout ParticleEmitter) {
        emitter.lodNearDistance = near
        emitter.lodFarDistance = far
        emitter.lodFarRateScale = farRateScale
        emitter.lodScalesSize = scalesSize
        emitter.cullingRadius = cullingRadius
        emitter.simulatesWhenCulled = simulatesWhenCulled
    }
}
