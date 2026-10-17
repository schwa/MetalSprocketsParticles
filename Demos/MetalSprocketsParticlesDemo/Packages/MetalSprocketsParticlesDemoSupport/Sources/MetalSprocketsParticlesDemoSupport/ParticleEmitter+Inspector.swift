import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftUI

// Writable computed properties that let the inspector bind with key-path projections ($emitter.foo) instead of
// closure-based Binding adapters.

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

    var launchSpeed: Float {
        get { velocity.y }
        set { velocity.y = newValue }
    }

    var gravityY: Float {
        get { gravity.y }
        set { gravity.y = newValue }
    }

    var hueVariation: Float {
        get { colorVariation.x }
        set { colorVariation.x = newValue }
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
}

extension [ForceField] {
    var turbulenceStrength: Float {
        get { strength(of: .turbulence) }
        set { setStrength(newValue, of: .turbulence) }
    }

    var vortexStrength: Float {
        get { strength(of: .vortex) }
        set { setStrength(newValue, of: .vortex) }
    }

    enum FieldKind {
        case turbulence
        case vortex
    }

    private func strength(of kind: FieldKind) -> Float {
        for field in self {
            switch (kind, field) {
            case let (.turbulence, .turbulence(strength, _, _)), let (.vortex, .vortex(_, _, strength, _)):
                return strength
            default:
                continue
            }
        }
        return 0
    }

    /// Replaces the first field of `kind`, adds one if missing, and removes it when `strength` is 0.
    private mutating func setStrength(_ strength: Float, of kind: FieldKind) {
        let index = firstIndex { field in
            switch (kind, field) {
            case (.turbulence, .turbulence), (.vortex, .vortex): true
            default: false
            }
        }
        let field: ForceField = switch kind {
        case .turbulence: .turbulence(strength: strength, scale: 1.2, speed: 0.5)
        case .vortex: .vortex(center: .zero, strength: strength, radius: 2.5)
        }
        switch (index, strength == 0) {
        case let (index?, true): remove(at: index)
        case let (index?, false): self[index] = field
        case (nil, false): append(field)
        case (nil, true): break
        }
    }
}

enum OrientationKind: String, CaseIterable, Identifiable {
    case billboard = "Billboard"
    case yAligned = "Y-Aligned"
    case velocityAligned = "Velocity"

    var id: Self { self }

    init(_ orientation: ParticleOrientation) {
        switch orientation {
        case .yAligned: self = .yAligned
        case .velocityAligned: self = .velocityAligned
        default: self = .billboard
        }
    }

    func orientation(stretch: Float) -> ParticleOrientation {
        switch self {
        case .billboard: .billboard
        case .yAligned: .yAligned
        case .velocityAligned: .velocityAligned(stretch: stretch)
        }
    }
}

extension ParticleCurve where Value == SIMD4<Float> {
    var startColor: Color {
        get { Color(start) }
        set { start = newValue.simd }
    }

    var endColor: Color {
        get { Color(end) }
        set { end = newValue.simd }
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
