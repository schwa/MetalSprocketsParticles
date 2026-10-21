extension ParticleCurve where Value == Float {
    /// The area under the curve from `start` to `end`, exact for its straight segments; the first and last values hold
    /// outside the keyframes.
    func integral(from start: Float, to end: Float) -> Float {
        guard end > start else {
            return 0
        }
        let breaks = keyframes.map(\.time).filter { $0 > start && $0 < end }.sorted()
        let points = [start] + breaks + [end]
        var total: Float = 0
        for index in 0..<(points.count - 1) {
            let from = points[index]
            let to = points[index + 1]
            total += (value(at: from) + value(at: to)) / 2 * (to - from)
        }
        return total
    }

    /// True when the curve has reached its last keyframe by `time` and holds a value of zero or less from then on.
    func hasEnded(at time: Float) -> Bool {
        guard let last = keyframes.max(by: { $0.time < $1.time }) else {
            return false
        }
        return last.value <= 0 && time >= last.time
    }
}

/// CPU-side emission bookkeeping. Decides how many particles to spawn each step and where in the ring they go.
struct Spawner: Equatable {
    struct Step: Equatable {
        var cursor: UInt32
        var count: UInt32
        var serial: UInt32
    }

    /// Emitter clock in seconds, used for emission duration and idle periods.
    var time: Float = 0
    /// Fractional particles carried between steps so low rates still emit.
    var accumulator: Float = 0
    var cursor: UInt32 = 0
    var serial: UInt32 = 0
    var pendingBurst = 0
    /// Emitter time at the end of the last step that spawned anything; -infinity before the first.
    var lastBirthTime = -Float.infinity
    /// Drives birth rate variation.
    var seed: UInt32 = 0

    /// Emitter time and spawn serial at the end of each recent step, oldest first. Used to bound which slots can hold
    /// live particles.
    struct Checkpoint: Equatable {
        var time: Float
        var serial: UInt32
    }

    var checkpoints: [Checkpoint] = [Checkpoint(time: 0, serial: 0)]
    /// The longest lifetime seen since the last reset. Only grows, so lowering the lifetime setting cannot hide
    /// particles that are still alive.
    var maxLifetime: Float = 0

    /// Every particle with a serial below this is dead: it was born in a step that ended at least `maxLifetime` ago.
    var liveStartSerial: UInt32 {
        let cutoff = time - maxLifetime
        return checkpoints.last { $0.time <= cutoff }?.serial ?? checkpoints[0].serial
    }

    /// Index of the emission cycle containing `time`. Always 0 when emission does not cycle.
    static func cycleIndex(time: Float, rate: RateModule) -> UInt32 {
        guard let duration = rate.emissionDuration, rate.loops else {
            return 0
        }
        let cycle = duration + max(rate.idleDuration, 0)
        return cycle > 0 ? UInt32(max(0, (time / cycle).rounded(.down))) : 0
    }

    /// `birthRate` +/- `birthRateVariation`, picked once per emission cycle from `seed`.
    func birthRate(rate: RateModule) -> Float {
        guard rate.variation > 0 else {
            return max(rate.birthRate, 0)
        }
        var generator = SplitMix64(seed: UInt64(seed) << 32 | UInt64(Self.cycleIndex(time: time, rate: rate)))
        let offset = Float.random(in: -1...1, using: &generator) * rate.variation
        return max(rate.birthRate + offset, 0)
    }

    /// True once the emitter will never spawn on its own again: its envelope has ended at zero, or its single
    /// (non-looping) emission period is over, or its birth rate is zero. Bursts and triggers can still add particles.
    static func isEmissionOver(time: Float, rate: RateModule) -> Bool {
        if rate.overTime.hasEnded(at: time) || rate.birthRate <= 0 && rate.variation <= 0 {
            return true
        }
        if let duration = rate.emissionDuration, !rate.loops {
            return time >= duration
        }
        return false
    }

    static func isInEmissionWindow(time: Float, rate: RateModule) -> Bool {
        guard let duration = rate.emissionDuration else {
            return true
        }
        guard rate.loops else {
            return time < duration
        }
        let cycle = duration + max(rate.idleDuration, 0)
        guard cycle > 0 else {
            return false
        }
        return time.truncatingRemainder(dividingBy: cycle) < duration
    }

    mutating func advance(deltaTime: Float, rate: RateModule, maxLifetime lifetime: Float, capacity: Int, isEmitting: Bool) -> Step {
        var count = 0
        if isEmitting, Self.isInEmissionWindow(time: time, rate: rate) {
            // Rate times the envelope's area over the step. A constant envelope keeps the plain product, so default
            // emitters spawn exactly as before.
            let envelope = rate.overTime
            let shapedTime = envelope.keyframes.count == 1
                ? envelope.keyframes[0].value * deltaTime
                : envelope.integral(from: time, to: time + deltaTime)
            accumulator += birthRate(rate: rate) * max(shapedTime, 0)
            let whole = Int(accumulator)
            accumulator -= Float(whole)
            count += whole
        }
        count += pendingBurst
        pendingBurst = 0
        count = min(count, capacity)

        if count > 0 {
            lastBirthTime = time + deltaTime
        }
        let step = Step(cursor: cursor, count: UInt32(count), serial: serial)
        cursor = UInt32((Int(cursor) + count) % max(capacity, 1))
        serial &+= UInt32(count)
        time += deltaTime
        maxLifetime = max(maxLifetime, lifetime)
        checkpoints.append(Checkpoint(time: time, serial: serial))
        // Keep the newest checkpoint at or before the cutoff; older ones can never be needed again.
        let cutoff = time - maxLifetime
        if let keep = checkpoints.lastIndex(where: { $0.time <= cutoff }), keep > 0 {
            checkpoints.removeFirst(keep)
        }
        return step
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
