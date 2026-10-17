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
            accumulator += max(emitter.birthRate, 0) * deltaTime
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
        return step
    }
}
