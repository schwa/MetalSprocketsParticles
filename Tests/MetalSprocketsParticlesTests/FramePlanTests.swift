import Metal
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Frame planning is CPU only: these check what `simulate` would dispatch without running the GPU.
struct FramePlanTests {
    let device = MTLCreateSystemDefaultDevice()!
    let deltaTime: Float = 1.0 / 60.0

    func emitter(_ configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.birthRate = 0
        emitter.lifetime = 10...10
        configure(&emitter)
        return emitter
    }

    /// Particles `emitter` spawns in `plan`, over all its dispatches.
    func spawned(_ plan: FramePlan, _ emitter: ParticleSystem.Emitter) -> Int {
        plan.dispatches
            .filter { Int($0.uniforms.spawn.sliceStart) == emitter.range.lowerBound }
            .reduce(0) { $0 + Int($1.uniforms.spawn.count) }
    }

    func plans(_ system: ParticleSystem, frames: Int) throws -> [FramePlan] {
        try (0..<frames).map { _ in try system.planFrame(deltaTime: deltaTime) }
    }

    // MARK: Timing

    @Test func birthRateSpreadsAcrossFrames() throws {
        let system = try ParticleSystem(device: device, capacity: 1_000, emitter: emitter { $0.birthRate = 90 })
        let counts = try plans(system, frames: 60).map { spawned($0, system.emitters[0]) }
        #expect(counts.reduce(0, +) == 90)
        #expect(counts.allSatisfy { $0 == 1 || $0 == 2 })
    }

    @Test func warmupRunsAsExtraStepsOnTheFirstFrameOnly() throws {
        let system = try ParticleSystem(device: device, capacity: 1_000, emitter: emitter {
            $0.birthRate = 60
            $0.warmupDuration = 0.5
        })
        let first = try system.planFrame(deltaTime: deltaTime)
        #expect(first.dispatches.count == 31)
        #expect(first.dispatches.dropFirst().allSatisfy { $0.followsSameEmitter })
        // 0.5 s of warmup plus one frame at 60 per second; the fractional accumulator may land one short.
        #expect((30...31).contains(spawned(first, system.emitters[0])))
        let second = try system.planFrame(deltaTime: deltaTime)
        #expect(second.dispatches.count == 1)
    }

    @Test func frameTimeIsClampedAndScaled() throws {
        let system = try ParticleSystem(device: device, capacity: 10, emitter: emitter())
        let clamped = try system.planFrame(deltaTime: 1)
        #expect(clamped.deltaTime == Float(1) / 30)
        system.speedFactor = 2
        let doubled = try system.planFrame(deltaTime: deltaTime)
        #expect(doubled.deltaTime == 2 * deltaTime)
        system.state = .paused
        let paused = try system.planFrame(deltaTime: deltaTime)
        #expect(paused.deltaTime == 0)
        #expect(paused.dispatches.allSatisfy { $0.uniforms.deltaTime == 0 && $0.uniforms.spawn.count == 0 })
    }

    // MARK: Slots

    @Test func dispatchCoversOnlyTheLiveWindow() throws {
        let system = try ParticleSystem(device: device, capacity: 1_000, emitter: emitter {
            $0.birthRate = 600
            $0.lifetime = 0.1...0.1
        })
        let threads = try plans(system, frames: 30).map { $0.dispatches[0].threadCount }
        // 0.1 s of life at 600 per second is about 60 live particles, plus the ones that just died.
        #expect(threads.allSatisfy { $0 <= 80 })
        #expect(threads.last! >= 50)
    }

    @Test func stopAndPlayKillsEverySlotOnce() throws {
        let system = try ParticleSystem(device: device, capacity: 500, emitter: emitter { $0.birthRate = 60 })
        _ = try plans(system, frames: 10)
        system.state = .stopped
        system.state = .playing
        let killed = try system.planFrame(deltaTime: deltaTime).dispatches[0]
        #expect(killed.uniforms.spawn.kill != 0)
        #expect(killed.threadCount == 500)
        let next = try system.planFrame(deltaTime: deltaTime)
        #expect(next.dispatches[0].uniforms.spawn.kill == 0)
    }

    @Test func subEmittersGetFixedSlotsAfterTheirParents() throws {
        var parent = emitter { $0.birthRate = 60 }
        parent.subEmitters = [SubEmitter(occasion: .onDeath, countPerEvent: 3, settings: ParticleEmitter())]
        let system = try ParticleSystem(device: device, capacity: 10, emitter: parent)
        let plan = try system.planFrame(deltaTime: deltaTime)
        let child = try #require(system.subEmitterInstances.first)
        #expect(plan.dispatches.count == 2)
        #expect(plan.dispatches[0].uniforms.subEmitterCount == 1)
        #expect(Int(plan.dispatches[0].subEmitters[0].childSliceStart) == child.range.lowerBound)
        #expect(plan.dispatches[0].subEmitters[0].countPerEvent == 3)
        #expect(plan.dispatches[1].threadCount == 30)
        #expect(plan.dispatches[1].followsSameEmitter)
        #expect(plan.dispatches[1].uniforms.spawn.count == 0)
    }

    @Test func colliderVelocityComesFromMotionBetweenFrames() throws {
        let system = try ParticleSystem(device: device, capacity: 10, emitter: emitter())
        _ = try system.planFrame(deltaTime: deltaTime, colliders: [.sphere(center: .zero, radius: 1)])
        let plan = try system.planFrame(deltaTime: deltaTime, colliders: [.sphere(center: [0.1, 0, 0], radius: 1)])
        #expect(abs(plan.colliders[0].velocity.x - 6) < 1e-3)
    }

    @Test func categoryMasksFilterEachDispatch() throws {
        let system = try ParticleSystem(device: device, emitters: [
            emitter { $0.collisionMask = 0b10; $0.fieldMask = 0b01 },
            emitter(),
        ], capacity: 10)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0, categoryBitMask: 0b01), .sphere(center: .zero, radius: 1, categoryBitMask: 0b10)]
        system.forceFields = [.wind(velocity: [1, 0, 0], strength: 1, categoryBitMask: 0b10)]
        let plan = try system.planFrame(deltaTime: deltaTime)
        let masked = plan.dispatches[0]
        #expect(masked.uniforms.colliderCount == 1 && masked.uniforms.forceFieldCount == 0)
        // The sphere keeps its index in system.colliders, so collider-hit triggers still match it.
        #expect(masked.colliders.map(\.triggerIndex) == [1])
        let unmasked = plan.dispatches[1]
        #expect(unmasked.uniforms.colliderCount == 2 && unmasked.uniforms.forceFieldCount == 1)
        #expect(unmasked.colliders.map(\.triggerIndex) == [0, 1])
    }

    // MARK: Triggers

    @Test func namedEventsBurstOnTheNextFrame() throws {
        let system = try ParticleSystem(device: device, capacity: 100, emitter: emitter { $0.triggers = [EmissionTrigger(.event("boom"), .burst(7))] })
        func next() throws -> Int {
            spawned(try system.planFrame(deltaTime: deltaTime), system.emitters[0])
        }
        let quiet = try next()
        system.send(event: "boom")
        system.send(event: "other")
        let once = try next()
        system.send(event: "boom")
        system.send(event: "boom")
        let twice = try next()
        #expect(quiet == 0 && once == 7 && twice == 14)
    }

    @Test func afterFiresOnceAndEveryRepeats() throws {
        let system = try ParticleSystem(device: device, emitters: [
            emitter { $0.triggers = [EmissionTrigger(.after(seconds: 0.5), .burst(1))] },
            emitter { $0.triggers = [EmissionTrigger(.every(seconds: 0.25), .burst(1))] },
        ], capacity: 100)
        // 1.1 s, so the 1.0 s tick does not land on a float boundary.
        let frames = try plans(system, frames: 66)
        #expect(frames.reduce(0) { $0 + spawned($1, system.emitters[0]) } == 1)
        #expect(frames.reduce(0) { $0 + spawned($1, system.emitters[1]) } == 4)
    }

    @Test func objectEnteringAVolumeFiresOncePerEntry() throws {
        let volume = TriggerVolume.sphere(center: .zero, radius: 1)
        let system = try ParticleSystem(device: device, capacity: 100, emitter: emitter {
            $0.triggers = [EmissionTrigger(.objectEnters(name: "ball", volume: volume), .burst(2))]
        })
        var total = 0
        for position: SIMD3<Float> in [[3, 0, 0], [0.5, 0, 0], [0.2, 0, 0], [3, 0, 0], [0, 0, 0]] {
            system.trackedObjects["ball"] = position
            total += spawned(try system.planFrame(deltaTime: deltaTime), system.emitters[0])
        }
        #expect(total == 4)
    }

    @Test func startAndStopToggleEmission() throws {
        let system = try ParticleSystem(device: device, capacity: 500, emitter: emitter {
            $0.birthRate = 60
            $0.triggers = [EmissionTrigger(.event("on"), .start), EmissionTrigger(.event("off"), .stop)]
        })
        func total(frames: Int) throws -> Int {
            try plans(system, frames: frames).reduce(0) { $0 + spawned($1, system.emitters[0]) }
        }
        system.isEmitting = false
        let off = try total(frames: 10)
        system.send(event: "on")
        let on = try total(frames: 30)
        system.send(event: "off")
        let stopped = try total(frames: 30)
        #expect(off == 0 && on == 30 && stopped == 0)
    }

    @Test func restartResetsTriggerTimers() throws {
        let system = try ParticleSystem(device: device, capacity: 10, emitter: emitter { $0.triggers = [EmissionTrigger(.after(seconds: 0.1), .burst(1))] })
        func total() throws -> Int {
            try plans(system, frames: 10).reduce(0) { $0 + spawned($1, system.emitters[0]) }
        }
        let before = try total()
        system.restart()
        let after = try total()
        #expect(before == 1 && after == 1)
        #expect(system.simulationTime < 0.2)
    }
}
