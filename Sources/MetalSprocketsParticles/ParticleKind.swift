import MetalSprocketsParticlesShaders
import simd

/// The case of an enum with associated values, or a plain option enum, with a display name. Editors list `allCases`
/// and bind to a value's writable `kind`; setting `kind` converts the value to a sensible one of the new kind,
/// keeping what carries over (centers, radii, names).
public protocol ParticleKind: CaseIterable, Hashable, Identifiable, Sendable where AllCases == [Self] {
    var name: String { get }
}

public extension ParticleKind {
    var id: Self { self }
}

// MARK: - Option enums

extension ParticleBlendMode: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleBlendMode] { [.alpha, .additive, .screen, .opaque] }

    public var name: String {
        switch self {
        case .additive: "Additive"
        case .screen: "Screen"
        case .opaque: "Opaque"
        default: "Alpha"
        }
    }
}

extension ParticleBirthLocation: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleBirthLocation] { [.volume, .surface, .vertices] }

    public var name: String {
        switch self {
        case .surface: "Surface"
        case .vertices: "Vertices"
        default: "Volume"
        }
    }
}

extension ParticleBirthDirection: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleBirthDirection] { [.velocity, .normal, .tangent] }

    public var name: String {
        switch self {
        case .normal: "Shape Normal"
        case .tangent: "Around Axis"
        default: "Velocity"
        }
    }
}

extension ParticleImageSequenceMode: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleImageSequenceMode] { [.repeat, .clamp, .autoReverse] }

    public var name: String {
        switch self {
        case .clamp: "Clamp"
        case .autoReverse: "Auto Reverse"
        default: "Repeat"
        }
    }
}

extension SimulationSpace: Identifiable, ParticleKind {
    public var name: String {
        switch self {
        case .world: "World"
        case .local: "Local"
        }
    }
}

extension ParticleSortMode: ParticleKind {
    public var name: String { rawValue }
}

extension EmitterMotion.Kind: ParticleKind {
    public var name: String { rawValue }
}

extension ParticleSprite: ParticleKind {
    public var name: String { rawValue }
}

// MARK: - Emitter shape

extension ParticleEmitterShapeKind: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleEmitterShapeKind] { [.point, .sphere, .box, .plane, .disc, .cylinder, .cone, .torus, .mesh] }

    public var name: String {
        switch self {
        case .sphere: "Sphere"
        case .box: "Box"
        case .plane: "Plane"
        case .disc: "Disc"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .torus: "Torus"
        case .mesh: "Mesh"
        default: "Point"
        }
    }
}

public extension EmitterShape {
    /// Setting it makes a default shape of that kind, keeping the radius where both shapes have one.
    var kind: ParticleEmitterShapeKind {
        get {
            switch self {
            case .point: .point
            case .sphere: .sphere
            case .box: .box
            case .plane: .plane
            case .disc: .disc
            case .cylinder: .cylinder
            case .cone: .cone
            case .torus: .torus
            case .mesh: .mesh
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            let radius: Float = switch self {
            case let .sphere(radius), let .disc(radius), let .cylinder(radius, _), let .cone(radius, _), let .torus(radius, _): radius
            default: 0.5
            }
            self = switch newValue {
            case .sphere: .sphere(radius: radius)
            case .box: .box(size: [1, 1, 1])
            case .plane: .plane(size: [1, 1])
            case .disc: .disc(radius: radius)
            case .cylinder: .cylinder(radius: radius, height: 1)
            case .cone: .cone(radius: radius, height: 1)
            case .torus: .torus(radius: radius, tubeRadius: radius * 0.2)
            case .mesh: .mesh
            default: .point
            }
        }
    }
}

// MARK: - Orientation

extension ParticleOrientationMode: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleOrientationMode] { [.billboard, .yAligned, .velocityAligned, .fixed] }

    public var name: String {
        switch self {
        case .yAligned: "Y-Aligned"
        case .velocityAligned: "Velocity"
        case .fixed: "Flat"
        default: "Billboard"
        }
    }
}

public extension ParticleOrientation {
    /// Setting it to `.fixed` lies flat facing +Y; `.velocityAligned` starts with no stretch.
    var kind: ParticleOrientationMode {
        get { mode }
        set {
            guard newValue != kind else {
                return
            }
            self = switch newValue {
            case .yAligned: .yAligned
            case .velocityAligned: .velocityAligned(stretch: 0)
            case .fixed: .fixed(normal: [0, 1, 0])
            default: .billboard
            }
        }
    }
}

// MARK: - Colliders and force fields

extension ParticleColliderKind: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleColliderKind] { [.plane, .sphere, .box, .capsule] }

    public var name: String {
        switch self {
        case .sphere: "Sphere"
        case .box: "Box"
        case .capsule: "Capsule"
        default: "Plane"
        }
    }
}

public extension Collider {
    /// Setting it makes a default shape of that kind at the same center, keeping the category.
    var kind: ParticleColliderKind {
        get { shape.kind }
        set { shape.kind = newValue }
    }
}

public extension Collider.Shape {
    /// Setting it makes a default shape of that kind at the same center.
    var kind: ParticleColliderKind {
        get {
            switch self {
            case .plane: .plane
            case .sphere: .sphere
            case .box: .box
            case .capsule: .capsule
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            let center: SIMD3<Float> = switch self {
            case let .plane(normal, distance): simd_normalize(normal) * distance
            case let .sphere(center, _), let .box(center, _, _): center
            case let .capsule(start, end, _): (start + end) / 2
            }
            self = switch newValue {
            case .sphere: .sphere(center: center, radius: 0.5)
            case .box: .box(center: center, halfExtents: [0.4, 0.4, 0.4])
            case .capsule: .capsule(start: center - [0.6, 0, 0], end: center + [0.6, 0, 0], radius: 0.25)
            default: .plane(normal: [0, 1, 0], distance: center.y)
            }
        }
    }
}

extension ParticleForceFieldKind: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleForceFieldKind] { [.wind, .attractor, .vortex, .turbulence] }

    public var name: String {
        switch self {
        case .attractor: "Attractor"
        case .vortex: "Vortex"
        case .turbulence: "Turbulence"
        default: "Wind"
        }
    }
}

public extension ForceField {
    /// Setting it makes a default field of that kind, keeping the category.
    var kind: ParticleForceFieldKind {
        get { effect.kind }
        set { effect.kind = newValue }
    }
}

public extension ForceField.Effect {
    /// Setting it makes a default effect of that kind.
    var kind: ParticleForceFieldKind {
        get {
            switch self {
            case .wind: .wind
            case .attractor: .attractor
            case .vortex: .vortex
            case .turbulence: .turbulence
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            self = switch newValue {
            case .attractor: .attractor(center: [0, 1.5, 0], strength: 5, radius: 0)
            case .vortex: .vortex(center: .zero, strength: 5, radius: 2.5)
            case .turbulence: .turbulence(strength: 3, scale: 1.2, speed: 0.5)
            default: .wind(velocity: [2, 0, 0], strength: 1)
            }
        }
    }
}

// MARK: - Sub-emitters and triggers

extension ParticleSpawnOccasion: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleSpawnOccasion] { [.birth, .death, .collision, .whileAlive, .age, .enterVolume] }

    public var name: String {
        switch self {
        case .death: "On Death"
        case .collision: "On Collision"
        case .whileAlive: "While Alive"
        case .age: "At Age"
        case .enterVolume: "On Entering Volume"
        default: "On Birth"
        }
    }
}

public extension SubEmitter.Occasion {
    /// Setting it to `.whileAlive` starts with a 0.05 second interval, `.age` at 1 second, and `.enterVolume` with a
    /// half-meter sphere at y = 1.
    var kind: ParticleSpawnOccasion {
        get {
            switch self {
            case .onBirth: .birth
            case .onDeath: .death
            case .onCollision: .collision
            case .whileAlive: .whileAlive
            case .atAge: .age
            case .onEntering: .enterVolume
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            self = switch newValue {
            case .death: .onDeath
            case .collision: .onCollision
            case .whileAlive: .whileAlive(interval: 0.05)
            case .age: .atAge(seconds: 1)
            case .enterVolume: .onEntering(.sphere(center: [0, 1, 0], radius: 0.5))
            default: .onBirth
            }
        }
    }
}

extension ParticleTriggerVolumeKind: @retroactive CaseIterable, @retroactive Identifiable, ParticleKind {
    public static var allCases: [ParticleTriggerVolumeKind] { [.sphere, .box] }

    public var name: String {
        self == .box ? "Box" : "Sphere"
    }
}

public extension TriggerVolume {
    /// Setting it keeps the center; a box gets half extents equal to the sphere's radius and vice versa.
    var kind: ParticleTriggerVolumeKind {
        get {
            switch self {
            case .sphere: .sphere
            case .box: .box
            }
        }
        set {
            switch (self, newValue) {
            case let (.sphere(center, radius), .box):
                self = .box(center: center, halfExtents: SIMD3(repeating: radius))
            case let (.box(center, halfExtents), .sphere):
                self = .sphere(center: center, radius: halfExtents.max())
            default:
                break
            }
        }
    }
}

public extension EmissionTrigger.Condition {
    enum Kind: String, ParticleKind {
        case event = "Event"
        case after = "After"
        case every = "Every"
        case objectEnters = "Object Enters"
        case particlesEnter = "Particles Enter"
        case colliderHit = "Collider Hit"

        public var name: String { rawValue }
    }

    /// Setting it makes a default condition of that kind: event "boom", 1 second, or a half-unit sphere at (0, 1, 0).
    var kind: Kind {
        get {
            switch self {
            case .event: .event
            case .after: .after
            case .every: .every
            case .objectEnters: .objectEnters
            case .particlesEnter: .particlesEnter
            case .colliderHit: .colliderHit
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            let volume = TriggerVolume.sphere(center: [0, 1, 0], radius: 0.5)
            self = switch newValue {
            case .event: .event("boom")
            case .after: .after(seconds: 1)
            case .every: .every(seconds: 1)
            case .objectEnters: .objectEnters(name: "object", volume: volume)
            case .particlesEnter: .particlesEnter(volume: volume, count: 1)
            case .colliderHit: .colliderHit(index: 0, count: 1)
            }
        }
    }
}

public extension EmissionTrigger.Action {
    enum Kind: String, ParticleKind {
        case burst = "Burst"
        case start = "Start"
        case stop = "Stop"
        case restart = "Restart"

        public var name: String { rawValue }
    }

    /// Setting it to `.burst` starts at 100 particles.
    var kind: Kind {
        get {
            switch self {
            case .burst: .burst
            case .start: .start
            case .stop: .stop
            case .restart: .restart
            }
        }
        set {
            guard newValue != kind else {
                return
            }
            self = switch newValue {
            case .burst: .burst(100)
            case .start: .start
            case .stop: .stop
            case .restart: .restart
            }
        }
    }
}
