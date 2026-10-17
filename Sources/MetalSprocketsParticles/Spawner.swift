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
    static func cycleIndex(time: Float, emitter: ParticleEmitter) -> UInt32 {
        guard let duration = emitter.emissionDuration, emitter.loops else {
            return 0
        }
        let cycle = duration + max(emitter.idleDuration, 0)
        return cycle > 0 ? UInt32(max(0, (time / cycle).rounded(.down))) : 0
    }

    /// `birthRate` +/- `birthRateVariation`, picked once per emission cycle from `seed`.
    func birthRate(emitter: ParticleEmitter) -> Float {
        guard emitter.birthRateVariation > 0 else {
            return max(emitter.birthRate, 0)
        }
        var generator = SplitMix64(seed: UInt64(seed) << 32 | UInt64(Self.cycleIndex(time: time, emitter: emitter)))
        let offset = Float.random(in: -1...1, using: &generator) * emitter.birthRateVariation
        return max(emitter.birthRate + offset, 0)
    }

    static func isInEmissionWindow(time: Float, emitter: ParticleEmitter) -> Bool {
        guard let duration = emitter.emissionDuration else {
            return true
        }
        guard emitter.loops else {
            return time < duration
        }
        let cycle = duration + max(emitter.idleDuration, 0)
        guard cycle > 0 else {
            return false
        }
        return time.truncatingRemainder(dividingBy: cycle) < duration
    }

    mutating func advance(deltaTime: Float, emitter: ParticleEmitter, capacity: Int, isEmitting: Bool) -> Step {
        var count = 0
        if isEmitting && Self.isInEmissionWindow(time: time, emitter: emitter) {
            accumulator += birthRate(emitter: emitter) * deltaTime
            let whole = Int(accumulator)
            accumulator -= Float(whole)
            count += whole
        }
        count += pendingBurst
        pendingBurst = 0
        count = min(count, capacity)

        let step = Step(cursor: cursor, count: UInt32(count), serial: serial)
        cursor = UInt32((Int(cursor) + count) % max(capacity, 1))
        serial &+= UInt32(count)
        time += deltaTime
        maxLifetime = max(maxLifetime, emitter.lifetime.upperBound)
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
