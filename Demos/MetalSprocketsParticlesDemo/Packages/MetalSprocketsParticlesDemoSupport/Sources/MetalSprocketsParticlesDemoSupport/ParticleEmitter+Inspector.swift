import ImageIO
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

    // MARK: Trails and ribbons

    var hasTrail: Bool {
        get { trail != nil }
        set { trail = newValue ? (trail ?? ParticleTrail()) : nil }
    }

    /// The trail, or the defaults when there is none. Setting it turns the trail on.
    var editableTrail: ParticleTrail {
        get { trail ?? ParticleTrail() }
        set { trail = newValue }
    }

    var hasRibbon: Bool {
        get { ribbon != nil }
        set { ribbon = newValue ? (ribbon ?? ParticleRibbon()) : nil }
    }

    var editableRibbon: ParticleRibbon {
        get { ribbon ?? ParticleRibbon() }
        set { ribbon = newValue }
    }

    // MARK: Color effects

    /// Starting gradients when a color effect is turned on: visible at once, easy to edit from.
    static let defaultSpeedGradient = ParticleCurve<SIMD4<Float>>.linear(from: [0.3, 0.5, 1, 1], to: [1, 0.6, 0.2, 1])
    static let defaultPositionGradient = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.3, 0.6, 1], to: [0.3, 0.9, 1, 1])

    var hasColorBySpeed: Bool {
        get { colorBySpeed != nil }
        set { colorBySpeed = newValue ? (colorBySpeed ?? Self.defaultSpeedGradient) : nil }
    }

    var editableColorBySpeed: ParticleCurve<SIMD4<Float>> {
        get { colorBySpeed ?? Self.defaultSpeedGradient }
        set { colorBySpeed = newValue }
    }

    /// The slowest end of `colorBySpeedRange`. Kept at or below the fastest.
    var colorBySpeedMinimum: Float {
        get { colorBySpeedRange.lowerBound }
        set { colorBySpeedRange = max(newValue, 0)...max(newValue, colorBySpeedRange.upperBound) }
    }

    /// The fastest end of `colorBySpeedRange`. Kept at or above the slowest.
    var colorBySpeedMaximum: Float {
        get { colorBySpeedRange.upperBound }
        set { colorBySpeedRange = min(colorBySpeedRange.lowerBound, max(newValue, 0))...max(newValue, 0) }
    }

    var hasAlternateColors: Bool {
        get { alternateColorOverLife != nil }
        set { alternateColorOverLife = newValue ? (alternateColorOverLife ?? colorOverLife) : nil }
    }

    /// The second gradient, or a copy of the first when there is none. Setting it turns alternate colors on.
    var editableAlternateColorOverLife: ParticleCurve<SIMD4<Float>> {
        get { alternateColorOverLife ?? colorOverLife }
        set { alternateColorOverLife = newValue }
    }

    var hasColorByPosition: Bool {
        get { colorByPosition != nil }
        set { colorByPosition = newValue ? (colorByPosition ?? Self.defaultPositionGradient) : nil }
    }

    var editableColorByPosition: ParticleCurve<SIMD4<Float>> {
        get { colorByPosition ?? Self.defaultPositionGradient }
        set { colorByPosition = newValue }
    }

    /// Whether the emitter has a color image. Turning it off removes the image; turning it on needs one chosen.
    var hasColorImage: Bool {
        get { colorImage != nil }
        set {
            if !newValue {
                colorImage = nil
            }
        }
    }

    /// The color image's placement, or a placeholder when there is none (edits then do nothing).
    var editableColorImage: ParticleColorImage {
        get { colorImage ?? ParticleColorImage(data: Data(), origin: .zero, width: [1, 0, 0], height: [0, 1, 0]) }
        set {
            if colorImage != nil {
                colorImage = newValue
            }
        }
    }

    /// Whether the emitter flocks. Turning it on starts from the library's defaults, or the settings it had.
    var isFlocking: Bool {
        get { flocking != nil }
        set { flocking = newValue ? (flocking ?? ParticleFlocking()) : nil }
    }

    /// The flocking settings, or the defaults when the emitter does not flock. Setting them turns flocking on.
    var editableFlocking: ParticleFlocking {
        get { flocking ?? ParticleFlocking() }
        set { flocking = newValue }
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

// MARK: - Trails

extension ParticleTrail {
    /// `pointCount` as a slider value, kept to 2...64 (the most the library records).
    var editablePointCount: Float {
        get { Float(pointCount) }
        set { pointCount = min(max(Int(newValue.rounded()), 2), 64) }
    }
}

// MARK: - Color image

extension ParticleColorImage {
    enum ChoiceError: LocalizedError {
        case notAnImage

        var errorDescription: String? {
            "The file is not an image."
        }
    }

    /// A new image's placement: where `existing` was, or upright in the XY plane at the origin, 4 units wide.
    static func choosing(data: Data, replacing existing: ParticleColorImage?) throws -> ParticleColorImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ChoiceError.notAnImage
        }
        if var existing {
            existing.data = data
            return existing
        }
        return ParticleColorImage(data: data, center: [0, 1.5, 0], size: 4)
    }
}

// MARK: - Flocking

extension ParticleFlocking {
    /// The slowest a flocking particle is kept. Kept at or below `maximumSpeed`.
    var minimumSpeed: Float {
        get { speedRange.lowerBound }
        set { speedRange = max(newValue, 0)...max(newValue, speedRange.upperBound) }
    }

    /// The fastest a flocking particle is kept. Kept at or above `minimumSpeed`.
    var maximumSpeed: Float {
        get { speedRange.upperBound }
        set { speedRange = min(speedRange.lowerBound, max(newValue, 0))...max(newValue, 0) }
    }

    /// `maxNeighbors` as a slider value, at least 1.
    var neighborLimit: Float {
        get { Float(maxNeighbors) }
        set { maxNeighbors = max(Int(newValue.rounded()), 1) }
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

    /// A distance field's turn about +Y (meshes are usually turned about the vertical); setting it replaces any other
    /// rotation. Other shapes ignore it.
    var turn: Float {
        get {
            if case let .signedDistanceField(_, _, rotation) = self {
                return rotation.angle * (rotation.axis.y < 0 ? -1 : 1)
            }
            return 0
        }
        set {
            if case let .signedDistanceField(field, center, _) = self {
                self = .signedDistanceField(field, center: center, rotation: simd_quatf(angle: newValue, axis: [0, 1, 0]))
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

// MARK: - Lights

extension ParticleEmitter {
    var emitsLight: Bool {
        get { light != nil }
        set { light = newValue ? (light ?? ParticleLightEmission()) : nil }
    }

    /// The particle lights, or the defaults when there are none. Setting them turns particle lights on.
    var editableLight: ParticleLightEmission {
        get { light ?? ParticleLightEmission() }
        set { light = newValue }
    }
}

extension ParticleLightEmission {
    /// `count` as a slider value, at least 1.
    var editableCount: Float {
        get { Float(count) }
        set { count = max(Int(newValue.rounded()), 1) }
    }
}

extension ParticleLight {
    /// Point (true) or directional (false). Switching keeps color and intensity.
    var isPoint: Bool {
        get {
            if case .point = self {
                return true
            }
            return false
        }
        set {
            guard newValue != isPoint else {
                return
            }
            self = newValue ? .point(position: [0, 2, 0], color: color, intensity: intensity, range: 6) : .directional(direction: [0, -1, 0], color: color, intensity: intensity)
        }
    }

    var color: SIMD3<Float> {
        get {
            switch self {
            case let .directional(_, color, _), let .point(_, color, _, _): color
            }
        }
        set {
            switch self {
            case let .directional(direction, _, intensity): self = .directional(direction: direction, color: newValue, intensity: intensity)
            case let .point(position, _, intensity, range): self = .point(position: position, color: newValue, intensity: intensity, range: range)
            }
        }
    }

    var intensity: Float {
        get {
            switch self {
            case let .directional(_, _, intensity), let .point(_, _, intensity, _): intensity
            }
        }
        set {
            switch self {
            case let .directional(direction, color, _): self = .directional(direction: direction, color: color, intensity: newValue)
            case let .point(position, color, _, range): self = .point(position: position, color: color, intensity: newValue, range: range)
            }
        }
    }

    /// The direction light travels; setting it on a point light does nothing.
    var direction: SIMD3<Float> {
        get {
            if case let .directional(direction, _, _) = self {
                return direction
            }
            return [0, -1, 0]
        }
        set {
            if case let .directional(_, color, intensity) = self {
                self = .directional(direction: newValue, color: color, intensity: intensity)
            }
        }
    }

    /// Where a point light is; setting it on a directional light does nothing.
    var position: SIMD3<Float> {
        get {
            if case let .point(position, _, _, _) = self {
                return position
            }
            return .zero
        }
        set {
            if case let .point(_, color, intensity, range) = self {
                self = .point(position: newValue, color: color, intensity: intensity, range: range)
            }
        }
    }

    /// A point light's falloff distance (0 for none); setting it on a directional light does nothing.
    var range: Float {
        get {
            if case let .point(_, _, _, range) = self {
                return range
            }
            return 0
        }
        set {
            if case let .point(position, color, intensity, _) = self {
                self = .point(position: position, color: color, intensity: intensity, range: newValue)
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

extension SIMD3 where Scalar == Float {
    /// Linear sRGB as a color, for color pickers. Values above 1 are clipped by the picker.
    var color: Color {
        get { Color(SIMD4(self, 1)) }
        set {
            let value = newValue.simd
            self = [value.x, value.y, value.z]
        }
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
