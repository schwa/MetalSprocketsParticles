import MetalSprocketsParticlesShaders
import simd

/// A force applied to particles each step, in addition to gravity and drag. Only emitters whose
/// `ParticleEmitter.fieldMask` shares a bit with `categoryBitMask` feel it.
public struct ForceField: Sendable, Equatable {
    public enum Effect: Sendable, Equatable, Codable {
        /// Pulls particle velocity toward `velocity`. `strength` is per second: higher catches up faster.
        case wind(velocity: SIMD3<Float>, strength: Float)
        /// Constant acceleration toward `center`; negative `strength` repels. `radius` 0 means unlimited range.
        case attractor(center: SIMD3<Float>, strength: Float, radius: Float = 0)
        /// Swirls particles around the line through `center` along `axis`. Positive `strength` turns counterclockwise
        /// looking down `axis`. `radius` 0 means unlimited range.
        case vortex(center: SIMD3<Float>, axis: SIMD3<Float> = [0, 1, 0], strength: Float, radius: Float = 0)
        /// Curl-noise turbulence. `scale` is noise frequency per world unit; `speed` animates the pattern over time.
        case turbulence(strength: Float, scale: Float = 1, speed: Float = 0)
        /// Moves particles along a smooth curve through `points`: at `speed` along it, pulled onto it at `strength` per
        /// second. `radius` 0 means unlimited range. `closed` joins the last point back to the first.
        case path(points: [SIMD3<Float>], speed: Float, strength: Float = 4, radius: Float = 0, closed: Bool = false) // swiftlint:disable:this enum_case_associated_values_count
    }

    public var effect: Effect
    /// All bits by default, so every emitter feels it.
    public var categoryBitMask: UInt32

    public init(_ effect: Effect, categoryBitMask: UInt32 = .max) {
        self.effect = effect
        self.categoryBitMask = categoryBitMask
    }

    public static func wind(velocity: SIMD3<Float>, strength: Float, categoryBitMask: UInt32 = .max) -> Self {
        Self(.wind(velocity: velocity, strength: strength), categoryBitMask: categoryBitMask)
    }

    public static func attractor(center: SIMD3<Float>, strength: Float, radius: Float = 0, categoryBitMask: UInt32 = .max) -> Self {
        Self(.attractor(center: center, strength: strength, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func vortex(
        center: SIMD3<Float>,
        axis: SIMD3<Float> = [0, 1, 0],
        strength: Float,
        radius: Float = 0,
        categoryBitMask: UInt32 = .max
    ) -> Self {
        Self(.vortex(center: center, axis: axis, strength: strength, radius: radius), categoryBitMask: categoryBitMask)
    }

    public static func turbulence(strength: Float, scale: Float = 1, speed: Float = 0, categoryBitMask: UInt32 = .max) -> Self {
        Self(.turbulence(strength: strength, scale: scale, speed: speed), categoryBitMask: categoryBitMask)
    }

    public static func path(
        points: [SIMD3<Float>],
        speed: Float,
        strength: Float = 4,
        radius: Float = 0,
        closed: Bool = false,
        categoryBitMask: UInt32 = .max
    ) -> Self {
        Self(.path(points: points, speed: speed, strength: strength, radius: radius, closed: closed), categoryBitMask: categoryBitMask)
    }

    /// Samples per span between two control points when smoothing a path.
    static let pathSamplesPerSpan = 12
    /// Most polyline points per path, to keep the GPU's closest-point search short.
    static let maximumPathPoints = 512

    /// The smooth polyline a path field follows: a Catmull-Rom curve through `points`. Empty for other effects.
    public var pathPolyline: [SIMD3<Float>] {
        guard case let .path(points, _, _, _, closed) = effect, points.count >= 2 else {
            return []
        }
        let count = points.count
        func point(_ index: Int) -> SIMD3<Float> {
            closed ? points[(index % count + count) % count] : points[min(max(index, 0), count - 1)]
        }
        let spans = closed ? count : count - 1
        let samples = max(1, min(Self.pathSamplesPerSpan, Self.maximumPathPoints / spans))
        var result: [SIMD3<Float>] = []
        for span in 0..<spans {
            let p0 = point(span - 1)
            let p1 = point(span)
            let p2 = point(span + 1)
            let p3 = point(span + 2)
            for sample in 0..<samples {
                let t = Float(sample) / Float(samples)
                let t2 = t * t
                let t3 = t2 * t
                let a = 2 * p1
                let b = (p2 - p0) * t
                let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
                result.append(0.5 * (a + b + c + d))
            }
        }
        if !closed {
            result.append(points[count - 1])
        }
        return Array(result.prefix(Self.maximumPathPoints))
    }
}

extension ForceField: Codable {
    private enum CodingKeys: String, CodingKey {
        case effect, categoryBitMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Files saved before categories stored the effect itself, without the wrapper.
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect) ?? Effect(from: decoder)
        categoryBitMask = try container.decodeIfPresent(UInt32.self, forKey: .categoryBitMask) ?? .max
    }
}

extension ForceFieldData {
    init(_ field: ForceField) {
        self.init()
        switch field.effect {
        case let .wind(velocity, strength):
            kind = .wind
            self.velocity = velocity
            self.strength = strength
        case let .attractor(center, strength, radius):
            kind = .attractor
            self.center = center
            self.strength = strength
            self.radius = radius
        case let .vortex(center, axis, strength, radius):
            kind = .vortex
            self.center = center
            self.axis = simd_length(axis) > 0 ? simd_normalize(axis) : [0, 1, 0]
            self.strength = strength
            self.radius = radius
        case let .turbulence(strength, scale, speed):
            kind = .turbulence
            self.strength = strength
            self.scale = scale
            self.speed = speed
        case let .path(_, speed, strength, radius, closed):
            // pathStart and pathCount are set where the polyline is added to the frame's path points.
            kind = .path
            self.speed = speed
            self.strength = strength
            self.radius = radius
            pathClosed = closed ? 1 : 0
        }
    }
}
