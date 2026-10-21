import Metal
import MetalSprocketsParticlesShaders
import simd

/// What one trigger saw at its last check, so it fires on changes rather than every frame.
struct TriggerMemory: Equatable {
    var hasFiredAfter = false
    var lastEveryTick = 0
    var objectWasInside = false
    /// The GPU counter value at the last check.
    var lastCount: UInt32 = 0
    /// Which counter the trigger used, so a changed layout starts a new baseline instead of firing.
    var counterIndex = -1
}

extension ParticleSystemRuntime {
    /// Trigger volumes for this frame, in the order the GPU counts them.
    var triggerVolumes: [TriggerVolume] {
        emitters.flatMap { emitter in
            emitter.resolved.triggers.compactMap { trigger in
                if case let .particlesEnter(volume, _) = trigger.condition {
                    return volume
                }
                return nil
            }
        }
    }

    var countsColliderHits: Bool {
        emitters.contains { emitter in
            emitter.resolved.triggers.contains { trigger in
                if case .colliderHit = trigger.condition {
                    return true
                }
                return false
            }
        }
    }

    /// Checks every trigger and applies the actions that fire. Called at the start of `simulate`, before
    /// `simulationTime` advances by `deltaTime`.
    func evaluateTriggers(deltaTime: Float) {
        let counterCount = Int(PARTICLE_TRIGGER_MAX_COLLIDERS + PARTICLE_TRIGGER_MAX_VOLUMES)
        let counters = Array(UnsafeBufferPointer(start: triggerCounters.contents().bindMemory(to: UInt32.self, capacity: counterCount), count: counterCount))
        let events = pendingEvents
        pendingEvents.removeAll()
        let time = simulationTime + deltaTime
        var volumeIndex = 0

        for emitter in emitters {
            for (index, trigger) in emitter.resolved.triggers.enumerated() {
                var memory = emitter.triggerMemory[index] ?? TriggerMemory()
                var fires = 0
                func counterFires(_ counterIndex: Int, threshold: Int) {
                    let count = counters[counterIndex]
                    if memory.counterIndex == counterIndex, Int(count &- memory.lastCount) >= max(threshold, 1) {
                        fires = 1
                    }
                    // Only consume counts once the threshold is reached, so slow trickles still add up.
                    if memory.counterIndex != counterIndex || fires > 0 {
                        memory.lastCount = count
                    }
                    memory.counterIndex = counterIndex
                }
                switch trigger.condition {
                case let .event(name):
                    fires = events.filter { $0 == name }.count
                case let .after(seconds):
                    if !memory.hasFiredAfter, time >= seconds {
                        memory.hasFiredAfter = true
                        fires = 1
                    }
                case let .every(seconds):
                    let tick = seconds > 0 ? Int((time / seconds).rounded(.down)) : 0
                    fires = max(tick - memory.lastEveryTick, 0)
                    memory.lastEveryTick = tick
                case let .objectEnters(name, volume):
                    let inside = trackedObjects[name].map(volume.contains) ?? false
                    fires = inside && !memory.objectWasInside ? 1 : 0
                    memory.objectWasInside = inside
                case let .particlesEnter(_, count):
                    counterFires(Int(PARTICLE_TRIGGER_MAX_COLLIDERS) + volumeIndex, threshold: count)
                    volumeIndex += 1
                case let .colliderHit(colliderIndex, count):
                    if colliderIndex >= 0, colliderIndex < Int(PARTICLE_TRIGGER_MAX_COLLIDERS) {
                        counterFires(colliderIndex, threshold: count)
                    }
                }
                emitter.triggerMemory[index] = memory
                for _ in 0..<fires {
                    apply(trigger.action, to: emitter)
                }
            }
        }
        simulationTime = time
    }

    private func apply(_ action: EmissionTrigger.Action, to emitter: Emitter) {
        switch action {
        case let .burst(count):
            emitter.burst(count)
        case .start:
            emitter.isEmitting = true
        case .stop:
            emitter.isEmitting = false
        case .restart:
            emitter.restart()
        }
    }
}
