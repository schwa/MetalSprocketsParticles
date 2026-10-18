import Foundation
import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh

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
        /// The mesh `mesh` was made from by `ParticleSystem.apply(_:)`, to skip remaking it.
        var meshSource: Mesh?
        /// Animates `mesh` each frame, by the emitter's own clock.
        public var meshDeformation: MeshDeformation = .none
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
        /// What each of `settings.triggers` saw last time, by trigger index.
        var triggerMemory: [Int: TriggerMemory] = [:]

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

        /// True when the emitter is done: it will not spawn on its own again (its `emissionOverTime` has ended at zero,
        /// its single emission period is over, its birth rate is zero, or `isEmitting` is off), it has no pending burst
        /// or triggers, and every particle it and its sub-emitters made has died. Use it to remove finite effects.
        public var isFinished: Bool {
            guard !needsWarmup, settings.triggers.isEmpty, spawner.pendingBurst == 0 else {
                return false
            }
            guard !isEmitting || Spawner.isEmissionOver(time: spawner.time, emitter: settings) else {
                return false
            }
            let childLifetime = settings.subEmitters.map(\.settings.lifetime.upperBound).max() ?? 0
            return spawner.time >= spawner.lastBirthTime + spawner.maxLifetime + childLifetime
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
    /// Positions of app objects, by name, for `EmissionTrigger.Condition.objectEnters`. Update them every frame.
    public var trackedObjects: [String: SIMD3<Float>] = [:]
    /// Seconds of simulation since the system started or restarted. Drives timer triggers.
    public internal(set) var simulationTime: Float = 0
    var pendingEvents: [String] = []
    /// Monotonic GPU counters: collider hits, then particles entering trigger volumes.
    let triggerCounters: MTLBuffer
    /// Live-particle counts, one slot per recent frame; see `aliveParticleCount`.
    let aliveCounters: MTLBuffer
    /// Frames planned so far; picks the alive-counter slot.
    var frameIndex = 0
    /// The alive-counter slot this frame's dispatches add to.
    var aliveCounterSlot: UInt32 = 0

    /// Live particles, counted on the GPU a few frames ago (the latest count that is surely finished). For statistics
    /// displays; 0 until enough frames have run.
    public internal(set) var aliveParticleCount = 0

    /// Fires `EmissionTrigger.Condition.event(name)` triggers at the start of the next `simulate`.
    public func send(event name: String) {
        pendingEvents.append(name)
    }

    /// What `apply(_:)` last built the buffer for. Empty after `setEmitters`, so the next `apply` rebuilds.
    var appliedLayout: [AppliedEmitter] = []
    /// Sprite textures made by `apply(_:)`.
    var spriteTextures: [ParticleSprite: MTLTexture] = [:]
    /// User functions compiled by `visibleFunction(for:)`.
    var compiledFunctions: [FunctionKey: VisibleFunction] = [:]

    /// Instances for every emitter's `settings.subEmitters`, stored after all emitters in the shared buffer.
    private(set) var subEmitterInstances: [Emitter] = []
    /// `countPerEvent` of each emitter's sub-emitters when the buffer was built, to notice structural changes.
    var subEmitterLayout: [[Int]] = []

    /// Emitters and sub-emitter instances, in buffer order.
    var allEmitters: [Emitter] {
        emitters + subEmitterInstances
    }
    /// World-space colliders shared by every emitter. Update them per frame to move them; their velocity is derived
    /// from the change since the previous frame.
    public var colliders: [Collider] = []
    /// World-space force fields shared by every emitter.
    public var forceFields: [ForceField] = []
    /// Lights for emitters with `isLit`. At most `PARTICLE_MAX_LIGHTS` are used.
    public var lights: [ParticleLight] = []
    /// Light that lit particles receive from every direction.
    public var ambientLight: SIMD3<Float> = [0.25, 0.25, 0.25]
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
    // Colliders from the previous frame, used to derive collider velocity. Nil before the first frame, unlike empty.
    // swiftlint:disable:next discouraged_optional_collection
    var previousColliders: [Collider]?

    /// The system's default Metal device. Every Mac and device this package supports has one.
    public static func defaultDevice() -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            preconditionFailure("No Metal device.")
        }
        return device
    }

    /// True when every emitter is finished (see `Emitter.isFinished`): nothing will spawn and nothing is alive.
    public var isFinished: Bool {
        emitters.allSatisfy(\.isFinished)
    }

    /// Total particles across all emitters.
    public var capacity: Int {
        allEmitters.reduce(0) { $0 + $1.capacity }
    }

    /// Creates a system with one emitter per entry in `emitters`, each with room for `capacity` particles.
    public init(device: MTLDevice = ParticleSystem.defaultDevice(), emitters: [ParticleEmitter], capacity: Int, seed: UInt32 = 0) throws {
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
        let counterLength = Int(PARTICLE_TRIGGER_MAX_COLLIDERS + PARTICLE_TRIGGER_MAX_VOLUMES) * MemoryLayout<UInt32>.stride
        guard let triggerCounters = device.makeBuffer(length: counterLength, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        triggerCounters.contents().initializeMemory(as: UInt8.self, repeating: 0, count: counterLength)
        triggerCounters.label = "Particle trigger counters"
        self.triggerCounters = triggerCounters
        let aliveLength = Int(PARTICLE_ALIVE_COUNTER_SLOTS) * MemoryLayout<UInt32>.stride
        guard let aliveCounters = device.makeBuffer(length: aliveLength, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        aliveCounters.contents().initializeMemory(as: UInt8.self, repeating: 0, count: aliveLength)
        aliveCounters.label = "Particle alive counters"
        self.aliveCounters = aliveCounters
        buffer = try Self.makeBuffer(device: device, count: 1)

        try setEmitters(emitters.map { ($0, capacity) })
    }

    /// Creates a system with a single emitter.
    public convenience init(device: MTLDevice = ParticleSystem.defaultDevice(), capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
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
        appliedLayout = []
        self.emitters = created
        subEmitterInstances = children
        subEmitterLayout = Self.subEmitterLayout(of: created)
        return created
    }

    static func subEmitterLayout(of emitters: [Emitter]) -> [[Int]] {
        emitters.map { $0.settings.subEmitters.map { max($0.countPerEvent, 1) } }
    }

    /// Rebuilds the buffer for the current emitters, keeping runtime state that is not part of the settings.
    func rebuild(adding extra: [(settings: ParticleEmitter, capacity: Int)] = []) throws {
        let existing = emitters
        let layout = appliedLayout
        try setEmitters(existing.map { ($0.settings, $0.capacity) } + extra)
        // Same emitters, so a later `apply` with the same descriptions need not rebuild again.
        if extra.isEmpty {
            appliedLayout = layout
        }
        for (old, new) in zip(existing, emitters) {
            new.texture = old.texture
            new.transform = old.transform
            new.simulationSpace = old.simulationSpace
            new.isEmitting = old.isEmitting
            new.mesh = old.mesh
            new.meshSource = old.meshSource
            new.meshDeformation = old.meshDeformation
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
        simulationTime = 0
        emitters.forEach { $0.triggerMemory = [:] }
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

    // Nil collections mean "leave as they are", which differs from empty ("none").
    // swiftlint:disable discouraged_optional_collection

    /// Advances every emitter one frame in a single compute pass. Put this before the render pass that draws the
    /// particles. The result depends only on `seed`, settings, playback calls, and the sequence of `deltaTime` values.
    /// Pass `colliders` to replace `self.colliders` this frame, and `transforms` to move emitters (matched by index;
    /// extra entries are ignored, missing ones leave the emitter where it is), and `trackedObjects` to replace
    /// `self.trackedObjects`. Pass the camera's `view` matrix to sort emitters whose `sortMode` is `.backToFront`;
    /// without it they draw unsorted.
    public func simulate(
        deltaTime: Float,
        colliders: [Collider]? = nil,
        transforms: [simd_float4x4]? = nil,
        trackedObjects: [String: SIMD3<Float>]? = nil,
        view: simd_float4x4? = nil
    ) throws -> some Element {
        // swiftlint:enable discouraged_optional_collection
        let plan = try planFrame(deltaTime: deltaTime, colliders: colliders, transforms: transforms, trackedObjects: trackedObjects)
        return try encode(plan, sorts: try sorts(view: view))
    }

    /// Records the GPU work for `plan`, then any sorts. No CPU state changes here.
    private func encode(_ plan: FramePlan, sorts: [EmitterSort]) throws -> some Element {
        let dispatches = plan.dispatches
        let volumeData = plan.triggerVolumes
        let triggerCounters = triggerCounters
        let aliveCounters = aliveCounters
        let placeholderMesh = placeholderMesh
        let kernel = try library.updateParticles as ComputeKernel
        let buffer = buffer
        let functionTables = try dispatches.map(functionTables)
        let sortKernels = sortKernels
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            ForEach(Array(dispatches.indices), id: \.self) { index in
                // Slices are disjoint, so only consecutive steps of one emitter depend on each other.
                if dispatches[index].followsSameEmitter {
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                }
                let tables = functionTables[index]
                try ComputePipeline(computeKernel: kernel) {
                    try ComputeDispatch(threadsPerGrid: MTLSize(width: dispatches[index].threadCount, height: 1, depth: 1))
                        .visibleFunctionTable(ParticleFunctionSlot.update.tableName, function: tables.functions[0])
                        .visibleFunctionTable(ParticleFunctionSlot.spawn.tableName, function: tables.functions[1])
                        .visibleFunctionTable(ParticleFunctionSlot.collision.tableName, function: tables.functions[2])
                        .visibleFunctionTable(ParticleFunctionSlot.death.tableName, function: tables.functions[3])
                }
                .linkedFunctions(tables.linked)
                .parameter(ParticleFunctionSlot.update.parametersName, values: tables.parameters[0])
                .parameter(ParticleFunctionSlot.spawn.parametersName, values: tables.parameters[1])
                .parameter(ParticleFunctionSlot.collision.parametersName, values: tables.parameters[2])
                .parameter(ParticleFunctionSlot.death.parametersName, values: tables.parameters[3])
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: dispatches[index].uniforms)
                // Never bind an empty array; the counts in uniforms keep the padding unused.
                .parameter("colliders", values: dispatches[index].colliders.isEmpty ? [ColliderData(.plane(normal: [0, 1, 0], distance: 0))] : dispatches[index].colliders)
                .parameter("forceFields", values: dispatches[index].forceFields.isEmpty ? [ForceFieldData(.wind(velocity: .zero, strength: 0))] : dispatches[index].forceFields)
                .parameter("meshTriangles", buffer: (dispatches[index].mesh ?? placeholderMesh).triangles)
                .parameter("meshVertices", buffer: (dispatches[index].mesh ?? placeholderMesh).vertices)
                .parameter("meshIndices", buffer: (dispatches[index].mesh ?? placeholderMesh).indices)
                // The rest vertices stand in when there are no deformed positions; the zero stride keeps them unread.
                .parameter("meshDeformedPositions", buffer: dispatches[index].mesh?.deformedPositions ?? (dispatches[index].mesh ?? placeholderMesh).vertices)
                .parameter("subEmitters", values: dispatches[index].subEmitters)
                .parameter("subEmitterUniforms", values: dispatches[index].subEmitterUniforms)
                .parameter("triggerCounters", buffer: triggerCounters)
                .parameter("aliveCounters", buffer: aliveCounters)
                .parameter("triggerVolumes", values: volumeData.isEmpty ? [TriggerVolume.sphere(center: .zero, radius: 0).data] : volumeData)
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
                cameraPosition: cameraToWorld.columns.3.xyz,
                // The camera looks down its -Z axis.
                cameraForward: -simd_normalize(cameraToWorld.columns.2.xyz),
                model: emitter.modelTransform,
                firstSlot: UInt32(window.start),
                liveCount: UInt32(window.count),
                capacity: UInt32(emitter.capacity),
                sliceStart: UInt32(emitter.range.lowerBound)
            )
            sorts.append(EmitterSort(buffers: buffers, keyParameters: parameters, count: window.count))
            emitter.sortedCount = window.count
        }
        return sorts
    }

    // MARK: Rendering

    /// Draws every emitter's particles. Place inside a `RenderPass`. Unsorted emitters draw first, in emitter order; then
    /// sorted emitters, farthest first by the distance to their shape's center. Particles of different emitters are
    /// not interleaved. Pass the scene's depth, the same size as the render target and rendered with `projection`, to
    /// soften emitters with `softness`; it is read, not tested against, so it must not be the pass's depth attachment.
    public func render(projection: simd_float4x4, view: simd_float4x4, sceneDepth: MTLTexture? = nil) throws -> some Element {
        let cameraToWorld = view.inverse
        let cameraPosition = cameraToWorld.columns.3.xyz
        let unsorted = allEmitters.filter { $0.settings.sortMode == .none }
        let sorted = allEmitters.filter { $0.settings.sortMode != .none }
            .sorted { simd_distance($0.worldCenter, cameraPosition) > simd_distance($1.worldCenter, cameraPosition) }
        let placeholderSortRecords = placeholderSortRecords
        let lighting = EmitterDraw.Lighting(ambient: ambientLight, lightCount: min(lights.count, Int(PARTICLE_MAX_LIGHTS)))
        let draws = (unsorted + sorted).map { emitter in
            EmitterDraw(emitter: emitter, projection: projection, view: view, lighting: lighting, hasSceneDepth: sceneDepth != nil)
        }
        let lightData = lights.prefix(Int(PARTICLE_MAX_LIGHTS)).map(ParticleLightData.init)
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
            // Never bind an empty array; lightCount keeps the padding unused.
            .parameter("lights", values: lightData.isEmpty ? [ParticleLightData()] : lightData)
            .parameter("sceneDepth", texture: sceneDepth ?? placeholderTexture)
            .renderPipelineDescriptorTransformer { descriptor in
                if let attachment = descriptor.colorAttachments[0] {
                    draw.blendMode.configure(attachment)
                }
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

    struct Lighting {
        var ambient: SIMD3<Float>
        var lightCount: Int
    }

    init(emitter: ParticleSystem.Emitter, projection: simd_float4x4, view: simd_float4x4, lighting: Lighting, hasSceneDepth: Bool) {
        let viewProjection = projection * view
        let cameraToWorld = view.inverse
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
            cameraRight: simd_normalize(cameraToWorld.columns.0.xyz),
            cameraUp: simd_normalize(cameraToWorld.columns.1.xyz),
            cameraPosition: cameraToWorld.columns.3.xyz,
            fixedNormal: settings.orientation.fixedNormal,
            velocityStretch: settings.orientation.velocityStretch,
            orientationMode: settings.orientation.mode,
            blendMode: settings.blendMode,
            hasTexture: emitter.texture == nil ? 0 : 1,
            sheetColumns: UInt32(max(sequence.columns, 1)),
            sheetRows: UInt32(max(sequence.rows, 1)),
            frameCount: UInt32(max(sequence.frameCount, 1)),
            sequenceMode: sequence.mode,
            readsSortRecords: sortRecords == nil ? 0 : 1,
            // The camera looks down its -Z axis.
            cameraForward: -simd_normalize(cameraToWorld.columns.2.xyz),
            ambientLight: lighting.ambient,
            isLit: settings.isLit ? 1 : 0,
            lightCount: UInt32(lighting.lightCount),
            softness: max(settings.softness, 0),
            hasSceneDepth: hasSceneDepth ? 1 : 0,
            // Clip z = a * zView + b and clip w = c * zView, so depth d = (a * zView + b) / (c * zView).
            depthUnproject: [projection.columns.2.z, projection.columns.3.z, projection.columns.2.w]
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
