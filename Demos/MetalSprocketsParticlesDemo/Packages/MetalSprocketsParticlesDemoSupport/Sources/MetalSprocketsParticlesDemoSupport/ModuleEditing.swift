import Foundation
import MetalSprocketsParticles
import simd

// Editing adapters on module types (#203): values shaped for sliders and toggles.

extension EmitterShape {
    /// Radius of sphere, disc, cylinder, cone, and torus shapes.
    var radius: Float {
        get {
            switch self {
            case let .sphere(radius), let .disc(radius), let .cylinder(radius, _), let .cone(radius, _), let .torus(radius, _): radius
            default: 0
            }
        }
        set {
            switch self {
            case .sphere: self = .sphere(radius: newValue)
            case .disc: self = .disc(radius: newValue)
            case let .cylinder(_, height): self = .cylinder(radius: newValue, height: height)
            case let .cone(_, height): self = .cone(radius: newValue, height: height)
            case let .torus(_, tube): self = .torus(radius: newValue, tubeRadius: tube)
            default: break
            }
        }
    }

    /// Height of cylinder and cone shapes; tube radius of a torus.
    var secondary: Float {
        get {
            switch self {
            case let .cylinder(_, height), let .cone(_, height): height
            case let .torus(_, tube): tube
            default: 0
            }
        }
        set {
            switch self {
            case let .cylinder(radius, _): self = .cylinder(radius: radius, height: newValue)
            case let .cone(radius, _): self = .cone(radius: radius, height: newValue)
            case let .torus(radius, _): self = .torus(radius: radius, tubeRadius: newValue)
            default: break
            }
        }
    }

    /// Full size of box shapes (xyz) and plane shapes (xz).
    var size: SIMD3<Float> {
        get {
            switch self {
            case let .box(size): size
            case let .plane(size): [size.x, 0, size.y]
            default: .zero
            }
        }
        set {
            switch self {
            case .box: self = .box(size: newValue)
            case .plane: self = .plane(size: [newValue.x, newValue.z])
            default: break
            }
        }
    }
}

extension LifetimeModule {
    /// Shortest lifetime the inspector allows, so particles always live a little.
    static let minimumEditableLifetime: Float = 0.01

    /// The middle of the range. Changing it keeps the variation, narrowing it only when the shortest life would drop
    /// below `minimumEditableLifetime`.
    var average: Float {
        get { (range.lowerBound + range.upperBound) / 2 }
        set {
            let average = max(newValue, Self.minimumEditableLifetime)
            range = Self.range(average: average, variation: min(variation, average - Self.minimumEditableLifetime))
        }
    }

    /// Plus or minus seconds around `average`.
    var variation: Float {
        get { (range.upperBound - range.lowerBound) / 2 }
        set {
            let average = average
            range = Self.range(average: average, variation: min(max(newValue, 0), average - Self.minimumEditableLifetime))
        }
    }

    /// Clamped so float rounding cannot put the shortest life just under the minimum.
    private static func range(average: Float, variation: Float) -> ClosedRange<Float> {
        let lower = max(average - variation, minimumEditableLifetime)
        return lower...max(average + variation, lower)
    }
}

extension RateModule {
    var hasLimitedEmission: Bool {
        get { emissionDuration != nil }
        set { emissionDuration = newValue ? (emissionDuration ?? 1) : nil }
    }

    /// The emission duration, or 1 when emission is unlimited. Setting it limits emission.
    var limitedEmissionDuration: Float {
        get { emissionDuration ?? 1 }
        set { emissionDuration = newValue }
    }
}

extension EmitterModules {
    /// Live particles the birth rate and longest lifetime call for, when more than `capacity`; nil when they fit.
    /// Bursts and emission limits are not counted.
    func particlesNeeded(capacity: Int) -> Int? {
        var rate: Float = 0
        var longest: Float = 0
        for slot in spawn where slot.isEnabled {
            switch slot.module {
            case let .rate(module): rate = module.birthRate + max(module.variation, 0)
            case let .lifetime(module): longest = module.range.upperBound
            default: break
            }
        }
        let needed = Int((rate * longest).rounded(.up))
        return needed > capacity ? needed : nil
    }

    /// The enabled mesh module's mesh, or nil for sprites.
    var particleMesh: ParticleMesh? {
        for slot in render where slot.isEnabled {
            if case let .mesh(module) = slot.module {
                return module.mesh
            }
        }
        return nil
    }

    /// What particles are drawn as. Setting it adds, changes, or removes the mesh module; a custom mesh is only kept.
    var drawing: ParticleDrawing {
        get {
            switch particleMesh {
            case nil: .sprite
            case .cube: .cube
            case .tetrahedron: .tetrahedron
            case .coin: .coin
            case .triangles: .custom
            }
        }
        set {
            let mesh: ParticleMesh?
            switch newValue {
            case .sprite: mesh = nil
            case .cube: mesh = .cube
            case .tetrahedron: mesh = .tetrahedron
            case .coin: mesh = .coin
            case .custom: return
            }
            render.removeAll { if case .mesh = $0.module { true } else { false } }
            if let mesh {
                render.append(ModuleSlot(.mesh(MeshModule(mesh: mesh))))
            }
        }
    }
}

extension SpriteModule {
    /// Stretch for `.velocityAligned`; 0 for other orientations. Setting it switches to `.velocityAligned`.
    var velocityStretch: Float {
        get {
            if case let .velocityAligned(stretch) = orientation {
                return stretch
            }
            return 0
        }
        set { orientation = .velocityAligned(stretch: newValue) }
    }
}

extension ColorOverLifeModule {
    var hasAlternateColors: Bool {
        get { alternate != nil }
        set { alternate = newValue ? (alternate ?? color) : nil }
    }

    /// The second gradient, or a copy of the first when there is none. Setting it turns alternate colors on.
    var editableAlternate: ParticleCurve<SIMD4<Float>> {
        get { alternate ?? color }
        set { alternate = newValue }
    }
}

extension ColorBySpeedModule {
    static let defaultGradient = ParticleCurve<SIMD4<Float>>.linear(from: [0.3, 0.5, 1, 1], to: [1, 0.6, 0.2, 1])

    var editableCurve: ParticleCurve<SIMD4<Float>> {
        get { curve ?? Self.defaultGradient }
        set { curve = newValue }
    }

    /// The slowest end of `range`. Kept at or below the fastest.
    var minimum: Float {
        get { range.lowerBound }
        set { range = max(newValue, 0)...max(newValue, range.upperBound) }
    }

    /// The fastest end of `range`. Kept at or above the slowest.
    var maximum: Float {
        get { range.upperBound }
        set { range = min(range.lowerBound, max(newValue, 0))...max(newValue, 0) }
    }
}

extension ColorByPositionModule {
    static let defaultGradient = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.3, 0.6, 1], to: [0.3, 0.9, 1, 1])

    var editableCurve: ParticleCurve<SIMD4<Float>> {
        get { curve ?? Self.defaultGradient }
        set { curve = newValue }
    }
}

extension ParticleMesh {
    var label: String {
        switch self {
        case .cube: "Cube"
        case .tetrahedron: "Tetrahedron"
        case .coin: "Coin"
        case .triangles: "Custom Mesh"
        }
    }
}
