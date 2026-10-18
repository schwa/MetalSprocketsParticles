import simd

/// One part of a particle system written with `ParticleSystemBuilder`.
public enum ParticleSystemComponent: Sendable {
    case layer(EmitterDescription)
    case collider(Collider)
    case forceField(ForceField)
    case light(ParticleLight)
    case trackedObject(name: String, motion: EmitterMotion)
}

/// A tracked object in a particle system builder: a stand-in for an app object that moves along `motion`.
public struct TrackedObject: Sendable {
    public var name: String
    public var motion: EmitterMotion

    public init(_ name: String, motion: EmitterMotion) {
        self.name = name
        self.motion = motion
    }
}

/// Builds a particle system's emitters, colliders, force fields, lights, and tracked objects from a list, in any order, with
/// `if`, `switch`, `for`, and optionals:
///
///     ParticleSystem("Sparks") {
///         EmitterDescription("Sparks", settings: sparks)
///         Collider.plane(normal: [0, 1, 0], distance: 0)
///         if windy {
///             ForceField.wind(velocity: [2, 0, 0], strength: 1)
///         }
///     }
@resultBuilder
public enum ParticleSystemBuilder {
    public static func buildExpression(_ layer: EmitterDescription) -> [ParticleSystemComponent] {
        [.layer(layer)]
    }

    public static func buildExpression(_ collider: Collider) -> [ParticleSystemComponent] {
        [.collider(collider)]
    }

    public static func buildExpression(_ field: ForceField) -> [ParticleSystemComponent] {
        [.forceField(field)]
    }

    public static func buildExpression(_ light: ParticleLight) -> [ParticleSystemComponent] {
        [.light(light)]
    }

    public static func buildExpression(_ object: TrackedObject) -> [ParticleSystemComponent] {
        [.trackedObject(name: object.name, motion: object.motion)]
    }

    public static func buildExpression(_ components: [ParticleSystemComponent]) -> [ParticleSystemComponent] {
        components
    }

    public static func buildBlock(_ components: [ParticleSystemComponent]...) -> [ParticleSystemComponent] {
        components.flatMap(\.self)
    }

    // The result builder protocol fixes this signature.
    // swiftlint:disable:next discouraged_optional_collection
    public static func buildOptional(_ components: [ParticleSystemComponent]?) -> [ParticleSystemComponent] {
        components ?? []
    }

    public static func buildEither(first components: [ParticleSystemComponent]) -> [ParticleSystemComponent] {
        components
    }

    public static func buildEither(second components: [ParticleSystemComponent]) -> [ParticleSystemComponent] {
        components
    }

    public static func buildArray(_ components: [[ParticleSystemComponent]]) -> [ParticleSystemComponent] {
        components.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ components: [ParticleSystemComponent]) -> [ParticleSystemComponent] {
        components
    }
}

public extension ParticleSystem {
    /// A particle system from a list of layers, colliders, force fields, lights, and tracked objects, kept in the order written
    /// within each kind.
    init(
        _ name: String,
        animatesColliders: Bool = false,
        ambientLight: SIMD3<Float> = [0.25, 0.25, 0.25],
        cameraEye: SIMD3<Float> = [0, 3, 6],
        cameraTarget: SIMD3<Float> = [0, 1.5, 0],
        @ParticleSystemBuilder content: () -> [ParticleSystemComponent]
    ) {
        var layers: [Layer] = []
        var colliders: [Collider] = []
        var forceFields: [ForceField] = []
        var lights: [ParticleLight] = []
        var trackedObjects: [String: EmitterMotion] = [:]
        for component in content() {
            switch component {
            case let .layer(layer): layers.append(layer)
            case let .collider(collider): colliders.append(collider)
            case let .forceField(field): forceFields.append(field)
            case let .light(light): lights.append(light)
            case let .trackedObject(name, motion): trackedObjects[name] = motion
            }
        }
        self.init(
            name,
            layers: layers,
            colliders: colliders,
            animatesColliders: animatesColliders,
            forceFields: forceFields,
            lights: lights,
            ambientLight: ambientLight,
            trackedObjects: trackedObjects,
            cameraEye: cameraEye,
            cameraTarget: cameraTarget
        )
    }
}
