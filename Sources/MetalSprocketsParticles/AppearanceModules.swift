import simd

// Appearance modules: evaluated when drawing, from each particle's age, speed, and position, so they are in the render
// stage. Their colors multiply, so their order does not matter.

public struct ColorOverLifeModule: ParticleModule {
    public static let kind = "colorOverLife"
    public static let isRequired = true
    public var color: ParticleCurve<SIMD4<Float>>
    public var opacity: ParticleCurve<Float>
    /// Half the particles use this instead of `color`.
    public var alternate: ParticleCurve<SIMD4<Float>>?

    public init(color: ParticleCurve<SIMD4<Float>>, opacity: ParticleCurve<Float> = .constant(1), alternate: ParticleCurve<SIMD4<Float>>? = nil) {
        self.color = color
        self.opacity = opacity
        self.alternate = alternate
    }
}

public struct SizeOverLifeModule: ParticleModule {
    public static let kind = "sizeOverLife"
    public static let isRequired = true
    public var curve: ParticleCurve<Float>

    public init(curve: ParticleCurve<Float>) {
        self.curve = curve
    }
}

public struct ColorBySpeedModule: ParticleModule {
    public static let kind = "colorBySpeed"
    public static let added: Self? = Self(curve: .linear(from: [0.2, 0.4, 1, 1], to: [1, 0.3, 0.1, 1]), range: 0...5)
    public var curve: ParticleCurve<SIMD4<Float>>?
    public var range: ClosedRange<Float>

    public init(curve: ParticleCurve<SIMD4<Float>>?, range: ClosedRange<Float> = 0...5) {
        self.curve = curve
        self.range = range
    }
}

public struct ColorByPositionModule: ParticleModule {
    public static let kind = "colorByPosition"
    public static let added: Self? = Self(curve: .linear(from: [1, 0.2, 0.2, 1], to: [0.2, 0.2, 1, 1]), start: [0, 0, 0], end: [0, 2, 0])
    public var curve: ParticleCurve<SIMD4<Float>>?
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    /// Sample once where the particle is born instead of every step.
    public var atBirth: Bool

    public init(curve: ParticleCurve<SIMD4<Float>>?, start: SIMD3<Float> = [0, 0, 0], end: SIMD3<Float> = [0, 1, 0], atBirth: Bool = false) {
        self.curve = curve
        self.start = start
        self.end = end
        self.atBirth = atBirth
    }
}

public struct ImageSequenceModule: ParticleModule {
    public static let kind = "imageSequence"
    public static let added: Self? = Self(sequence: ImageSequence(rows: 2, columns: 2))
    public var sequence: ImageSequence

    public init(sequence: ImageSequence) {
        self.sequence = sequence
    }
}
