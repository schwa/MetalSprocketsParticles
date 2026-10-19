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
        /// Only the colliders and force fields whose category matches the emitter's masks. Counts are in uniforms.
        var colliders: [ColliderData]
        var forceFields: [ForceFieldData]
        /// The previous dispatch wrote the same slice.
        var followsSameEmitter: Bool
        /// The emitter's sub-emitters and the settings their children spawn with. Never empty;
        /// `uniforms.subEmitterCount` keeps padding unused.
        var subEmitters: [SubEmitterData]
        var subEmitterUniforms: [SimulationUniforms]
        /// The emitter's user functions, one per `ParticleFunctionSlot` in order; the uniforms' has-function flags match.
        var functions: [ParticleFunction?]
        /// `colorByPosition` baked, for coloring at birth; one white entry when unused.
        var birthColorCurve: [SIMD4<Float>] = [.one]
    }

    /// Warmup steps first, then the frame's step, per emitter; sub-emitter instances after all emitters.
    var dispatches: [Dispatch]
    /// Every collider and force field, before filtering by category.
    var colliders: [ColliderData]
    var forceFields: [ForceFieldData]
    /// Polylines of path fields, which index into it. Never empty.
    var pathPoints: [SIMD4<Float>]
    /// At most `PARTICLE_TRIGGER_MAX_VOLUMES`.
    var triggerVolumes: [TriggerVolumeData]
    /// Seconds simulated this frame, after clamping and `speedFactor`; 0 when not playing.
    var deltaTime: Float
}

extension ParticleSystemRuntime {
    // Nil collections mean "leave as they are", which differs from empty ("none").
    // swiftlint:disable discouraged_optional_collection

    /// The CPU half of `simulate`: applies `colliders` and `transforms`, rebuilds after sub-emitter layout changes,
    /// evaluates triggers, and plans every dispatch. Advances emitter state, so plan each frame exactly once.
    func planFrame(
        deltaTime: Float,
        colliders: [Collider]? = nil,
        transforms: [simd_float4x4]? = nil,
        trackedObjects: [String: SIMD3<Float>]? = nil
    ) throws -> FramePlan {
        // swiftlint:enable discouraged_optional_collection
        if let trackedObjects {
            self.trackedObjects = trackedObjects
        }
        if let colliders {
            self.colliders = colliders
        }
        // Before colliderData, which looks up each distance field's texture slot.
        try updateSignedDistanceFieldTextures(for: self.colliders)
        if let transforms {
            for (emitter, transform) in zip(emitters, transforms) {
                emitter.transform = transform
            }
        }
        if Self.subEmitterLayout(of: emitters) != subEmitterLayout {
            try rebuild()
        }
        let frameDeltaTime = min(deltaTime, Self.maximumStep) * max(speedFactor, 0)
        // Live-particle statistics: read the oldest slot (its frame has surely finished, with at most a few frames in
        // flight), then clear it for this frame to fill.
        let slots = Int(PARTICLE_ALIVE_COUNTER_SLOTS)
        let counters = aliveCounters.contents().bindMemory(to: UInt32.self, capacity: 3 * slots)
        aliveCounterSlot = UInt32(frameIndex % slots)
        let slot = Int(aliveCounterSlot)
        if frameIndex >= slots {
            aliveParticleCount = Int(counters[slot])
            bornParticleCount = Int(counters[slots + slot])
            diedParticleCount = Int(counters[2 * slots + slot])
            // Counts lag a few frames; the frame times they belong to are close enough for a rate.
            recordParticleCounts(seconds: frameDeltaTime)
        }
        counters[slot] = 0
        counters[slots + slot] = 0
        counters[2 * slots + slot] = 0
        frameIndex += 1
        evaluateTriggers(deltaTime: state == .playing ? frameDeltaTime : 0)
        for child in subEmitterInstances {
            if let parent = child.parent, child.subEmitterIndex < parent.settings.subEmitters.count {
                let sub = parent.settings.subEmitters[child.subEmitterIndex]
                child.settings = sub.settings
                // Cached per sprite, so this is a dictionary lookup.
                child.texture = texture(for: sub.sprite)
            }
        }
        for emitter in emitters where emitter.meshDeformation != .none {
            try emitter.mesh?.applyDeformation(emitter.meshDeformation, time: emitter.spawner.time)
        }
        let colliderData = colliderData(deltaTime: state == .playing ? frameDeltaTime : 0)
        var pathPoints: [SIMD4<Float>] = []
        let forceFieldData = forceFields.map { field in
            var data = ForceFieldData(field)
            let polyline = field.pathPolyline
            if !polyline.isEmpty {
                data.pathStart = UInt32(pathPoints.count)
                data.pathCount = UInt32(polyline.count)
                pathPoints += polyline.map { SIMD4($0, 0) }
            }
            return data
        }
        let world = WorldData(
            colliders: Array(zip(self.colliders.map(\.categoryBitMask), colliderData)),
            forceFields: Array(zip(forceFields.map(\.categoryBitMask), forceFieldData))
        )
        return FramePlan(
            dispatches: allEmitters.enumerated().flatMap { index, emitter in
                dispatches(emitter, index: index, frameDeltaTime: frameDeltaTime, world: world)
            },
            colliders: colliderData,
            forceFields: forceFieldData,
            pathPoints: pathPoints.isEmpty ? [.zero] : pathPoints,
            triggerVolumes: triggerVolumes.prefix(Int(PARTICLE_TRIGGER_MAX_VOLUMES)).map(\.data),
            deltaTime: state == .playing ? frameDeltaTime : 0
        )
    }

    /// Colliders matched by index with last frame's get the velocity implied by their motion.
    private func colliderData(deltaTime: Float) -> [ColliderData] {
        let current = colliders
        defer { previousColliders = current }
        guard let previous = previousColliders, previous.count == current.count else {
            return current.enumerated().map { index, collider in
                var data = ColliderData(collider)
                data.triggerIndex = UInt32(index)
                data.fieldIndex = signedDistanceFieldSlot(for: collider)
                return data
            }
        }
        return zip(previous, current).enumerated().map { index, pair in
            let motion = pair.1.motion(from: pair.0, deltaTime: deltaTime)
            var data = ColliderData(pair.1, velocity: motion.linear)
            data.angularVelocity = motion.angular
            data.triggerIndex = UInt32(index)
            data.fieldIndex = signedDistanceFieldSlot(for: pair.1)
            return data
        }
    }

    /// Colliders and force fields with their categories, for filtering per emitter.
    private struct WorldData {
        var colliders: [(category: UInt32, data: ColliderData)]
        var forceFields: [(category: UInt32, data: ForceFieldData)]
    }

    /// Where an emitter is in simulation space for one step.
    private struct SpawnMotion {
        var transform = matrix_identity_float4x4
        var previousOrigin: SIMD3<Float> = .zero
        var inheritedVelocity: SIMD3<Float> = .zero
        /// The rotation over the step, as unit axis and angle; angle 0 for none.
        var spinAxis: SIMD3<Float> = [0, 1, 0]
        var spinAngle: Float = 0
        var inheritedAngularVelocity: SIMD3<Float> = .zero
    }

    /// The shortest rotation taking `previous`'s orientation to `current`'s, or nil if either is not a rotation (scaled
    /// or sheared) or they barely differ. Over half a turn per step reads as the shorter way round.
    static func spin(from previous: simd_float4x4, to current: simd_float4x4) -> (axis: SIMD3<Float>, angle: Float)? {
        func rotation(_ matrix: simd_float4x4) -> simd_quatf? {
            let basis = simd_float3x3(matrix.columns.0.xyz, matrix.columns.1.xyz, matrix.columns.2.xyz)
            let isRigid = [basis.columns.0, basis.columns.1, basis.columns.2].allSatisfy { abs(simd_length($0) - 1) < 1e-3 }
                && abs(simd_determinant(basis) - 1) < 1e-3
            return isRigid ? simd_quatf(basis) : nil
        }
        guard let from = rotation(previous), let to = rotation(current) else {
            return nil
        }
        var delta = simd_normalize(to * from.inverse)
        if delta.real < 0 {
            delta = simd_quatf(vector: -delta.vector)
        }
        let angle = delta.angle
        guard angle > 1e-5 else {
            return nil
        }
        return (simd_normalize(delta.axis), angle)
    }

    private func makeStep(_ emitter: Emitter, deltaTime: Float, motion: SpawnMotion) -> (uniforms: SimulationUniforms, threadCount: Int) {
        let settings = emitter.settings
        let playing = state == .playing
        let deltaTime = playing ? deltaTime : 0
        // Sub-emitter instances never spawn on their own; their parents write their particles.
        let spawn = playing
            ? emitter.spawner.advance(deltaTime: deltaTime, emitter: settings.scalingBirthRate(by: emitter.lodRateScale), capacity: emitter.capacity, isEmitting: emitter.isEmitting && !emitter.isSubEmitter)
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
        // Glint sub-emitters see what foil shading sees: the first light (or foil's fixed light) and the shininess.
        // The camera is set by simulate when it has a view.
        uniforms.glintShininess = max(settings.foil?.shininess ?? ParticleFoil().shininess, 1)
        uniforms.glintLight = switch lights.first {
        case let .directional(direction, _, _)?: SIMD4(simd_length(direction) > 0 ? -simd_normalize(direction) : [0, 1, 0], 0)
        case let .point(position, _, _, _)?: SIMD4(position, 1)
        case nil: SIMD4(simd_normalize(SIMD3<Float>(0.3, 1, 0.6)), 0)
        }
        if settings.constrainsToPlane {
            uniforms.constrainsToPlane = 1
            uniforms.planePoint = motion.transform.columns.3.xyz
            let normal = motion.transform.columns.2.xyz
            uniforms.planeNormal = simd_length(normal) > 0 ? simd_normalize(normal) : [0, 0, 1]
        }
        uniforms.simulationToWorld = model
        uniforms.worldToSimulation = model.inverse
        uniforms.previousEmitterOrigin = motion.previousOrigin
        uniforms.inheritedVelocity = motion.inheritedVelocity
        uniforms.spinAxis = motion.spinAxis
        uniforms.spinAngle = motion.spinAngle
        uniforms.inheritedAngularVelocity = motion.inheritedAngularVelocity
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
        // The stride is filled in once the trail buffer is sized, after planning.
        uniforms.trailPointCount = UInt32(settings.trail?.clampedPointCount ?? 0)
        uniforms.trailPointInterval = max(settings.trail?.pointInterval ?? 0, 0)
        uniforms.collisionRadius = max(settings.collisionRadius, 0)
        uniforms.ordersBirths = settings.ribbon == nil ? 0 : 1
        uniforms.customAttributeCount = UInt32(min(max(settings.customAttributeCount, 1), ParticleFunction.maximumCustomAttributes))
        if settings.colorByPositionAtBirth, settings.colorByPosition != nil {
            uniforms.colorsByBirthPosition = 1
            uniforms.birthColorStart = settings.colorByPositionStart
            uniforms.birthColorEnd = settings.colorByPositionEnd
        }
        if let flocking = settings.flocking {
            uniforms.flocks = 1
            uniforms.flockSpeedRange = [flocking.speedRange.lowerBound, flocking.speedRange.upperBound]
        }
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
                occasion: sub.occasion.gpuKind,
                countPerEvent: UInt32(max(sub.countPerEvent, 1)),
                childSliceStart: UInt32(child.range.lowerBound),
                childCapacity: UInt32(child.capacity),
                velocityFactor: sub.velocityFactor,
                interval: sub.interval,
                replacesParent: sub.replacesParent ? 1 : 0,
                continuesParentLife: sub.continuesParentLife ? 1 : 0,
                volume: sub.volume
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

    private func dispatches(_ emitter: Emitter, index emitterIndex: Int, frameDeltaTime: Float, world: WorldData) -> [FramePlan.Dispatch] {
        emitter.lodRateScale = emitter.lodRateScale(camera: cullingCamera)
        emitter.isCulled = emitter.isOutsideView(camera: cullingCamera)
        // A culled emitter that does not simulate is frozen: no dispatch, and its clock and spawner stand still.
        if emitter.isCulled, !emitter.settings.simulatesWhenCulled {
            return []
        }
        // Filtering here keeps category masks off the GPU: unmasked emitters see exactly the full lists.
        let colliders = world.colliders.filter { $0.category & emitter.settings.categoryMask != 0 }.map(\.data)
        let forceFields = world.forceFields.filter { $0.category & emitter.settings.categoryMask != 0 }.map(\.data)
        // In local space the emitter is the origin of its own space and never moves.
        let spawnTransform = emitter.simulationSpace == .world ? emitter.transform : matrix_identity_float4x4
        let origin = spawnTransform.columns.3.xyz
        let previousOrigin = emitter.simulationSpace == .world ? (emitter.previousTransform?.columns.3.xyz ?? origin) : origin
        let spin = emitter.simulationSpace == .world ? emitter.previousTransform.flatMap { Self.spin(from: $0, to: emitter.transform) } : nil
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
        // Positioned bursts: one zero-length step each, spawning only that burst, with the shape moved to the point.
        if state == .playing, !emitter.pendingPositionedBursts.isEmpty {
            let heldBurst = emitter.spawner.pendingBurst
            for burst in emitter.pendingPositionedBursts {
                var transform = spawnTransform
                transform.columns.3 = SIMD4(burst.position, 1)
                emitter.spawner.pendingBurst = burst.count
                steps.append(makeStep(emitter, deltaTime: 0, motion: SpawnMotion(transform: transform, previousOrigin: burst.position)))
            }
            emitter.spawner.pendingBurst = heldBurst
            emitter.pendingPositionedBursts = []
        }
        var motion = SpawnMotion(
            transform: spawnTransform,
            previousOrigin: previousOrigin,
            inheritedVelocity: emitterVelocity * emitter.settings.inheritVelocity
        )
        if let spin, frameDeltaTime > 0 {
            motion.spinAxis = spin.axis
            motion.spinAngle = spin.angle
            motion.inheritedAngularVelocity = spin.axis * spin.angle / frameDeltaTime * emitter.settings.inheritVelocity
        }
        steps.append(makeStep(emitter, deltaTime: frameDeltaTime, motion: motion))
        let subEmitters = subEmitterData(for: emitter)
        return steps.enumerated().map { index, step in
            var uniforms = step.uniforms
            uniforms.colliderCount = UInt32(colliders.count)
            uniforms.forceFieldCount = UInt32(forceFields.count)
            // Count each emitter once a frame, on its last step (after any warmup steps).
            uniforms.countsAlive = index == steps.count - 1 ? 1 : 0
            uniforms.aliveCounterSlot = aliveCounterSlot
            uniforms.hasUpdateFunction = emitter.settings.updateFunction == nil ? 0 : 1
            uniforms.hasSpawnFunction = emitter.settings.spawnFunction == nil ? 0 : 1
            uniforms.hasCollisionFunction = emitter.settings.collisionFunction == nil ? 0 : 1
            uniforms.hasDeathFunction = emitter.settings.deathFunction == nil ? 0 : 1
            uniforms.reportsCollisions = emitter.settings.reportsCollisions ? 1 : 0
            uniforms.reportsDeaths = emitter.settings.reportsDeaths ? 1 : 0
            uniforms.eventEmitterIndex = UInt32(emitterIndex)
            uniforms.collidesWithSceneDepth = emitter.settings.collidesWithSceneDepth ? 1 : 0
            return FramePlan.Dispatch(
                uniforms: uniforms,
                threadCount: step.threadCount,
                mesh: emitter.mesh,
                colliders: colliders,
                forceFields: forceFields,
                // Sub-emitter instances run after their parents have written their children.
                followsSameEmitter: index > 0 || emitter.isSubEmitter,
                subEmitters: subEmitters.data,
                subEmitterUniforms: subEmitters.uniforms,
                functions: ParticleFunctionSlot.allCases.map { emitter.settings[keyPath: $0.keyPath] },
                birthColorCurve: uniforms.colorsByBirthPosition != 0 ? emitter.settings.colorByPosition?.baked() ?? [.one] : [.one]
            )
        }
    }
}
