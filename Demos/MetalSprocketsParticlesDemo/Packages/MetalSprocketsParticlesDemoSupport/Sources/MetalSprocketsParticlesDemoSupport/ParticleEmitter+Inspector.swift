import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftUI

// Writable computed properties that let the inspector bind with key-path projections ($emitter.foo) instead of
// closure-based Binding adapters. Setters on properties that do not apply to the current case are ignored.

// MARK: - ParticleEmitter

extension ParticleEmitter {
    var lifetimeMinimum: Float {
        get { lifetime.lowerBound }
        set { lifetime = newValue...max(newValue, lifetime.upperBound) }
    }

    var lifetimeMaximum: Float {
        get { lifetime.upperBound }
        set { lifetime = min(lifetime.lowerBound, newValue)...newValue }
    }

    var hasLimitedEmission: Bool {
        get { emissionDuration != nil }
        set { emissionDuration = newValue ? (emissionDuration ?? 1) : nil }
    }

    /// The emission duration, or 1 when emission is unlimited. Setting it limits emission.
    var limitedEmissionDuration: Float {
        get { emissionDuration ?? 1 }
        set { emissionDuration = newValue }
    }

    var orientationKind: OrientationKind {
        get { OrientationKind(orientation) }
        set { orientation = newValue.orientation(stretch: velocityStretch) }
    }

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

    var hasImageSequence: Bool {
        get { imageSequence != nil }
        set { imageSequence = newValue ? (imageSequence ?? ImageSequence(rows: 2, columns: 2, frameRate: 4)) : nil }
    }

    /// The image sequence, or a 1×1 default when there is none. Setting it enables the sequence.
    var editableImageSequence: ImageSequence {
        get { imageSequence ?? ImageSequence() }
        set { imageSequence = newValue }
    }

    var shapeKind: ShapeKind {
        get { ShapeKind(shape) }
        set { shape = newValue.defaultShape(keeping: self) }
    }

    /// Radius of sphere, disc, cylinder, cone, and torus shapes.
    var shapeRadius: Float {
        get {
            switch shape {
            case let .sphere(radius), let .disc(radius), let .cylinder(radius, _), let .cone(radius, _), let .torus(radius, _): radius
            default: 0
            }
        }
        set {
            switch shape {
            case .sphere: shape = .sphere(radius: newValue)
            case .disc: shape = .disc(radius: newValue)
            case let .cylinder(_, height): shape = .cylinder(radius: newValue, height: height)
            case let .cone(_, height): shape = .cone(radius: newValue, height: height)
            case let .torus(_, tube): shape = .torus(radius: newValue, tubeRadius: tube)
            default: break
            }
        }
    }

    /// Height of cylinder and cone shapes; tube radius of a torus.
    var shapeSecondary: Float {
        get {
            switch shape {
            case let .cylinder(_, height), let .cone(_, height): height
            case let .torus(_, tube): tube
            default: 0
            }
        }
        set {
            switch shape {
            case let .cylinder(radius, _): shape = .cylinder(radius: radius, height: newValue)
            case let .cone(radius, _): shape = .cone(radius: radius, height: newValue)
            case let .torus(radius, _): shape = .torus(radius: radius, tubeRadius: newValue)
            default: break
            }
        }
    }

    /// Full size of box shapes (xyz) and plane shapes (xz).
    var shapeSize: SIMD3<Float> {
        get {
            switch shape {
            case let .box(size): size
            case let .plane(size): [size.x, 0, size.y]
            default: .zero
            }
        }
        set {
            switch shape {
            case .box: shape = .box(size: newValue)
            case .plane: shape = .plane(size: [newValue.x, newValue.z])
            default: break
            }
        }
    }
}

enum ShapeKind: String, CaseIterable, Identifiable {
    case point = "Point"
    case sphere = "Sphere"
    case box = "Box"
    case plane = "Plane"
    case disc = "Disc"
    case cylinder = "Cylinder"
    case cone = "Cone"
    case torus = "Torus"

    var id: Self { self }

    init(_ shape: EmitterShape) {
        switch shape {
        case .point, .mesh: self = .point
        case .sphere: self = .sphere
        case .box: self = .box
        case .plane: self = .plane
        case .disc: self = .disc
        case .cylinder: self = .cylinder
        case .cone: self = .cone
        case .torus: self = .torus
        }
    }

    /// A reasonable shape of this kind, reusing the emitter's current radius where it has one.
    func defaultShape(keeping emitter: ParticleEmitter) -> EmitterShape {
        let radius = emitter.shapeRadius > 0 ? emitter.shapeRadius : 0.5
        return switch self {
        case .point: .point
        case .sphere: .sphere(radius: radius)
        case .box: .box(size: [1, 1, 1])
        case .plane: .plane(size: [1, 1])
        case .disc: .disc(radius: radius)
        case .cylinder: .cylinder(radius: radius, height: 1)
        case .cone: .cone(radius: radius, height: 1)
        case .torus: .torus(radius: radius, tubeRadius: radius * 0.2)
        }
    }
}

enum OrientationKind: String, CaseIterable, Identifiable {
    case billboard = "Billboard"
    case yAligned = "Y-Aligned"
    case velocityAligned = "Velocity"
    case flat = "Flat"

    var id: Self { self }

    init(_ orientation: ParticleOrientation) {
        switch orientation {
        case .billboard: self = .billboard
        case .yAligned: self = .yAligned
        case .velocityAligned: self = .velocityAligned
        case .fixed: self = .flat
        }
    }

    func orientation(stretch: Float) -> ParticleOrientation {
        switch self {
        case .billboard: .billboard
        case .yAligned: .yAligned
        case .velocityAligned: .velocityAligned(stretch: stretch)
        case .flat: .fixed(normal: [0, 1, 0])
        }
    }
}

// MARK: - Colliders

enum ColliderKind: String, CaseIterable, Identifiable {
    case plane = "Plane"
    case sphere = "Sphere"
    case box = "Box"
    case capsule = "Capsule"

    var id: Self { self }
}

extension Collider {
    var kind: ColliderKind {
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
            let center = self.center
            self = switch newValue {
            case .plane: .plane(normal: [0, 1, 0], distance: center.y)
            case .sphere: .sphere(center: center, radius: 0.5)
            case .box: .box(center: center, halfExtents: [0.4, 0.4, 0.4])
            case .capsule: .capsule(start: center - [0.6, 0, 0], end: center + [0.6, 0, 0], radius: 0.25)
            }
        }
    }

    /// Plane: the point on the plane closest to the origin. Capsule: the segment midpoint.
    var center: SIMD3<Float> {
        get {
            switch self {
            case let .plane(normal, distance): simd_normalize(normal) * distance
            case let .sphere(center, _), let .box(center, _, _): center
            case let .capsule(start, end, _): (start + end) / 2
            }
        }
        set {
            switch self {
            case let .plane(normal, _): self = .plane(normal: normal, distance: simd_dot(newValue, simd_normalize(normal)))
            case let .sphere(_, radius): self = .sphere(center: newValue, radius: radius)
            case let .box(_, halfExtents, rotation): self = .box(center: newValue, halfExtents: halfExtents, rotation: rotation)
            case let .capsule(start, end, radius):
                let offset = newValue - (start + end) / 2
                self = .capsule(start: start + offset, end: end + offset, radius: radius)
            }
        }
    }

    var radius: Float {
        get {
            switch self {
            case let .sphere(_, radius), let .capsule(_, _, radius): radius
            default: 0
            }
        }
        set {
            switch self {
            case let .sphere(center, _): self = .sphere(center: center, radius: newValue)
            case let .capsule(start, end, _): self = .capsule(start: start, end: end, radius: newValue)
            default: break
            }
        }
    }

    /// Box full size.
    var size: SIMD3<Float> {
        get {
            if case let .box(_, halfExtents, _) = self {
                return halfExtents * 2
            }
            return .zero
        }
        set {
            if case let .box(center, _, rotation) = self {
                self = .box(center: center, halfExtents: newValue / 2, rotation: rotation)
            }
        }
    }

    /// Box rotation about z, in radians.
    var tilt: Float {
        get {
            if case let .box(_, _, rotation) = self {
                return rotation.angle * (rotation.axis.z < 0 ? -1 : 1)
            }
            return 0
        }
        set {
            if case let .box(center, halfExtents, _) = self {
                self = .box(center: center, halfExtents: halfExtents, rotation: simd_quatf(angle: newValue, axis: [0, 0, 1]))
            }
        }
    }

    /// Capsule length along its current direction.
    var length: Float {
        get {
            if case let .capsule(start, end, _) = self {
                return simd_distance(start, end)
            }
            return 0
        }
        set {
            if case let .capsule(start, end, radius) = self {
                let middle = (start + end) / 2
                let direction = simd_distance(start, end) > 0 ? simd_normalize(end - start) : SIMD3<Float>(1, 0, 0)
                self = .capsule(start: middle - direction * newValue / 2, end: middle + direction * newValue / 2, radius: radius)
            }
        }
    }
}

// MARK: - Force fields

enum ForceFieldKind: String, CaseIterable, Identifiable {
    case wind = "Wind"
    case attractor = "Attractor"
    case vortex = "Vortex"
    case turbulence = "Turbulence"

    var id: Self { self }
}

extension ForceField {
    var kind: ForceFieldKind {
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
            case .wind: .wind(velocity: [2, 0, 0], strength: 1)
            case .attractor: .attractor(center: [0, 1.5, 0], strength: 5, radius: 0)
            case .vortex: .vortex(center: .zero, strength: 5, radius: 2.5)
            case .turbulence: .turbulence(strength: 3, scale: 1.2, speed: 0.5)
            }
        }
    }

    var strength: Float {
        get {
            switch self {
            case let .wind(_, strength), let .attractor(_, strength, _), let .vortex(_, _, strength, _), let .turbulence(strength, _, _): strength
            }
        }
        set {
            switch self {
            case let .wind(velocity, _): self = .wind(velocity: velocity, strength: newValue)
            case let .attractor(center, _, radius): self = .attractor(center: center, strength: newValue, radius: radius)
            case let .vortex(center, axis, _, radius): self = .vortex(center: center, axis: axis, strength: newValue, radius: radius)
            case let .turbulence(_, scale, speed): self = .turbulence(strength: newValue, scale: scale, speed: speed)
            }
        }
    }

    /// Attractor and vortex center.
    var center: SIMD3<Float> {
        get {
            switch self {
            case let .attractor(center, _, _), let .vortex(center, _, _, _): center
            default: .zero
            }
        }
        set {
            switch self {
            case let .attractor(_, strength, radius): self = .attractor(center: newValue, strength: strength, radius: radius)
            case let .vortex(_, axis, strength, radius): self = .vortex(center: newValue, axis: axis, strength: strength, radius: radius)
            default: break
            }
        }
    }

    /// Attractor and vortex range; 0 is unlimited.
    var radius: Float {
        get {
            switch self {
            case let .attractor(_, _, radius), let .vortex(_, _, _, radius): radius
            default: 0
            }
        }
        set {
            switch self {
            case let .attractor(center, strength, _): self = .attractor(center: center, strength: strength, radius: newValue)
            case let .vortex(center, axis, strength, _): self = .vortex(center: center, axis: axis, strength: strength, radius: newValue)
            default: break
            }
        }
    }

    var windVelocity: SIMD3<Float> {
        get {
            if case let .wind(velocity, _) = self {
                return velocity
            }
            return .zero
        }
        set {
            if case let .wind(_, strength) = self {
                self = .wind(velocity: newValue, strength: strength)
            }
        }
    }

    var turbulenceScale: Float {
        get {
            if case let .turbulence(_, scale, _) = self {
                return scale
            }
            return 0
        }
        set {
            if case let .turbulence(strength, _, speed) = self {
                self = .turbulence(strength: strength, scale: newValue, speed: speed)
            }
        }
    }

    var turbulenceSpeed: Float {
        get {
            if case let .turbulence(_, _, speed) = self {
                return speed
            }
            return 0
        }
        set {
            if case let .turbulence(strength, scale, _) = self {
                self = .turbulence(strength: strength, scale: scale, speed: newValue)
            }
        }
    }
}

// MARK: - Colors

extension ParticleCurve.Keyframe where Value == SIMD4<Float> {
    var color: Color {
        get { Color(value) }
        set { value = newValue.simd }
    }
}

extension Color {
    init(_ color: SIMD4<Float>) {
        self.init(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
    }

    /// Linear sRGB components, matching the particle shaders.
    var simd: SIMD4<Float> {
        let resolved = resolve(in: EnvironmentValues())
        return [resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity]
    }
}

// MARK: - Shader enums

extension ParticleBlendMode: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [ParticleBlendMode] { [.alpha, .additive, .screen, .opaque] }
    public var id: UInt32 { rawValue }

    var name: String {
        switch self {
        case .additive: "Additive"
        case .screen: "Screen"
        case .opaque: "Opaque"
        default: "Alpha"
        }
    }
}

extension ParticleBirthLocation: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [ParticleBirthLocation] { [.volume, .surface] }
    public var id: UInt32 { rawValue }

    var name: String {
        self == .surface ? "Surface" : "Volume"
    }
}

extension ParticleBirthDirection: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [ParticleBirthDirection] { [.velocity, .normal, .tangent] }
    public var id: UInt32 { rawValue }

    var name: String {
        switch self {
        case .normal: "Shape Normal"
        case .tangent: "Around Axis"
        default: "Velocity"
        }
    }
}

extension ParticleImageSequenceMode: @retroactive CaseIterable, @retroactive Identifiable {
    public static var allCases: [ParticleImageSequenceMode] { [.repeat, .clamp, .autoReverse] }
    public var id: UInt32 { rawValue }

    var name: String {
        switch self {
        case .clamp: "Clamp"
        case .autoReverse: "Auto Reverse"
        default: "Repeat"
        }
    }
}

extension SimulationSpace: @retroactive Identifiable {
    public var id: Self { self }

    var name: String {
        self == .local ? "Local" : "World"
    }
}
