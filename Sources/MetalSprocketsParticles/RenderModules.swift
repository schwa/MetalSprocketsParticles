public enum RenderModule: StageModule {
    case sprite(SpriteModule)
    case colorOverLife(ColorOverLifeModule)
    case sizeOverLife(SizeOverLifeModule)
    case colorBySpeed(ColorBySpeedModule)
    case colorByPosition(ColorByPositionModule)
    case imageSequence(ImageSequenceModule)
    case shading(ShadingModule)
    case mesh(MeshModule)
    case trail(TrailModule)
    case ribbon(RibbonModule)
    case light(LightModule)
    case levelOfDetail(LevelOfDetailModule)

    public static let types: [any ParticleModule.Type] = [
        SpriteModule.self, ColorOverLifeModule.self, SizeOverLifeModule.self, ColorBySpeedModule.self, ColorByPositionModule.self,
        ImageSequenceModule.self, ShadingModule.self, MeshModule.self, TrailModule.self, RibbonModule.self, LightModule.self, LevelOfDetailModule.self,
    ]

    public init?(wrapping module: any ParticleModule) {
        switch module {
        case let module as SpriteModule: self = .sprite(module)
        case let module as ColorOverLifeModule: self = .colorOverLife(module)
        case let module as SizeOverLifeModule: self = .sizeOverLife(module)
        case let module as ColorBySpeedModule: self = .colorBySpeed(module)
        case let module as ColorByPositionModule: self = .colorByPosition(module)
        case let module as ImageSequenceModule: self = .imageSequence(module)
        case let module as ShadingModule: self = .shading(module)
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
        case let .colorOverLife(module): module
        case let .sizeOverLife(module): module
        case let .colorBySpeed(module): module
        case let .colorByPosition(module): module
        case let .imageSequence(module): module
        case let .shading(module): module
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
    public var minimumScreenSize: Float

    public init(blendMode: ParticleBlendMode = .alpha, sortMode: ParticleSortMode = .none, orientation: ParticleOrientation = .billboard, softness: Float = 0, minimumScreenSize: Float = 0) {
        self.blendMode = blendMode
        self.sortMode = sortMode
        self.orientation = orientation
        self.softness = softness
        self.minimumScreenSize = minimumScreenSize
    }
}

public struct MeshModule: ParticleModule {
    public static let kind = "mesh"
    public var mesh: ParticleMesh

    public init(mesh: ParticleMesh) {
        self.mesh = mesh
    }
}

public struct TrailModule: ParticleModule {
    public static let kind = "trail"
    public static let added: Self? = Self(trail: ParticleTrail())
    public var trail: ParticleTrail

    public init(trail: ParticleTrail) {
        self.trail = trail
    }
}

public struct RibbonModule: ParticleModule {
    public static let kind = "ribbon"
    public static let added: Self? = Self(ribbon: ParticleRibbon())
    public var ribbon: ParticleRibbon

    public init(ribbon: ParticleRibbon) {
        self.ribbon = ribbon
    }
}

public struct LightModule: ParticleModule {
    public static let kind = "light"
    public static let added: Self? = Self(light: ParticleLightEmission())
    public var light: ParticleLightEmission

    public init(light: ParticleLightEmission) {
        self.light = light
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
}
