import MetalSprocketsParticlesShaders
import simd

/// Everything one `simulate` call dispatches, worked out on the CPU: which emitters step, how many particles each
/// spawns from which ring slots, with which settings, against which colliders and fields. Planning advances emitter
/// clocks, triggers, and collider history; encoding then only records GPU work. Tests can check a plan without
/// running the GPU.
struct FramePlan {
    /// One compute dispatch: an emitter's slice for one step.
    struct Dispatch {
        var uniforms: SimulationUniforms
        /// Slots this step touches, starting at `uniforms.spawn.firstSlot`.
        var threadCount: Int
        var mesh: EmitterMesh?
        /// The previous dispatch wrote the same slice.
        var followsSameEmitter: Bool
        /// The emitter's sub-emitters and the settings their children spawn with. Never empty;
        /// `uniforms.subEmitterCount` keeps padding unused.
        var subEmitters: [SubEmitterData]
        var subEmitterUniforms: [SimulationUniforms]
    }

    /// Warmup steps first, then the frame's step, per emitter; sub-emitter instances after all emitters.
    var dispatches: [Dispatch]
    var colliders: [ColliderData]
    var forceFields: [ForceFieldData]
    /// At most `PARTICLE_TRIGGER_MAX_VOLUMES`.
    var triggerVolumes: [TriggerVolumeData]
    /// Seconds simulated this frame, after clamping and `speedFactor`; 0 when not playing.
    var deltaTime: Float
}

extension ParticleSystem {
    /// The CPU half of `simulate`: applies `colliders` and `transforms`, rebuilds after sub-emitter layout changes,
    /// evaluates triggers, and plans every dispatch. Advances emitter state, so plan each frame exactly once.
    func planFrame(deltaTime: Float, colliders: [Collider]? = nil, transforms: [simd_float4x4]? = nil) throws -> FramePlan {
        if let colliders {
            self.colliders = colliders
        }
        if let transforms {
            for (emitter, transform) in zip(emitters, transforms) {
                emitter.transform = transform
            }
        }
        if Self.subEmitterLayout(of: emitters) != subEmitterLayout {
            try rebuild()
        }
        let frameDeltaTime = min(deltaTime, 1.0 / 30.0) * max(speedFactor, 0)
        evaluateTriggers(deltaTime: state == .playing ? frameDeltaTime : 0)
        for child in subEmitterInstances {
            if let parent = child.parent, child.subEmitterIndex < parent.settings.subEmitters.count {
                child.settings = parent.settings.subEmitters[child.subEmitterIndex].settings
            }
        }
        return FramePlan(
            dispatches: allEmitters.flatMap { dispatches($0, frameDeltaTime: frameDeltaTime) },
            colliders: colliderData(deltaTime: state == .playing ? frameDeltaTime : 0),
            forceFields: forceFields.map(ForceFieldData.init),
            triggerVolumes: triggerVolumes.prefix(Int(PARTICLE_TRIGGER_MAX_VOLUMES)).map(\.data),
            deltaTime: state == .playing ? frameDeltaTime : 0
        )
    }

    /// Colliders matched by index with last frame's get the velocity implied by their motion.
    private func colliderData(deltaTime: Float) -> [ColliderData] {
        let current = colliders
        defer { previousColliders = current }
        guard let previous = previousColliders, previous.count == current.count else {
            return current.map { ColliderData($0) }
        }
        return zip(previous, current).map { previous, collider in
            ColliderData(collider, velocity: collider.velocity(from: previous, deltaTime: deltaTime))
        }
    }

    /// Where an emitter is in simulation space for one step.
    private struct SpawnMotion {
        var transform = matrix_identity_float4x4
        var previousOrigin: SIMD3<Float> = .zero
        var inheritedVelocity: SIMD3<Float> = .zero
    }

    private func makeStep(_ emitter: Emitter, deltaTime: Float, motion: SpawnMotion) -> (uniforms: SimulationUniforms, threadCount: Int) {
        let settings = emitter.settings
        let playing = state == .playing
        let deltaTime = playing ? deltaTime : 0
        // Sub-emitter instances never spawn on their own; their parents write their particles.
        let spawn = playing
            ? emitter.spawner.advance(deltaTime: deltaTime, emitter: settings, capacity: emitter.capacity, isEmitting: emitter.isEmitting && !emitter.isSubEmitter)
            : Spawner.Step(cursor: emitter.spawner.cursor, count: 0, serial: emitter.spawner.serial)
        var uniforms = self.uniforms(for: emitter, deltaTime: deltaTime, motion: motion, spawn: spawn)
        uniforms.subEmitterCount = UInt32(emitter.children.count)
        // Touch only slots that can hold live particles, plus those that died since the last step. A kill, or a
        // sub-emitter instance, touches all.
        let threadCount: Int
        if emitter.needsKill || emitter.isSubEmitter {
            uniforms.spawn.firstSlot = 0
            threadCount = emitter.capacity
        } else {
            let start = emitter.dispatchStartSerial
            uniforms.spawn.firstSlot = start % UInt32(emitter.capacity)
            threadCount = min(Int(emitter.spawner.serial &- start), emitter.capacity)
        }
        emitter.dispatchStartSerial = emitter.spawner.liveStartSerial
        emitter.needsKill = false
        // Never dispatch zero threads; an extra dead slot is harmless.
        return (uniforms, max(threadCount, 1))
    }

    /// An emitter's settings for one step, without side effects. Sub-emitter children spawn with these too.
    private func uniforms(for emitter: Emitter, deltaTime: Float, motion: SpawnMotion, spawn: Spawner.Step) -> SimulationUniforms {
        let settings = emitter.settings
        let model = emitter.modelTransform
        var uniforms = SimulationUniforms()
        uniforms.emitterTransform = motion.transform
        uniforms.simulationToWorld = model
        uniforms.worldToSimulation = model.inverse
        uniforms.previousEmitterOrigin = motion.previousOrigin
        uniforms.inheritedVelocity = motion.inheritedVelocity
        uniforms.shape = ParticleShapeData(settings, mesh: emitter.mesh)
        uniforms.velocity = settings.velocity
        uniforms.velocitySpread = settings.velocitySpread
        uniforms.gravity = settings.gravity
        uniforms.drag = settings.drag
        uniforms.lifetimeMinimum = settings.lifetime.lowerBound
        uniforms.lifetimeMaximum = settings.lifetime.upperBound
        uniforms.deltaTime = deltaTime
        // The emitter clock, not wall time, so turbulence stays deterministic.
        uniforms.time = emitter.spawner.time
        uniforms.restitution = settings.restitution
        uniforms.friction = settings.friction
        uniforms.diesOnCollision = settings.diesOnCollision ? 1 : 0
        uniforms.countsColliderHits = countsColliderHits ? 1 : 0
        uniforms.angle = settings.angle
        uniforms.angularSpeed = settings.angularSpeed
        uniforms.initialFrame = settings.imageSequence?.initialFrame ?? 0
        uniforms.frameRate = settings.imageSequence?.frameRate ?? 0
        uniforms.variation = ParticleVariationData(
            size: max(settings.sizeVariation, 0),
            restitution: max(settings.restitutionVariation, 0),
            friction: max(settings.frictionVariation, 0),
            speed: max(settings.speedVariation, 0),
            color: simd_max(settings.colorVariation, .zero),
            angle: settings.angleVariation,
            angularSpeed: settings.angularSpeedVariation,
            initialFrame: settings.imageSequence?.initialFrameVariation ?? 0,
            frameRate: settings.imageSequence?.frameRateVariation ?? 0
        )
        uniforms.colliderCount = UInt32(colliders.count)
        uniforms.forceFieldCount = UInt32(forceFields.count)
        uniforms.triggerVolumeCount = UInt32(min(triggerVolumes.count, Int(PARTICLE_TRIGGER_MAX_VOLUMES)))
        uniforms.spawn = ParticleSpawnData(
            seed: emitter.seed,
            capacity: UInt32(emitter.capacity),
            sliceStart: UInt32(emitter.range.lowerBound),
            firstSlot: 0,
            cursor: spawn.cursor,
            count: spawn.count,
            serial: spawn.serial,
            kill: emitter.needsKill ? 1 : 0
        )
        return uniforms
    }

    /// What the parent's kernel needs to write `emitter`'s children.
    private func subEmitterData(for emitter: Emitter) -> (data: [SubEmitterData], uniforms: [SimulationUniforms]) {
        var data: [SubEmitterData] = []
        var uniforms: [SimulationUniforms] = []
        for child in emitter.children {
            guard child.subEmitterIndex < emitter.settings.subEmitters.count else {
                continue
            }
            let sub = emitter.settings.subEmitters[child.subEmitterIndex]
            data.append(SubEmitterData(
                occasion: sub.occasion.kind,
                countPerEvent: UInt32(max(sub.countPerEvent, 1)),
                childSliceStart: UInt32(child.range.lowerBound),
                childCapacity: UInt32(child.capacity),
                velocityFactor: sub.velocityFactor,
                interval: sub.interval
            ))
            let still = Spawner.Step(cursor: 0, count: 0, serial: 0)
            uniforms.append(self.uniforms(for: child, deltaTime: 0, motion: SpawnMotion(), spawn: still))
        }
        // Never bind empty arrays.
        if data.isEmpty {
            data = [SubEmitterData()]
            uniforms = [self.uniforms(for: emitter, deltaTime: 0, motion: SpawnMotion(), spawn: Spawner.Step(cursor: 0, count: 0, serial: 0))]
        }
        return (data, uniforms)
    }

    private func dispatches(_ emitter: Emitter, frameDeltaTime: Float) -> [FramePlan.Dispatch] {
        // In local space the emitter is the origin of its own space and never moves.
        let spawnTransform = emitter.simulationSpace == .world ? emitter.transform : matrix_identity_float4x4
        let origin = spawnTransform.columns.3.xyz
        let previousOrigin = emitter.simulationSpace == .world ? (emitter.previousTransform?.columns.3.xyz ?? origin) : origin
        emitter.previousTransform = emitter.transform
        let emitterVelocity = frameDeltaTime > 0 ? (origin - previousOrigin) / frameDeltaTime : .zero

        var steps: [(uniforms: SimulationUniforms, threadCount: Int)] = []
        if emitter.needsWarmup {
            emitter.needsWarmup = false
            let still = SpawnMotion(transform: spawnTransform, previousOrigin: origin)
            let warmupStep: Float = 1.0 / 60.0
            var remaining = emitter.settings.warmupDuration
            while remaining > 0 {
                steps.append(makeStep(emitter, deltaTime: min(warmupStep, remaining), motion: still))
                remaining -= warmupStep
            }
        }
        steps.append(makeStep(emitter, deltaTime: frameDeltaTime, motion: SpawnMotion(
            transform: spawnTransform,
            previousOrigin: previousOrigin,
            inheritedVelocity: emitterVelocity * emitter.settings.inheritVelocity
        )))
        let subEmitters = subEmitterData(for: emitter)
        return steps.enumerated().map { index, step in
            FramePlan.Dispatch(
                uniforms: step.uniforms,
                threadCount: step.threadCount,
                mesh: emitter.mesh,
                // Sub-emitter instances run after their parents have written their children.
                followsSameEmitter: index > 0 || emitter.isSubEmitter,
                subEmitters: subEmitters.data,
                subEmitterUniforms: subEmitters.uniforms
            )
        }
    }
}
