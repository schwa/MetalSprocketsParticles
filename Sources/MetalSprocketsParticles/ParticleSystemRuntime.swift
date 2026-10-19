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
public final class ParticleSystemRuntime {
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
        // The description's `isEmitting` when last applied; nil until the first apply, so that one always sets it.
        // swiftlint:disable:next discouraged_optional_boolean
        var appliedIsEmitting: Bool?
        /// Triangles for `EmitterShape.mesh`.
        public var mesh: EmitterMesh?
        /// The mesh `mesh` was made from by `ParticleSystemRuntime.apply(_:)`, to skip remaking it.
        var meshSource: Mesh?
        /// Whether the last frame culled this emitter (its `cullingRadius` sphere was outside the view).
        public internal(set) var isCulled = false
        /// The last frame's distance LOD birth rate multiplier.
        public internal(set) var lodRateScale: Float = 1
        /// The point cache `mesh` was made from by `apply(_:)`.
        var pointsSource: [EmitterPoint]? // swiftlint:disable:this discouraged_optional_collection
        /// The image `mesh` was sampled from by `apply(_:)`.
        var imageSource: EmitterImage?
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
            guard !needsWarmup, settings.triggers.isEmpty, spawner.pendingBurst == 0, pendingPositionedBursts.isEmpty else {
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

        /// Emits `count` particles as if the emitter's origin were at `position`, on the next playing step; the shape
        /// keeps its usual offset (`settings.position`) from that origin. The emitter does not move. `position` is in world space (emitter space
        /// for local-space emitters); with the overlay camera that is a point in the view, such as a tap location.
        public func burst(_ count: Int, at position: SIMD3<Float>) {
            if count > 0 {
                pendingPositionedBursts.append((count, position))
            }
        }

        /// Bursts from `burst(_:at:)`, spawned as their own steps by the next playing frame.
        var pendingPositionedBursts: [(count: Int, position: SIMD3<Float>)] = []

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
    let eventCursor: MTLBuffer
    let eventRecords: MTLBuffer
    /// The sequence number of the last event read, so each event is reported once.
    var lastEventSequence: UInt32 = 0
    /// Events read at the start of the last `simulate`, oldest first. GPU work is read a frame or two after it runs,
    /// so events arrive that late. Only emitters with `reportsCollisions` or `reportsDeaths` produce them.
    public internal(set) var recentEvents: [ParticleEvent] = []
    /// Events lost since the system was made, because more than `ParticleEvent.capacity` happened between reads.
    public internal(set) var droppedEventCount = 0
    /// Lights gathered from emitting particles (`ParticleEmitter.light`) by the last `simulate`: `particleLightCount`
    /// `ParticleLightData` values, in world space. The GPU writes it during the simulation, so read it on the GPU after
    /// the simulation, or on the CPU once that frame has finished (see `emittedLights()`).
    public let particleLightBuffer: MTLBuffer
    public internal(set) var particleLightCount = 0
    var particleLightGathers: [ParticleLightGatherData] = []
    /// Each gather's emitter's color over life, for picking the brightest particles.
    var particleLightColorCurves: [[SIMD4<Float>]] = []
    /// Points between particles' trails in `trails`; 0 without trails.
    var trailStride = 0
    /// Vertex buffers for `ParticleEmitter.particleMesh`, made once per shape.
    var particleMeshBuffers: [ParticleMesh: (buffer: MTLBuffer, vertexCount: Int)] = [:]
    /// The scene depth `collidesWithSceneDepth` emitters bounce off. `renderSceneDepth(into:projection:view:)` sets it
    /// each frame, so the simulation uses the depth of the frame before. Set it yourself to use your own depth.
    public var collisionDepth: SceneDepthCollision?
    /// The camera of the last `render`, for LOD and culling.
    var cullingCamera: CullingCamera?
    /// Live-particle counts, one slot per recent frame; see `aliveParticleCount`.
    let aliveCounters: MTLBuffer
    /// Frames planned so far; picks the alive-counter slot.
    var frameIndex = 0
    /// The alive-counter slot this frame's dispatches add to.
    var aliveCounterSlot: UInt32 = 0

    /// Live particles, counted on the GPU a few frames ago (the latest count that is surely finished). For statistics
    /// displays; 0 until enough frames have run.
    public internal(set) var aliveParticleCount = 0
    /// Particles born (spawned or written as sub-emitter children) and particles that died in one recent frame, read a
    /// few frames late like `aliveParticleCount`.
    public internal(set) var bornParticleCount = 0
    public internal(set) var diedParticleCount = 0
    /// Births and deaths per second over the last `particleRateWindow` frames, for statistics displays.
    public var birthsPerSecond: Double { particleRates.births }
    public var deathsPerSecond: Double { particleRates.deaths }
    /// Frames the per-second rates average over.
    public static let particleRateWindow = 30
    /// Recent frames' (seconds, births, deaths), newest last.
    var recentParticleCounts: [(seconds: Float, born: Int, died: Int)] = []

    /// Fires `EmissionTrigger.Condition.event(name)` triggers at the start of the next `simulate`.
    public func send(event name: String) {
        pendingEvents.append(name)
    }

    /// What `apply(_:)` last built the buffer for. Empty after `setEmitters`, so the next `apply` rebuilds.
    var appliedLayout: [AppliedEmitter] = []
    /// Sprite textures made by `apply(_:)`.
    var spriteTextures: [ParticleSprite: MTLTexture] = [:]
    /// Textures for `ParticleEmitter.colorImage`, made once per image.
    var colorImageTextures: [Data: MTLTexture] = [:]
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
    /// GPU copies of the colliders' distance field grids.
    var signedDistanceFieldTextures: [SignedDistanceFieldTexture] = []
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
    /// `ParticleState.custom`, one float4 per particle. Made the first time an emitter has user functions, so other
    /// systems do not pay for it; dropped when the particle buffer is rebuilt.
    private(set) var attributes: MTLBuffer?
    /// Attribute entries per particle in `attributes`: the largest `customAttributeCount` among emitters with functions.
    private(set) var attributeStride = 1
    /// Recent positions for `ParticleEmitter.trail`, made when an emitter has a trail.
    var trails: MTLBuffer?
    /// Reverse Z: depth runs from 1 at the near plane to 0 at the far plane, for better precision at a distance. Use a
    /// reversed projection (`reversingDepth(_:)`; `ParticlePlayer` does this itself) and clear depth buffers to 0.
    /// Scene depth, solid colliders, mesh particles, soft particles, and depth collision all follow it.
    public var reverseZ = false
    /// Draws particles in false colors or as wireframes instead of their own colors. Simulation is unaffected.
    public var debugView: ParticleDebugView = .none
    /// Speeds for `ParticleDebugView.speed`; the upper bound is also the seconds for `.lifeRemaining`.
    public var debugRange: ClosedRange<Float> = 0...5
    /// See `colliderSolidVertices(planeExtent:)`.
    var solidVertexCache: (colliders: [Collider], planeExtent: Float, vertices: [SIMD4<Float>])?
    /// For `ParticleEmitter.flocking`, made when an emitter flocks.
    var flockingBuffers: FlockingBuffers?
    var flocks: [FlockData] = []
    let library: ShaderLibrary
    private let sampler: MTLSamplerState
    /// Bound in place of a missing texture; the shader ignores it.
    private let placeholderTexture: MTLTexture
    /// Bound in unused distance field slots; colliders never point at them.
    private let placeholderFieldTexture: MTLTexture
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
    public init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), emitters: [ParticleEmitter], capacity: Int, seed: UInt32 = 0) throws {
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
        let fieldDescriptor = MTLTextureDescriptor()
        fieldDescriptor.textureType = .type3D
        fieldDescriptor.pixelFormat = .r32Float
        guard let placeholderFieldTexture = device.makeTexture(descriptor: fieldDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        placeholderFieldTexture.label = "Particle placeholder distance field"
        self.placeholderFieldTexture = placeholderFieldTexture
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
        guard let eventCursor = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let eventRecords = device.makeBuffer(length: MemoryLayout<ParticleEventRecord>.stride * ParticleEvent.capacity, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        eventCursor.label = "Particle event cursor"
        eventRecords.label = "Particle events"
        self.eventCursor = eventCursor
        self.eventRecords = eventRecords
        guard let particleLightBuffer = device.makeBuffer(length: MemoryLayout<ParticleLightData>.stride * Int(PARTICLE_MAX_PARTICLE_LIGHTS), options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        particleLightBuffer.label = "Particle lights"
        self.particleLightBuffer = particleLightBuffer
        // Live, born, and died counts, one run of slots each.
        let aliveLength = 3 * Int(PARTICLE_ALIVE_COUNTER_SLOTS) * MemoryLayout<UInt32>.stride
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
    public convenience init(device: MTLDevice = ParticleSystemRuntime.defaultDevice(), capacity: Int, emitter: ParticleEmitter = ParticleEmitter(), seed: UInt32 = 0) throws {
        try self.init(device: device, emitters: [emitter], capacity: capacity, seed: seed)
    }

    /// `total + capacity`, or `tooManyParticles` when it overflows or no buffer could hold that many particles.
    private static func checkedTotal(_ total: Int, adding capacity: Int) throws -> Int {
        let (sum, overflow) = total.addingReportingOverflow(capacity)
        guard !overflow, sum <= Int(UInt32.max), sum.multipliedReportingOverflow(by: MemoryLayout<Particle>.stride).overflow == false else {
            throw ParticleSystemRuntimeError.tooManyParticles
        }
        return sum
    }

    private static func makeBuffer(device: MTLDevice, count: Int) throws -> MTLBuffer {
        // All particles start dead (lifetime 0).
        let length = MemoryLayout<Particle>.stride * max(count, 1)
        guard length <= device.maxBufferLength else {
            throw ParticleSystemRuntimeError.tooManyParticles
        }
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
            start = try Self.checkedTotal(start, adding: capacity)
        }
        // Sub-emitter instances follow all emitters, one level at a time, so each level dispatches after its parents.
        // Each parent slot owns countPerEvent child slots, so capacity multiplies with depth.
        var children: [Emitter] = []
        var level = created
        for _ in 0..<Self.maxSubEmitterDepth {
            var nextLevel: [Emitter] = []
            for parent in level {
                for (subIndex, sub) in parent.settings.subEmitters.enumerated() {
                    // Effect files can ask for anything; overflow or an impossible buffer is an error, not a crash.
                    let (capacity, overflow) = parent.capacity.multipliedReportingOverflow(by: max(sub.countPerEvent, 1))
                    guard !overflow else {
                        throw ParticleSystemRuntimeError.tooManyParticles
                    }
                    let child = Emitter(settings: sub.settings, capacity: capacity, range: start..<(start + capacity), seed: emitterSeed(created.count + children.count))
                    child.parent = parent
                    child.subEmitterIndex = subIndex
                    child.needsWarmup = false
                    parent.children.append(child)
                    children.append(child)
                    nextLevel.append(child)
                    start = try Self.checkedTotal(start, adding: capacity)
                }
            }
            level = nextLevel
        }
        buffer = try Self.makeBuffer(device: device, count: start)
        attributes = nil
        appliedLayout = []
        self.emitters = created
        subEmitterInstances = children
        subEmitterLayout = Self.subEmitterLayout(of: created)
        return created
    }

    /// How deep sub-emitters nest: children, grandchildren, and great-grandchildren. Deeper ones are ignored.
    public static let maxSubEmitterDepth = 3

    /// The shape of every emitter's sub-emitter tree, so a change in nesting or counts triggers a rebuild.
    static func subEmitterLayout(of emitters: [Emitter]) -> [[Int]] {
        func layout(_ settings: ParticleEmitter, depth: Int) -> [Int] {
            guard depth < maxSubEmitterDepth else {
                return []
            }
            // Each sub-emitter: its count, its own subtree, then a -1 marker closing it.
            return settings.subEmitters.flatMap { [max($0.countPerEvent, 1)] + layout($0.settings, depth: depth + 1) + [-1] }
        }
        return emitters.map { layout($0.settings, depth: 0) }
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
            new.appliedIsEmitting = old.appliedIsEmitting
            new.mesh = old.mesh
            new.meshSource = old.meshSource
            new.pointsSource = old.pointsSource
            new.imageSource = old.imageSource
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

    /// Emits `count` particles from the first emitter at `position`. See `Emitter.burst(_:at:)`.
    public func burst(_ count: Int, at position: SIMD3<Float>) {
        emitters.first?.burst(count, at: position)
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
        readEvents()
        var plan = try planFrame(deltaTime: deltaTime, colliders: colliders, transforms: transforms, trackedObjects: trackedObjects)
        let trailStride = UInt32(try makeTrailsIfNeeded())
        for index in plan.dispatches.indices {
            plan.dispatches[index].uniforms.trailStride = trailStride
            for child in plan.dispatches[index].subEmitterUniforms.indices {
                plan.dispatches[index].subEmitterUniforms[child].trailStride = trailStride
            }
        }
        self.trailStride = Int(trailStride)
        flocks = try planFlocking()
        try makeAttributesIfNeeded(for: plan)
        planParticleLights()
        return try encode(plan, sorts: try sorts(view: view))
    }

    private func makeAttributesIfNeeded(for plan: FramePlan) throws {
        let withFunctions = plan.dispatches.filter { dispatch in
            let uniforms = dispatch.uniforms
            return uniforms.hasUpdateFunction | uniforms.hasSpawnFunction | uniforms.hasCollisionFunction | uniforms.hasDeathFunction != 0
        }
        let stride = withFunctions.map { Int($0.uniforms.customAttributeCount) }.max() ?? 0
        // Made once, and again only when an emitter asks for more attributes (which clears them).
        guard stride > 0, attributes == nil || stride > attributeStride else {
            return
        }
        attributeStride = stride
        // New Metal buffers are zero-filled, which is what custom starts as.
        guard let attributes = device.makeBuffer(length: buffer.length / MemoryLayout<Particle>.stride * stride * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
            throw CocoaError(.featureUnsupported)
        }
        attributes.label = "Particle attributes"
        self.attributes = attributes
    }

    /// Records the GPU work for `plan`, then any sorts. No CPU state changes here.
    private func encode(_ plan: FramePlan, sorts: [EmitterSort]) throws -> some Element {
        let dispatches = plan.dispatches
        let volumeData = plan.triggerVolumes
        let triggerCounters = triggerCounters
        let eventCursor = eventCursor
        let particleLightGathers = particleLightGathers
        let particleLightColorCurves = particleLightColorCurves
        let particleLightBuffer = particleLightBuffer
        let gatherKernel = try library.gatherParticleLights as ComputeKernel
        var depthCollision = collisionDepth?.data ?? DepthCollisionData()
        depthCollision.reverseZ = reverseZ ? 1 : 0
        let trailBuffer = trails ?? placeholderMesh.vertices
        let flocks = flocks
        let flockingBuffers = flockingBuffers
        let steeringBuffer = flockingBuffers?.steering ?? placeholderMesh.vertices
        let depthTexture = collisionDepth?.depth.texture ?? placeholderTexture
        let fieldTextures = signedDistanceFieldTextureSlots(placeholder: placeholderFieldTexture)
        let eventRecords = eventRecords
        let aliveCounters = aliveCounters
        let placeholderMesh = placeholderMesh
        let kernel = try library.updateParticles as ComputeKernel
        let buffer = buffer
        // Without attributes, a count of 0 keeps the one-entry placeholder unread.
        let attributes = attributes ?? placeholderMesh.vertices
        let attributeCount = self.attributes == nil ? UInt32(0) : UInt32(buffer.length / MemoryLayout<Particle>.stride)
        let attributeStride = UInt32(self.attributeStride)
        let functionTables = try dispatches.map(functionTables)
        let sortKernels = sortKernels
        return try ComputePass {
            // Previous frame's vertex stage reads the buffer we are about to write.
            QueueBarrier(after: .vertex, before: .dispatch)
            if let flockingBuffers, !flocks.isEmpty {
                try flockingPasses(flocks, buffers: flockingBuffers, particles: buffer)
                // The update reads the steering.
                EncoderBarrier(after: .dispatch, before: .dispatch)
            }
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
                .parameter("attributes", buffer: attributes)
                .parameter("attributeCount", value: attributeCount)
                .parameter("attributeStride", value: attributeStride)
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
                .parameter("eventCursor", buffer: eventCursor)
                .parameter("events", buffer: eventRecords)
                .parameter("pathPoints", values: plan.pathPoints)
                .parameter("birthColorCurve", values: dispatches[index].birthColorCurve)
                .parameter("depthCollision", value: depthCollision)
                .parameter("sceneDepth", texture: depthTexture)
                .parameter("signedDistanceFields", textures: fieldTextures)
                .parameter("trails", buffer: trailBuffer)
                .parameter("steering", buffer: steeringBuffer)
                .parameter("aliveCounters", buffer: aliveCounters)
                .parameter("triggerVolumes", values: volumeData.isEmpty ? [TriggerVolume.sphere(center: .zero, radius: 0).data] : volumeData)
            }
            if !particleLightGathers.isEmpty {
                // Lights come from the particles the simulation just wrote.
                EncoderBarrier(after: .dispatch, before: .dispatch)
                ForEach(Array(particleLightGathers.indices), id: \.self) { index in
                    try ComputePipeline(computeKernel: gatherKernel) {
                        try ComputeDispatch(threadsPerGrid: MTLSize(width: Int(particleLightGathers[index].count), height: 1, depth: 1))
                    }
                    .parameter("particles", buffer: buffer)
                    .parameter("gather", value: particleLightGathers[index])
                    .parameter("colorCurve", values: particleLightColorCurves[index])
                    .parameter("particleLights", buffer: particleLightBuffer)
                }
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
        cullingCamera = CullingCamera(position: cameraPosition, viewProjection: projection * view)
        let visible = allEmitters.filter { !$0.isOutsideView(camera: cullingCamera) }
        let unsorted = visible.filter { $0.settings.sortMode == .none }
        let sorted = visible.filter { $0.settings.sortMode != .none }
            .sorted { simd_distance($0.worldCenter, cameraPosition) > simd_distance($1.worldCenter, cameraPosition) }
        let placeholderSortRecords = placeholderSortRecords
        let lighting = EmitterDraw.Lighting(ambient: ambientLight, lightCount: min(lights.count, Int(PARTICLE_MAX_LIGHTS)), particleLightCount: particleLightCount)
        let particleLightBuffer = particleLightBuffer
        let draws = try (unsorted + sorted).map { emitter in
            var draw = EmitterDraw(emitter: emitter, projection: projection, view: view, lighting: lighting, hasSceneDepth: sceneDepth != nil)
            draw.mesh = try emitter.settings.particleMesh.flatMap(vertexBuffer(for:))
            if draw.mesh != nil {
                // Solid shapes: the fragment shader's procedural dot is fully covered at the center.
                draw.uniforms.hasTexture = 0
            }
            if let image = emitter.settings.colorImage, let texture = colorImageTexture(for: image) {
                draw.colorImage = texture
                draw.uniforms.hasColorImage = 1
                draw.uniforms.colorImageOrigin = image.origin
                draw.uniforms.colorImageU = image.width
                draw.uniforms.colorImageV = image.height
            }
            if debugView != .none {
                draw.uniforms.debugMode = debugView.gpuMode
                draw.uniforms.debugEmitterIndex = UInt32(allEmitters.firstIndex { $0 === emitter } ?? 0)
                draw.uniforms.debugSliceStart = UInt32(emitter.range.lowerBound)
                draw.uniforms.debugCapacity = UInt32(emitter.capacity)
                draw.uniforms.debugRange = [debugRange.lowerBound, debugRange.upperBound]
                if let blendMode = debugView.blendMode {
                    draw.blendMode = blendMode
                    draw.uniforms.blendMode = blendMode
                }
                draw.wireframe = debugView == .wireframe
            }
            if let ribbon = emitter.settings.ribbon {
                let window = emitter.liveWindow
                draw.uniforms.ribbonSliceStart = UInt32(emitter.range.lowerBound)
                draw.uniforms.ribbonCapacity = UInt32(emitter.capacity)
                draw.uniforms.ribbonWindowStart = UInt32(window.start)
                draw.uniforms.ribbonWindowCount = UInt32(window.count)
                draw.uniforms.ribbonTapers = ribbon.tapers ? 1 : 0
                draw.isRibbon = true
            }
            if let trail = emitter.settings.trail, trails != nil, trailStride > 0 {
                draw.uniforms.trailPointCount = UInt32(min(trail.clampedPointCount, trailStride))
                draw.uniforms.trailStride = UInt32(trailStride)
                draw.uniforms.trailTapers = trail.tapers ? 1 : 0
                draw.uniforms.trailFades = trail.fades ? 1 : 0
            }
            return draw
        }
        let meshVertexShader = try library.particleMeshVertex as VertexShader
        let depthCompare = depthCompareFunction
        let trailVertexShader = try library.particleTrailVertex as VertexShader
        let ribbonVertexShader = try library.particleRibbonVertex as VertexShader
        let trailBuffer = trails ?? placeholderMesh.vertices
        let lightData = lights.prefix(Int(PARTICLE_MAX_LIGHTS)).map(ParticleLightData.init)
        let buffer = buffer
        let vertexShader = try library.particleVertex as VertexShader
        let fragmentShader = try library.particleFragment as FragmentShader
        let placeholderTexture = placeholderTexture
        let sampler = sampler
        return ForEach(Array(draws.indices), id: \.self) { index in
            let draw = draws[index]
            if draw.isRibbon {
                try RenderPipeline(vertexShader: ribbonVertexShader, fragmentShader: fragmentShader) {
                    Draw { encoder in
                        encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill)
                        let count = Int(draw.uniforms.ribbonWindowCount)
                        if count > 1 {
                            encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: count * 2, instanceCount: 1, baseInstance: 0)
                        }
                    }
                }
                .parameter("colorImage", texture: draw.colorImage ?? placeholderTexture)
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: draw.uniforms)
                .parameter("colorCurve", values: draw.colorCurve)
                .parameter("sizeCurve", values: draw.sizeCurve)
                .parameter("extraColorCurves", values: draw.extraColorCurves)
                .parameter("sprite", texture: draw.texture ?? placeholderTexture)
                .parameter("spriteSampler", samplerState: sampler)
                .parameter("lights", values: lightData.isEmpty ? [ParticleLightData()] : lightData)
                .parameter("particleLights", buffer: particleLightBuffer)
                .parameter("sceneDepth", texture: sceneDepth ?? placeholderTexture)
                .renderPipelineDescriptorTransformer { descriptor in
                    if let attachment = descriptor.colorAttachments[0] {
                        draw.blendMode.configure(attachment)
                    }
                }
            } else if let mesh = draw.mesh {
                try RenderPipeline(vertexShader: meshVertexShader, fragmentShader: fragmentShader) {
                    Draw { encoder in
                        encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill)
                        for segment in draw.segments where segment.count > 0 {
                            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount, instanceCount: segment.count, baseInstance: segment.start)
                        }
                    }
                }
                .parameter("meshVertices", buffer: mesh.buffer)
                .parameter("colorImage", texture: draw.colorImage ?? placeholderTexture)
                .parameter("extraColorCurves", values: draw.extraColorCurves)
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: draw.uniforms)
                .parameter("colorCurve", values: draw.colorCurve)
                .parameter("sizeCurve", values: draw.sizeCurve)
                .parameter("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
                .parameter("sprite", texture: placeholderTexture)
                .parameter("spriteSampler", samplerState: sampler)
                .parameter("lights", values: lightData.isEmpty ? [ParticleLightData()] : lightData)
                .parameter("particleLights", buffer: particleLightBuffer)
                .parameter("sceneDepth", texture: sceneDepth ?? placeholderTexture)
                // Shapes hide each other; only opaque ones write depth, so blended ones still show what is behind.
                .depthCompare(function: depthCompare, writes: draw.blendMode == .opaque)
                .renderPipelineDescriptorTransformer { descriptor in
                    if let attachment = descriptor.colorAttachments[0] {
                        draw.blendMode.configure(attachment)
                    }
                }
            } else if draw.uniforms.trailPointCount > 1 {
                try RenderPipeline(vertexShader: trailVertexShader, fragmentShader: fragmentShader) {
                    Draw { encoder in
                        encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill)
                        for segment in draw.segments where segment.count > 0 {
                            encoder.drawPrimitives(
                                primitiveType: .triangleStrip,
                                vertexStart: 0,
                                vertexCount: Int(draw.uniforms.trailPointCount) * 2,
                                instanceCount: segment.count,
                                baseInstance: segment.start
                            )
                        }
                    }
                }
                .parameter("trails", buffer: trailBuffer)
                .parameter("colorImage", texture: draw.colorImage ?? placeholderTexture)
                .parameter("particles", buffer: buffer)
                .parameter("uniforms", value: draw.uniforms)
                .parameter("colorCurve", values: draw.colorCurve)
                .parameter("sizeCurve", values: draw.sizeCurve)
                .parameter("extraColorCurves", values: draw.extraColorCurves)
                .parameter("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
                .parameter("sprite", texture: draw.texture ?? placeholderTexture)
                .parameter("spriteSampler", samplerState: sampler)
                .parameter("lights", values: lightData.isEmpty ? [ParticleLightData()] : lightData)
                .parameter("particleLights", buffer: particleLightBuffer)
                .parameter("sceneDepth", texture: sceneDepth ?? placeholderTexture)
                .renderPipelineDescriptorTransformer { descriptor in
                    if let attachment = descriptor.colorAttachments[0] {
                        draw.blendMode.configure(attachment)
                    }
                }
            } else {
            try RenderPipeline(vertexShader: vertexShader, fragmentShader: fragmentShader) {
                Draw { encoder in
                    encoder.setTriangleFillMode(draw.wireframe ? .lines : .fill)
                    for segment in draw.segments where segment.count > 0 {
                        encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segment.count, baseInstance: segment.start)
                    }
                }
            }
            .parameter("particles", buffer: buffer)
            .parameter("colorImage", texture: draw.colorImage ?? placeholderTexture)
            .parameter("uniforms", value: draw.uniforms)
            .parameter("colorCurve", values: draw.colorCurve)
            .parameter("sizeCurve", values: draw.sizeCurve)
            .parameter("extraColorCurves", values: draw.extraColorCurves)
            .parameter("sortRecords", buffer: draw.sortRecords ?? placeholderSortRecords)
            .parameter("sprite", texture: draw.texture ?? placeholderTexture)
            .parameter("spriteSampler", samplerState: sampler)
            // Never bind an empty array; lightCount keeps the padding unused.
            .parameter("lights", values: lightData.isEmpty ? [ParticleLightData()] : lightData)
            .parameter("particleLights", buffer: particleLightBuffer)
            .parameter("sceneDepth", texture: sceneDepth ?? placeholderTexture)
            .renderPipelineDescriptorTransformer { descriptor in
                if let attachment = descriptor.colorAttachments[0] {
                    draw.blendMode.configure(attachment)
                }
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
    /// By speed, alternate over life (with opacity, like `colorCurve`), and by position; white where unused.
    var extraColorCurves: [SIMD4<Float>]
    /// `ParticleEmitter.colorImage`'s texture.
    var colorImage: MTLTexture?
    /// `ParticleEmitter.ribbon`: one strip through the live window, drawn instead of anything else.
    var isRibbon = false
    /// Draws triangles as lines (`ParticleDebugView.wireframe`).
    var wireframe = false
    /// `ParticleEmitter.particleMesh`'s vertices, drawn instead of a quad.
    var mesh: (buffer: MTLBuffer, vertexCount: Int)?

    struct Lighting {
        var ambient: SIMD3<Float>
        var lightCount: Int
        var particleLightCount: Int
    }

    init(emitter: ParticleSystemRuntime.Emitter, projection: simd_float4x4, view: simd_float4x4, lighting: Lighting, hasSceneDepth: Bool) {
        let viewProjection = projection * view
        let cameraToWorld = view.inverse
        let settings = emitter.settings
        let sequence = emitter.texture == nil ? ImageSequence() : settings.imageSequence ?? ImageSequence()
        let opacity = settings.opacityOverLife.baked()
        colorCurve = zip(settings.colorOverLife.baked(), opacity).map { color, opacity in
            SIMD4(color.x, color.y, color.z, color.w * opacity)
        }
        sizeCurve = settings.sizeOverLife.baked()
        let white = [SIMD4<Float>](repeating: .one, count: Int(PARTICLE_CURVE_SAMPLES))
        let alternate = settings.alternateColorOverLife.map { curve in
            zip(curve.baked(), opacity).map { color, opacity in SIMD4(color.x, color.y, color.z, color.w * opacity) }
        }
        extraColorCurves = (settings.colorBySpeed?.baked() ?? white) + (alternate ?? white) + (settings.colorByPosition?.baked() ?? white)
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
            particleLightCount: UInt32(lighting.particleLightCount),
            softness: max(settings.softness, 0),
            hasSceneDepth: hasSceneDepth ? 1 : 0,
            // Clip z = a * zView + b and clip w = c * zView, so depth d = (a * zView + b) / (c * zView).
            depthUnproject: [projection.columns.2.z, projection.columns.3.z, projection.columns.2.w],
            hasSpeedColor: settings.colorBySpeed == nil ? 0 : 1,
            hasAlternateColor: settings.alternateColorOverLife == nil ? 0 : 1,
            // At birth, the simulation applies it instead.
            hasPositionColor: settings.colorByPosition == nil || settings.colorByPositionAtBirth ? 0 : 1,
            speedColorRange: [settings.colorBySpeedRange.lowerBound, settings.colorBySpeedRange.upperBound],
            positionColorStart: settings.colorByPositionStart,
            positionColorEnd: settings.colorByPositionEnd,
            // Set by render once the trail buffer is known.
            trailPointCount: 0,
            trailStride: 0,
            trailTapers: 0,
            trailFades: 0,
            // Set by render for debug views.
            debugMode: .none,
            debugEmitterIndex: 0,
            debugSliceStart: 0,
            debugCapacity: 0,
            debugRange: .zero,
            // Set by render for ribbons.
            ribbonSliceStart: 0,
            ribbonCapacity: 0,
            ribbonWindowStart: 0,
            ribbonWindowCount: 0,
            ribbonTapers: 0,
            sizeScale: settings.lodScalesSize && emitter.lodRateScale > 0 ? 1 / emitter.lodRateScale.squareRoot() : 1,
            minimumScreenSize: max(settings.minimumScreenSize, 0),
            projectionScaleY: projection.columns.1.y,
            // Set by render when the emitter has a color image.
            hasColorImage: 0,
            colorImageOrigin: .zero,
            colorImageU: .zero,
            colorImageV: .zero
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
