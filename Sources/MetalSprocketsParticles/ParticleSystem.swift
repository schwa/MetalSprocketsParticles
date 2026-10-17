import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

public enum SimulationState: Sendable, Hashable {
    case playing
    /// Particles freeze in place. Queued bursts wait until playback resumes.
    case paused
    /// All particles are removed and nothing emits. Switching back to `.playing` restarts every emitter.
    case stopped
}

/// Owns GPU particle state for any number of emitters. All emitters share one particle buffer, one simulation pass,
/// and one world of colliders and force fields. Each emitter owns a fixed slice of the buffer and draws with its own
/// blend mode and texture. Simulation and rendering are separate elements so callers can place them in their own
/// passes.
public final class ParticleSystem {
    /// Particle colors, curves, and blending are linear. Render to an sRGB target so the GPU encodes them for display;
    /// a non-sRGB target shows linear values as if they were sRGB, which looks darker and more saturated.
    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// One emitter in a system: its settings plus the runtime state that does not belong in a value type.
    public final class Emitter {
        public var settings: ParticleEmitter
        /// Premultiplied-alpha sprite, or a sprite sheet when `settings.imageSequence` is set. `nil` draws a soft dot.
        public var texture: MTLTexture?
        /// Emitter-to-world transform. Emitter position, velocity, and shape are in this space.
        public var transform = matrix_identity_float4x4
        public var simulationSpace: SimulationSpace = .world
        /// Turns emission off without affecting existing particles.
        public var isEmitting = true
        /// Triangles for `EmitterShape.mesh`.
        public var mesh: EmitterMesh?
        /// Particles this emitter can have alive at once.
        public let capacity: Int
        /// This emitter's slice of the shared particle buffer.
        public internal(set) var range: Range<Int>

        let seed: UInt32
        var spawner: Spawner
        var needsKill = false
        var needsWarmup = true
        var previousTransform: simd_float4x4?
        /// The live bound from the previous step. Each step dispatches from here, so particles that just died get one
        /// last update that stores them as dead; every slot outside the window is then known to be dead.
        var dispatchStartSerial: UInt32 = 0
        /// Radix sort scratch, created the first time the emitter sorts.
        var sortBuffers: ParticleSortBuffers?
        /// Particles sorted this frame, or 0 when this frame was not sorted. Render draws sorted records when nonzero.
        var sortedCount = 0
        /// For a sub-emitter instance: the emitter whose particles spawn this one's, and which of its sub-emitters this is.
        weak var parent: Emitter?
        var subEmitterIndex = 0
        /// Sub-emitter instances driven by this emitter, in `settings.subEmitters` order.
        var children: [Emitter] = []

        var isSubEmitter: Bool {
            parent != nil
        }

        /// World-space center of the emitter's shape, for ordering emitters by distance.
        var worldCenter: SIMD3<Float> {
            (transform * SIMD4(settings.position, 1)).xyz
        }

        /// Ring slots that can hold live particles: `count` slots starting at `start`, wrapping at `capacity`.
        /// Sub-emitter children are written by their parents, not spawned in order, so their window is everything.
        var liveWindow: (start: Int, count: Int) {
            if isSubEmitter {
                return (0, capacity)
            }
            let start = spawner.liveStartSerial
            return (Int(start % UInt32(capacity)), min(Int(spawner.serial &- start), capacity))
        }

        init(settings: ParticleEmitter, capacity: Int, range: Range<Int>, seed: UInt32) {
            self.settings = settings
            self.capacity = capacity
            self.range = range
            self.seed = seed
            spawner = Spawner(seed: seed)
        }

        /// Emits `count` particles on the next playing step, on top of the birth rate.
        public func burst(_ count: Int) {
            spawner.pendingBurst += max(count, 0)
        }

        /// Removes this emitter's particles, resets its emission clock, and runs its warmup again.
        public func restart() {
            spawner = Spawner(seed: seed)
            needsKill = true
            needsWarmup = true
            dispatchStartSerial = 0
        }

        /// Simulation space to world: the transform in local space, identity in world space.
        var modelTransform: simd_float4x4 {
            simulationSpace == .local ? transform : matrix_identity_float4x4
        }
    }

    public let seed: UInt32
    public private(set) var emitters: [Emitter] = []
    /// Instances for every emitter's `settings.subEmitters`, stored after all emitters in the shared buffer.
    private(set) var subEmitterInstances: [Emitter] = []
    /// `countPerEvent` of each emitter's sub-emitters when the buffer was built, to notice structural changes.
    private var subEmitterLayout: [[Int]] = []

    /// Emitters and sub-emitter instances, in buffer order.
    var allEmitters: [Emitter] {
        emitters + subEmitterInstances
    }
    /// World-space colliders shared by every emitter. Update them per frame to move them; their velocity is derived
    /// from the change since the previous frame.
    public var colliders: [Collider] = []
    /// World-space force fields shared by every emitter.
    public var forceFields: [ForceField] = []
    /// Multiplies simulation time. 2 runs twice as fast; 0.5 is slow motion.
    public var speedFactor: Float = 1

    public var state: SimulationState = .playing {
        didSet {
            if state == .stopped {
                allEmitters.forEach { $0.needsKill = true }
            } else if oldValue == .stopped {
                allEmitters.forEach { $0.restart() }
            }
        }
    }

    public let device: MTLDevice
    private(set) var buffer: MTLBuffer
    let library: ShaderLibrary
    private let sampler: MTLSamplerState
    /// Bound in place of a missing texture; the shader ignores it.
    private let placeholderTexture: MTLTexture
    /// Bound in place of a missing emitter mesh; the counts in uniforms keep it unused.
    private let placeholderMesh: EmitterMesh
    private let sortKernels: ParticleSortKernels
    /// Bound in place of sort records for unsorted emitters; the shader ignores it.
    private let placeholderSortRecords: MTLBuffer
    /// Colliders from the previous frame, used to derive collider velocity.
    private var previousColliders: [Collider]?

    /// Total particles across all emitters.
    public var capacity: Int {
        allEmitters.reduce(0) { $0 + $1.capacity }
    }

    /// Creates a system with one emitter per entry in `emitters`, each with room for `capacity` particles.
    public init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, emitters: [ParticleEmitter], capacity: Int, seed: UInt32 = 0) throws {
        self.device = device
        self.seed = seed
        library = try ShaderLibrary(bundle: .metalSprocketsParticlesShaders(), device: device)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        self.sampler = sampler
        let placeholderDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let placeholderTexture = device.makeTexture(descriptor: placeholderDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        placeholderTexture.label = "Particle placeholder texture"
        self.placeholderTexture = placeholderTexture
        placeholderMesh = try EmitterMesh(device: device, positions: [], indices: [])
        sortKernels = try ParticleSortKernels(library: library)
        guard let placeholderSortRecords = device.makeBuffer(length: 16, options: .storageModePrivate) else {
            throw CocoaError(.featureUnsupported)
        }
        placeholderSortRecords.label = "Particle placeholder sort records"
        self.placeholderSortRecords = placeholderSortRecords
        buffer = try Self.makeBuffer(device: device, count: 1)

        try setEmitters(emitters.map { ($0, capacity) })
    }

    /// Creates a system with a single emitter.
    public convenience init(device: MTLDevice = MTLCreateSystemDefaultDevice()!, capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: [emitter], capacity: capacity, seed: seed)
    }

    private static func makeBuffer(device: MTLDevice, count: Int) throws -> MTLBuffer {
        // All particles start dead (lifetime 0).
        let length = MemoryLayout<Particle>.stride * max(count, 1)
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: length)
        buffer.label = "Particles"
        return buffer
    }

    /// Emitter `index` uses the system seed offset by its index, so emitter 0 matches a single-emitter system.
    private func emitterSeed(_ index: Int) -> UInt32 {
        seed &+ UInt32(truncatingIfNeeded: index) &* 0x9E37_79B9
    }

    /// Replaces every emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    public func setEmitters(_ emitters: [(settings: ParticleEmitter, capacity: Int)]) throws -> [Emitter] {
        var start = 0
        var created: [Emitter] = []
        for (index, entry) in emitters.enumerated() {
            let capacity = max(entry.capacity, 1)
            created.append(Emitter(settings: entry.settings, capacity: capacity, range: start..<(start + capacity), seed: emitterSeed(index)))
            start += capacity
        }
        // Sub-emitter instances follow all emitters. Each parent slot owns countPerEvent child slots.
        var children: [Emitter] = []
        for parent in created {
            for (subIndex, sub) in parent.settings.subEmitters.enumerated() {
                let capacity = parent.capacity * max(sub.countPerEvent, 1)
                let child = Emitter(settings: sub.settings, capacity: capacity, range: start..<(start + capacity), seed: emitterSeed(created.count + children.count))
                child.parent = parent
                child.subEmitterIndex = subIndex
                child.needsWarmup = false
                parent.children.append(child)
                children.append(child)
                start += capacity
            }
        }
        buffer = try Self.makeBuffer(device: device, count: start)
        self.emitters = created
        subEmitterInstances = children
        subEmitterLayout = Self.subEmitterLayout(of: created)
        return created
    }

    private static func subEmitterLayout(of emitters: [Emitter]) -> [[Int]] {
        emitters.map { $0.settings.subEmitters.map { max($0.countPerEvent, 1) } }
    }

    /// Rebuilds the buffer for the current emitters, keeping runtime state that is not part of the settings.
    private func rebuild(adding extra: [(settings: ParticleEmitter, capacity: Int)] = []) throws {
        let existing = emitters
        try setEmitters(existing.map { ($0.settings, $0.capacity) } + extra)
        for (old, new) in zip(existing, emitters) {
            new.texture = old.texture
            new.transform = old.transform
            new.simulationSpace = old.simulationSpace
            new.isEmitting = old.isEmitting
            new.mesh = old.mesh
        }
    }

    /// Adds an emitter. Reallocates the particle buffer, so all particles are removed.
    @discardableResult
    public func addEmitter(_ settings: ParticleEmitter, capacity: Int) throws -> Emitter {
        try rebuild(adding: [(settings, capacity)])
        return emitters[emitters.count - 1]
    }

    /// Removes all particles from every emitter, resets their clocks, and runs warmup again.
    public func restart() {
        allEmitters.forEach { $0.restart() }
        if state != .playing {
            state = .playing
        }
    }

    // MARK: Single-emitter conveniences. These act on the first emitter.

    public var emitter: ParticleEmitter {
        get { emitters[0].settings }
        set { emitters[0].settings = newValue }
    }

    public var texture: MTLTexture? {
        get { emitters[0].texture }
        set { emitters[0].texture = newValue }
    }

    public var transform: simd_float4x4 {
        get { emitters[0].transform }
        set { emitters[0].transform = newValue }
    }

    public var simulationSpace: SimulationSpace {
        get { emitters[0].simulationSpace }
        set { emitters[0].simulationSpace = newValue }
    }

    public var isEmitting: Bool {
        get { emitters[0].isEmitting }
        set { emitters[0].isEmitting = newValue }
    }

    public func burst(_ count: Int) {
        emitters.first?.burst(count)
    }

    // MARK: Simulation

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

    /// One compute dispatch: an emitter's slice for one step.
    private struct Dispatch {
        var uniforms: SimulationUniforms
        /// Slots this step touches; see `random.w` for the first one.
        var threadCount: Int
        var mesh: EmitterMesh?
        /// The previous dispatch wrote the same slice.
        var followsSameEmitter: Bool
        /// The emitter's sub-emitters and the settings their children spawn with. Never empty; the count in
        /// `uniforms.fields.z` keeps padding unused.
        var subEmitters: [SubEmitterData]
        var subEmitterUniforms: [SimulationUniforms]
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
        uniforms.fields.z = Float(emitter.children.count)
        // Touch only slots that can hold live particles, plus those that died since the last step. A kill, or a
        // sub-emitter instance, touches all.
        let threadCount: Int
        if emitter.needsKill || emitter.isSubEmitter {
            uniforms.random.w = 0
            threadCount = emitter.capacity
        } else {
            let start = emitter.dispatchStartSerial
            uniforms.random.w = start % UInt32(emitter.capacity)
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
        return SimulationUniforms(
            emitterTransform: motion.transform,
            simulationToWorld: model,
            worldToSimulation: model.inverse,
            previousEmitterOrigin: SIMD4(motion.previousOrigin, 0),
            inheritedVelocity: SIMD4(motion.inheritedVelocity, 0),
            emitterPosition: SIMD4(settings.position, 0),
            shape: [settings.shape.kind.rawValue, settings.birthLocation.rawValue, settings.birthDirection.rawValue, 0],
            shapeParameters: {
                var parameters = settings.shape.parameters
                parameters.w = max(settings.sweepAngle, 0)
                return parameters
            }(),
            meshCounts: settings.shape == .mesh ? [UInt32(emitter.mesh?.triangleCount ?? 0), UInt32(emitter.mesh?.vertexCount ?? 0), 0, 0] : .zero,
            emitterVelocity: SIMD4(settings.velocity, settings.velocitySpread),
            gravity: SIMD4(settings.gravity, settings.drag),
            lifetime: [settings.lifetime.lowerBound, settings.lifetime.upperBound, 0, deltaTime],
            collision: [settings.restitution, settings.friction, Float(colliders.count), settings.diesOnCollision ? 1 : 0],
            rotation: [settings.angle, settings.angleVariation, settings.angularSpeed, settings.angularSpeedVariation],
            imageSequence: settings.imageSequence.map {
                [$0.initialFrame, $0.initialFrameVariation, $0.frameRate, $0.frameRateVariation]
            } ?? .zero,
            // The emitter clock, not wall time, so turbulence stays deterministic.
            fields: [Float(forceFields.count), emitter.spawner.time, 0, 0],
            variation: [max(settings.sizeVariation, 0), max(settings.restitutionVariation, 0), max(settings.frictionVariation, 0), max(settings.speedVariation, 0)],
            colorVariation: simd_max(settings.colorVariation, .zero),
            random: [emitter.seed, UInt32(emitter.capacity), UInt32(emitter.range.lowerBound), 0],
            spawn: [spawn.cursor, spawn.count, spawn.serial, emitter.needsKill ? 1 : 0]
        )
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
                info: [sub.occasionCode.rawValue, UInt32(max(sub.countPerEvent, 1)), UInt32(child.range.lowerBound), UInt32(child.capacity)],
                parameters: [sub.velocityFactor, sub.interval, 0, 0]
            ))
            let still = Spawner.Step(cursor: 0, count: 0, serial: 0)
            uniforms.append(self.uniforms(for: child, deltaTime: 0, motion: SpawnMotion(), spawn: still))
        }
        // Never bind empty arrays.
        if data.isEmpty {
            data = [SubEmitterData(info: .zero, parameters: .zero)]
            uniforms = [self.uniforms(for: emitter, deltaTime: 0, motion: SpawnMotion(), spawn: Spawner.Step(cursor: 0, count: 0, serial: 0))]
        }
        return (data, uniforms)
    }

    private func dispatches(_ emitter: Emitter, frameDeltaTime: Float) -> [Dispatch] {
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
            Dispatch(
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

    /// Advances every emitter one frame in a single compute pass. Put this before the render pass that draws the
    /// particles. The result depends only on `seed`, settings, playback calls, and the sequence of `deltaTime` values.
    /// Pass `colliders` to replace `self.colliders` this frame, and `transforms` to move emitters (matched by index;
    /// extra entries are ignored, missing ones leave the emitter where it is). Pass the camera's `view` matrix to sort
    /// emitters whose `sortMode` is `.backToFront`; without it they draw unsorted.
    public func simulate(deltaTime: Float, colliders: [Collider]? = nil, transforms: [simd_float4x4]? = nil, view: simd_float4x4? = nil) throws -> some Element {
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
        for child in subEmitterInstances {
            if let parent = child.parent, child.subEmitterIndex < parent.settings.subEmitters.count {
                child.settings = parent.settings.subEmitters[child.subEmitterIndex].settings
            }
        }
        let frameDeltaTime = min(deltaTime, 1.0 / 30.0) * max(speedFactor, 0)
        let dispatches = allEmitters.flatMap { dispatches($0, frameDeltaTime: frameDeltaTime) }
        let colliderData = colliderData(deltaTime: state == .playing ? frameDeltaTime : 0)
        let forceFieldData = forceFields.map(ForceFieldData.init)
        let placeholderMesh = placeholderMesh
        let kernel = try library.updateParticles as ComputeKernel
        let buffer = buffer
        let sorts = try sorts(view: view)
        let sortKernels = sortKernels
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            ForEach(Array(dispatches.indices), id: \.self) { index in
                // Slices are disjoint, so only consecutive steps of one emitter depend on each other.
                if dispatches[index].followsSameEmitter {
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                }
                try ComputePipeline(computeKernel: kernel) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: dispatches[index].threadCount, height: 1, depth: 1))
                }
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: dispatches[index].uniforms)
                // Never bind an empty array; the counts in uniforms keep the padding unused.
                .parameter("colliders", values: colliderData.isEmpty ? [ColliderData(.plane(normal: [0, 1, 0], distance: 0))] : colliderData)
                .parameter("forceFields", values: forceFieldData.isEmpty ? [ForceFieldData(.wind(velocity: .zero, strength: 0))] : forceFieldData)
                .parameter("meshTriangles", buffer: (dispatches[index].mesh ?? placeholderMesh).triangles)
                .parameter("meshVertices", buffer: (dispatches[index].mesh ?? placeholderMesh).vertices)
                .parameter("subEmitters", values: dispatches[index].subEmitters)
                .parameter("subEmitterUniforms", values: dispatches[index].subEmitterUniforms)
            }
            if !sorts.isEmpty {
                // Sorting reads the particles the simulation just wrote.
                EncoderBarrier(after: .dispatch, before: .dispatch)
                ForEach(Array(sorts.indices), id: \.self) { index in
                    try sortKernels.element(sorts[index], particles: buffer)
                }
            }
        }
        .barrierAfterPass(after: .dispatch, beforeQueueStages: .vertex)
        .gpuTimed("Simulate")
    }

    /// Sort work for emitters that sort back to front. Also records which emitters are sorted this frame.
    private func sorts(view: simd_float4x4?) throws -> [EmitterSort] {
        var sorts: [EmitterSort] = []
        for emitter in allEmitters {
            emitter.sortedCount = 0
            guard emitter.settings.sortMode == .backToFront, let view else {
                continue
            }
            let window = emitter.liveWindow
            guard window.count > 0 else {
                continue
            }
            if emitter.sortBuffers?.capacity != emitter.capacity {
                emitter.sortBuffers = try ParticleSortBuffers(device: device, capacity: emitter.capacity)
            }
            guard let buffers = emitter.sortBuffers else {
                continue
            }
            let cameraToWorld = view.inverse
            let parameters = ParticleSortKeyParams(
                cameraPosition: SIMD4(cameraToWorld.columns.3.xyz, 1),
                // The camera looks down its -Z axis.
                cameraForward: SIMD4(-simd_normalize(cameraToWorld.columns.2.xyz), 0),
                model: emitter.modelTransform,
                window: [UInt32(window.start), UInt32(window.count), UInt32(emitter.capacity), UInt32(emitter.range.lowerBound)]
            )
            sorts.append(EmitterSort(buffers: buffers, keyParameters: parameters, count: window.count))
            emitter.sortedCount = window.count
        }
        return sorts
    }

    // MARK: Rendering

    /// Draws every emitter's particles. Place inside a `RenderPass`. Unsorted emitters draw first, in emitter order; then
    /// sorted emitters, farthest first by the distance to their shape's center. Particles of different emitters are
    /// not interleaved.
    public func render(projection: simd_float4x4, view: simd_float4x4) throws -> some Element {
        let cameraToWorld = view.inverse
        let cameraPosition = cameraToWorld.columns.3.xyz
        let unsorted = allEmitters.filter { $0.settings.sortMode == .none }
        let sorted = allEmitters.filter { $0.settings.sortMode != .none }
            .sorted { simd_distance($0.worldCenter, cameraPosition) > simd_distance($1.worldCenter, cameraPosition) }
        let placeholderSortRecords = placeholderSortRecords
        let draws = (unsorted + sorted).map { emitter in
            EmitterDraw(emitter: emitter, viewProjection: projection * view, cameraToWorld: cameraToWorld)
        }
        let buffer = buffer
        let vertexShader = try library.particleVertex as VertexShader
        let fragmentShader = try library.particleFragment as FragmentShader
        let placeholderTexture = placeholderTexture
        let sampler = sampler
        return ForEach(Array(draws.indices), id: \.self) { index in
            let draw = draws[index]
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    for segment in draw.segments where segment.count > 0 {
                        encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segment.count, baseInstance: segment.start)
                    }
                }
            }
            .parameter("particles", buffer: buffer)
            .parameter("uniforms", value: draw.uniforms)
            .parameter("colorCurve", values: draw.colorCurve)
            .parameter("sizeCurve", values: draw.sizeCurve)
            .parameter("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
            .parameter("sprite", texture: draw.texture ?? placeholderTexture)
            .parameter("spriteSampler", samplerState: sampler)
            .renderPipelineDescriptorTransformer { descriptor in
                draw.blendMode.configure(descriptor.colorAttachments[0]!)
            }
        }
    }
}

/// Everything one emitter's draw needs, captured when the render element is built.
private struct EmitterDraw {
    var uniforms: RenderUniforms
    var colorCurve: [SIMD4<Float>]
    var sizeCurve: [Float]
    var texture: MTLTexture?
    var blendMode: ParticleBlendMode
    /// Instance ranges: the emitter's live window in the shared buffer, split in two where it wraps; or, when
    /// sorted, the sorted records.
    var segments: [(start: Int, count: Int)]
    var sortRecords: MTLBuffer?

    init(emitter: ParticleSystem.Emitter, viewProjection: simd_float4x4, cameraToWorld: simd_float4x4) {
        let settings = emitter.settings
        let sequence = emitter.texture == nil ? ImageSequence() : settings.imageSequence ?? ImageSequence()
        let opacity = settings.opacityOverLife.baked()
        colorCurve = zip(settings.colorOverLife.baked(), opacity).map { color, opacity in
            SIMD4(color.x, color.y, color.z, color.w * opacity)
        }
        sizeCurve = settings.sizeOverLife.baked()
        texture = emitter.texture
        blendMode = settings.blendMode
        if emitter.sortedCount > 0, let buffers = emitter.sortBuffers {
            // Sorted records hold absolute particle indices, so instances start at 0.
            segments = [(0, emitter.sortedCount)]
            sortRecords = buffers.recordsA
        } else {
            let base = emitter.range.lowerBound
            let window = emitter.liveWindow
            let firstCount = min(window.count, emitter.capacity - window.start)
            segments = [(base + window.start, firstCount), (base, window.count - firstCount)]
            sortRecords = nil
        }
        uniforms = RenderUniforms(
            viewProjection: viewProjection,
            model: emitter.modelTransform,
            cameraRight: SIMD4(simd_normalize(cameraToWorld.columns.0.xyz), 0),
            cameraUp: SIMD4(simd_normalize(cameraToWorld.columns.1.xyz), 0),
            options: [
                settings.blendMode.rawValue,
                emitter.texture == nil ? 0 : 1,
                UInt32(max(sequence.columns, 1)),
                UInt32(max(sequence.rows, 1)),
            ],
            imageSequence: [UInt32(max(sequence.frameCount, 1)), sequence.mode.rawValue, 0, 0],
            cameraPosition: SIMD4(cameraToWorld.columns.3.xyz, 1),
            orientation: settings.orientation.parameters,
            orientationMode: [settings.orientation.mode.rawValue, sortRecords == nil ? 0 : 1, 0, 0]
        )
    }
}

extension ParticleBlendMode {
    // The fragment shader outputs premultiplied color, so every blended mode uses `.one` for the source.
    func configure(_ attachment: MTL4RenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.blendingState = .disabled
            return
        case .additive:
            attachment.destinationRGBBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        case .screen:
            attachment.destinationRGBBlendFactor = .oneMinusSourceColor
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        default:
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        attachment.blendingState = .enabled
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x, y, z) }
}
