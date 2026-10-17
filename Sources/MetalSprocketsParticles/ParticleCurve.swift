import Foundation
import MetalSprocketsParticlesShaders

public protocol ParticleCurveValue: Sendable, Equatable {
    static func interpolate(_ from: Self, _ to: Self, _ fraction: Float) -> Self
}

extension Float: ParticleCurveValue {
    public static func interpolate(_ from: Float, _ to: Float, _ fraction: Float) -> Float {
        from + (to - from) * fraction
    }
}

extension SIMD4: ParticleCurveValue where Scalar == Float {
    public static func interpolate(_ from: SIMD4<Float>, _ to: SIMD4<Float>, _ fraction: Float) -> SIMD4<Float> {
        from + (to - from) * fraction
    }
}

/// A value over a particle's normalized life (0 = birth, 1 = death), linear between keyframes.
public struct ParticleCurve<Value: ParticleCurveValue>: Sendable, Equatable {
    public struct Keyframe: Sendable, Equatable {
        public var time: Float
        public var value: Value

        public init(_ time: Float, _ value: Value) {
            self.time = time
            self.value = value
        }
    }

    /// Always sorted by time and never empty.
    public private(set) var keyframes: [Keyframe]

    public init(_ keyframes: [Keyframe]) {
        precondition(!keyframes.isEmpty, "A curve needs at least one keyframe.")
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public static func constant(_ value: Value) -> Self {
        Self([Keyframe(0, value)])
    }

    public static func linear(from start: Value, to end: Value) -> Self {
        Self([Keyframe(0, start), Keyframe(1, end)])
    }

    /// Eases from `start` to `end`. `exponent` 1 is linear; below 1 changes early, above 1 changes late.
    public static func power(from start: Value, to end: Value, exponent: Float) -> Self {
        let steps = 16
        return Self((0...steps).map { index in
            let time = Float(index) / Float(steps)
            return Keyframe(time, Value.interpolate(start, end, pow(time, exponent)))
        })
    }

    public func value(at time: Float) -> Value {
        guard let first = keyframes.first, let last = keyframes.last else {
            preconditionFailure("A curve needs at least one keyframe.")
        }
        if time <= first.time {
            return first.value
        }
        if time >= last.time {
            return last.value
        }
        let upper = keyframes.firstIndex { $0.time > time } ?? keyframes.count - 1
        let from = keyframes[upper - 1]
        let to = keyframes[upper]
        let span = to.time - from.time
        return Value.interpolate(from.value, to.value, span > 0 ? (time - from.time) / span : 1)
    }

    /// Evenly spaced samples over 0...1 for the GPU lookup table.
    func baked(sampleCount: Int = Int(PARTICLE_CURVE_SAMPLES)) -> [Value] {
        (0..<sampleCount).map { value(at: Float($0) / Float(sampleCount - 1)) }
    }

    /// The first keyframe's value. Setting it changes only that keyframe.
    public var start: Value {
        get { keyframes[0].value }
        set { keyframes[0].value = newValue }
    }

    /// The last keyframe's value. Setting it on a single-keyframe curve adds a keyframe at 1.
    public var end: Value {
        get { keyframes[keyframes.count - 1].value }
        set {
            if keyframes.count == 1 {
                keyframes.append(Keyframe(max(1, keyframes[0].time), newValue))
            } else {
                keyframes[keyframes.count - 1].value = newValue
            }
        }
    }
}
