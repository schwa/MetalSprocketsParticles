import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftUI

// Writable computed properties that let the inspector bind with key-path projections ($emitter.foo) instead of
// closure-based Binding adapters. Setters on properties that do not apply to the current case are ignored. Switching
// between cases uses the library's writable `kind` properties (see ParticleKind).

// MARK: - ParticleEmitter

extension EmitterDescription {
    /// `capacity`, at least 1. There is no upper limit here: the GPU's largest buffer is the real one, and the model
    /// reports a capacity it cannot allocate and puts the last one back.
    var editableCapacity: Int {
        get { capacity }
        set { capacity = max(newValue, 1) }
    }
}

extension ParticleEmitter {
    /// Live particles the birth rate and longest lifetime call for, when more than `capacity`; nil when they fit. Bursts
    /// and emission limits are not counted.
    func particlesNeeded(capacity: Int) -> Int? {
        let needed = Int(((birthRate + max(birthRateVariation, 0)) * lifetime.upperBound).rounded(.up))
        return needed > capacity ? needed : nil
    }

    /// Shortest lifetime the inspector allows, so particles always live a little.
    static let minimumEditableLifetime: Float = 0.01

    /// The middle of the lifetime range. Changing it keeps the variation, narrowing it only when the shortest life
    /// would drop below `minimumEditableLifetime`.
    var lifetimeAverage: Float {
        get { (lifetime.lowerBound + lifetime.upperBound) / 2 }
        set {
            let average = max(newValue, Self.minimumEditableLifetime)
            let variation = min(lifetimeVariation, average - Self.minimumEditableLifetime)
            lifetime = Self.lifetimeRange(average: average, variation: variation)
        }
    }

    /// Plus or minus seconds around `lifetimeAverage`.
    var lifetimeVariation: Float {
        get { (lifetime.upperBound - lifetime.lowerBound) / 2 }
        set {
            let average = lifetimeAverage
            let variation = min(max(newValue, 0), average - Self.minimumEditableLifetime)
            lifetime = Self.lifetimeRange(average: average, variation: variation)
        }
    }

    /// Clamped so float rounding cannot put the shortest life just under the minimum.
    private static func lifetimeRange(average: Float, variation: Float) -> ClosedRange<Float> {
        let lower = max(average - variation, minimumEditableLifetime)
        return lower...max(average + variation, lower)
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

// MARK: - Colliders

extension Collider.Shape {
    /// Plane: the point on the plane closest to the origin. Capsule: the segment midpoint.
    var center: SIMD3<Float> {
        get {
            switch self {
            case let .plane(normal, distance): simd_normalize(normal) * distance
            case let .sphere(center, _), let .box(center, _, _), let .signedDistanceField(_, center, _): center
            case let .capsule(start, end, _): (start + end) / 2
            }
        }
        set {
            switch self {
            case let .plane(normal, _): self = .plane(normal: normal, distance: simd_dot(newValue, simd_normalize(normal)))
            case let .sphere(_, radius): self = .sphere(center: newValue, radius: radius)
            case let .box(_, halfExtents, rotation): self = .box(center: newValue, halfExtents: halfExtents, rotation: rotation)
            case let .signedDistanceField(field, _, rotation): self = .signedDistanceField(field, center: newValue, rotation: rotation)
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

extension ForceField.Effect {
    var strength: Float {
        get {
            switch self {
            case let .wind(_, strength), let .attractor(_, strength, _), let .vortex(_, _, strength, _), let .turbulence(strength, _, _),
                 let .path(_, _, strength, _, _): strength
            }
        }
        set {
            switch self {
            case let .wind(velocity, _): self = .wind(velocity: velocity, strength: newValue)
            case let .attractor(center, _, radius): self = .attractor(center: center, strength: newValue, radius: radius)
            case let .vortex(center, axis, _, radius): self = .vortex(center: center, axis: axis, strength: newValue, radius: radius)
            case let .turbulence(_, scale, speed): self = .turbulence(strength: newValue, scale: scale, speed: speed)
            case let .path(points, speed, _, radius, closed): self = .path(points: points, speed: speed, strength: newValue, radius: radius, closed: closed)
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
