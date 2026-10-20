import simd

// An emitter as ordered module stacks per stage (#178). See Documentation/Modules.md.
//
// Built-in modules lower to ParticleEmitter, which the simulation kernel reads as uniforms, so they cost nothing per
// module. Stitched modules (user [[stitchable]] functions) run in stack order inside the stage's function slot.

/// A module in a stack, with a switch to turn it off without removing it.
public struct ModuleSlot<Module: Sendable & Equatable & Codable>: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var module: Module

    public init(_ module: Module, isEnabled: Bool = true) {
        self.module = module
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, module
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        module = try container.decode(Module.self, forKey: .module)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(module, forKey: .module)
        if !isEnabled {
            try container.encode(false, forKey: .isEnabled)
        }
    }
}

/// A user module: a `[[stitchable]]` Metal function stitched with the stage's other user modules into one function.
///
/// ```metal
/// [[stitchable]] constant float4 *name(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters)
/// ```
///
/// Read your entries from `parameters` and return `parameters + parameterCount`, so the next module reads its own.
/// `source` compiles after `ParticleFunction.prelude`.
public struct StitchedModule: Sendable, Hashable, Codable {
    public var source: String
    public var name: String
    public var parameters: [SIMD4<Float>]
    /// Entries this module reads and skips; `parameters` is padded with zeros to this count.
    public var parameterCount: Int

    public init(source: String, name: String, parameters: [SIMD4<Float>] = [], parameterCount: Int? = nil) {
        self.source = source
        self.name = name
        self.parameters = parameters
        self.parameterCount = parameterCount ?? parameters.count
    }
}

public enum SpawnModule: Sendable, Equatable, Codable {
    case shape(position: SIMD3<Float>, shape: EmitterShape, birthLocation: ParticleBirthLocation, birthDirection: ParticleBirthDirection, sweepAngle: Float)
    case rate(birthRate: Float, variation: Float, emissionDuration: Float?, idleDuration: Float, loops: Bool, warmupDuration: Float, overTime: ParticleCurve<Float>)
    case lifetime(range: ClosedRange<Float>)
    case velocity(velocity: SIMD3<Float>, spread: Float, speedVariation: Float, inherit: Float)
    case rotation(angle: Float, angleVariation: Float, angularSpeed: Float, angularSpeedVariation: Float)
    case variation(size: Float, color: SIMD4<Float>)
    case colorImage(image: ParticleColorImage)
    case function(function: ParticleFunction)
    case stitched(module: StitchedModule)
}

public enum UpdateModule: Sendable, Equatable, Codable {
    case gravity(acceleration: SIMD3<Float>)
    case drag(amount: Float)
    case flocking(flocking: ParticleFlocking)
    case collision(restitution: Float, restitutionVariation: Float, friction: Float, frictionVariation: Float, diesOnCollision: Bool, radius: Float, collidesWithSceneDepth: Bool)
    case planeConstraint
    case colorOverLife(color: ParticleCurve<SIMD4<Float>>, opacity: ParticleCurve<Float>, alternate: ParticleCurve<SIMD4<Float>>?)
    case sizeOverLife(curve: ParticleCurve<Float>)
    case colorBySpeed(curve: ParticleCurve<SIMD4<Float>>?, range: ClosedRange<Float>)
    case colorByPosition(curve: ParticleCurve<SIMD4<Float>>?, start: SIMD3<Float>, end: SIMD3<Float>, atBirth: Bool)
    case imageSequence(sequence: ImageSequence)
    case events(reportsCollisions: Bool, reportsDeaths: Bool)
    case subEmitters(emitters: [SubEmitter])
    case triggers(triggers: [EmissionTrigger])
    case function(function: ParticleFunction)
    case collisionFunction(function: ParticleFunction)
    case deathFunction(function: ParticleFunction)
    case stitched(module: StitchedModule)
}

public enum RenderModule: Sendable, Equatable, Codable {
    case sprite(blendMode: ParticleBlendMode, sortMode: ParticleSortMode, orientation: ParticleOrientation, softness: Float, isLit: Bool, minimumScreenSize: Float)
    case foil(foil: ParticleFoil)
    case mesh(mesh: ParticleMesh)
    case trail(trail: ParticleTrail)
    case ribbon(ribbon: ParticleRibbon)
    case light(light: ParticleLightEmission)
    case levelOfDetail(near: Float, far: Float, farRateScale: Float, scalesSize: Bool, cullingRadius: Float, simulatesWhenCulled: Bool)
}

/// One emitter's behavior: a module stack per stage, applied in order, plus settings that belong to no stage.
public struct EmitterModules: Sendable, Equatable, Codable {
    public var spawn: [ModuleSlot<SpawnModule>] = []
    public var update: [ModuleSlot<UpdateModule>] = []
    public var render: [ModuleSlot<RenderModule>] = []
    /// Which colliders and force fields affect the particles.
    public var categoryMask: UInt32 = .max
    /// `ParticleState.custom` through `custom3` kept between steps, 1 to 4.
    public var customAttributeCount = 1

    public init(spawn: [SpawnModule] = [], update: [UpdateModule] = [], render: [RenderModule] = []) {
        self.spawn = spawn.map { ModuleSlot($0) }
        self.update = update.map { ModuleSlot($0) }
        self.render = render.map { ModuleSlot($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case spawn, update, render, categoryMask, customAttributeCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.update(&spawn, .spawn)
        try container.update(&update, .update)
        try container.update(&render, .render)
        try container.update(&categoryMask, .categoryMask)
        try container.update(&customAttributeCount, .customAttributeCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spawn, forKey: .spawn)
        try container.encode(update, forKey: .update)
        try container.encode(render, forKey: .render)
        if categoryMask != .max {
            try container.encode(categoryMask, forKey: .categoryMask)
        }
        if customAttributeCount != 1 {
            try container.encode(customAttributeCount, forKey: .customAttributeCount)
        }
    }
}

// MARK: - Lowering

public extension ParticleEmitter {
    /// What an emitter does with no modules: nothing moves, colors, or grows; it just spawns with the shape's defaults.
    /// Modules are applied on top of this.
    static var neutral: Self {
        var emitter = Self()
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.drag = 0
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.sizeOverLife = .constant(0.04)
        return emitter
    }
}

public extension EmitterModules {
    /// The flat settings the simulation runs. Disabled modules are skipped.
    func lowered() -> ParticleEmitter {
        var emitter = ParticleEmitter.neutral
        emitter.categoryMask = categoryMask
        emitter.customAttributeCount = customAttributeCount
        for slot in spawn where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        for slot in update where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        for slot in render where slot.isEnabled {
            slot.module.apply(to: &emitter)
        }
        return emitter
    }

    /// Modules that lower to `emitter`. Optional behaviors get a module only when they differ from `ParticleEmitter.neutral`.
    init(_ emitter: ParticleEmitter) {
        let neutral = ParticleEmitter.neutral
        var spawn: [SpawnModule] = [
            .shape(position: emitter.position, shape: emitter.shape, birthLocation: emitter.birthLocation, birthDirection: emitter.birthDirection, sweepAngle: emitter.sweepAngle),
            .rate(birthRate: emitter.birthRate, variation: emitter.birthRateVariation, emissionDuration: emitter.emissionDuration, idleDuration: emitter.idleDuration, loops: emitter.loops, warmupDuration: emitter.warmupDuration, overTime: emitter.emissionOverTime),
            .lifetime(range: emitter.lifetime),
        ]
        if emitter.velocity != neutral.velocity || emitter.velocitySpread != neutral.velocitySpread || emitter.speedVariation != neutral.speedVariation || emitter.inheritVelocity != neutral.inheritVelocity {
            spawn.append(.velocity(velocity: emitter.velocity, spread: emitter.velocitySpread, speedVariation: emitter.speedVariation, inherit: emitter.inheritVelocity))
        }
        if emitter.angle != 0 || emitter.angleVariation != 0 || emitter.angularSpeed != 0 || emitter.angularSpeedVariation != 0 {
            spawn.append(.rotation(angle: emitter.angle, angleVariation: emitter.angleVariation, angularSpeed: emitter.angularSpeed, angularSpeedVariation: emitter.angularSpeedVariation))
        }
        if emitter.sizeVariation != 0 || emitter.colorVariation != .zero {
            spawn.append(.variation(size: emitter.sizeVariation, color: emitter.colorVariation))
        }
        if let colorImage = emitter.colorImage {
            spawn.append(.colorImage(image: colorImage))
        }
        if let function = emitter.spawnFunction {
            spawn.append(.function(function: function))
        }
        spawn += emitter.spawnModules.map { .stitched(module: $0) }

        var update: [UpdateModule] = []
        if emitter.gravity != .zero {
            update.append(.gravity(acceleration: emitter.gravity))
        }
        if emitter.drag != 0 {
            update.append(.drag(amount: emitter.drag))
        }
        if let flocking = emitter.flocking {
            update.append(.flocking(flocking: flocking))
        }
        update.append(.collision(restitution: emitter.restitution, restitutionVariation: emitter.restitutionVariation, friction: emitter.friction, frictionVariation: emitter.frictionVariation, diesOnCollision: emitter.diesOnCollision, radius: emitter.collisionRadius, collidesWithSceneDepth: emitter.collidesWithSceneDepth))
        if emitter.constrainsToPlane {
            update.append(.planeConstraint)
        }
        update.append(.colorOverLife(color: emitter.colorOverLife, opacity: emitter.opacityOverLife, alternate: emitter.alternateColorOverLife))
        update.append(.sizeOverLife(curve: emitter.sizeOverLife))
        if emitter.colorBySpeed != nil || emitter.colorBySpeedRange != neutral.colorBySpeedRange {
            update.append(.colorBySpeed(curve: emitter.colorBySpeed, range: emitter.colorBySpeedRange))
        }
        if emitter.colorByPosition != nil || emitter.colorByPositionStart != neutral.colorByPositionStart || emitter.colorByPositionEnd != neutral.colorByPositionEnd || emitter.colorByPositionAtBirth {
            update.append(.colorByPosition(curve: emitter.colorByPosition, start: emitter.colorByPositionStart, end: emitter.colorByPositionEnd, atBirth: emitter.colorByPositionAtBirth))
        }
        if let sequence = emitter.imageSequence {
            update.append(.imageSequence(sequence: sequence))
        }
        if emitter.reportsCollisions || emitter.reportsDeaths {
            update.append(.events(reportsCollisions: emitter.reportsCollisions, reportsDeaths: emitter.reportsDeaths))
        }
        if !emitter.subEmitters.isEmpty {
            update.append(.subEmitters(emitters: emitter.subEmitters))
        }
        if !emitter.triggers.isEmpty {
            update.append(.triggers(triggers: emitter.triggers))
        }
        if let function = emitter.updateFunction {
            update.append(.function(function: function))
        }
        update += emitter.updateModules.map { .stitched(module: $0) }
        if let function = emitter.collisionFunction {
            update.append(.collisionFunction(function: function))
        }
        if let function = emitter.deathFunction {
            update.append(.deathFunction(function: function))
        }

        var render: [RenderModule] = [
            .sprite(blendMode: emitter.blendMode, sortMode: emitter.sortMode, orientation: emitter.orientation, softness: emitter.softness, isLit: emitter.isLit, minimumScreenSize: emitter.minimumScreenSize),
        ]
        if let foil = emitter.foil {
            render.append(.foil(foil: foil))
        }
        if let mesh = emitter.particleMesh {
            render.append(.mesh(mesh: mesh))
        }
        if let trail = emitter.trail {
            render.append(.trail(trail: trail))
        }
        if let ribbon = emitter.ribbon {
            render.append(.ribbon(ribbon: ribbon))
        }
        if let light = emitter.light {
            render.append(.light(light: light))
        }
        if emitter.lodNearDistance != neutral.lodNearDistance || emitter.lodFarDistance != neutral.lodFarDistance || emitter.lodFarRateScale != neutral.lodFarRateScale || emitter.lodScalesSize
            || emitter.cullingRadius != neutral.cullingRadius || emitter.simulatesWhenCulled != neutral.simulatesWhenCulled {
            render.append(.levelOfDetail(near: emitter.lodNearDistance, far: emitter.lodFarDistance, farRateScale: emitter.lodFarRateScale, scalesSize: emitter.lodScalesSize, cullingRadius: emitter.cullingRadius, simulatesWhenCulled: emitter.simulatesWhenCulled))
        }
        self.init(spawn: spawn, update: update, render: render)
        categoryMask = emitter.categoryMask
        customAttributeCount = emitter.customAttributeCount
    }
}

extension SpawnModule {
    func apply(to emitter: inout ParticleEmitter) {
        switch self {
        case let .shape(position, shape, birthLocation, birthDirection, sweepAngle):
            emitter.position = position
            emitter.shape = shape
            emitter.birthLocation = birthLocation
            emitter.birthDirection = birthDirection
            emitter.sweepAngle = sweepAngle
        case let .rate(birthRate, variation, emissionDuration, idleDuration, loops, warmupDuration, overTime):
            emitter.birthRate = birthRate
            emitter.birthRateVariation = variation
            emitter.emissionDuration = emissionDuration
            emitter.idleDuration = idleDuration
            emitter.loops = loops
            emitter.warmupDuration = warmupDuration
            emitter.emissionOverTime = overTime
        case let .lifetime(range):
            emitter.lifetime = range
        case let .velocity(velocity, spread, speedVariation, inherit):
            emitter.velocity = velocity
            emitter.velocitySpread = spread
            emitter.speedVariation = speedVariation
            emitter.inheritVelocity = inherit
        case let .rotation(angle, angleVariation, angularSpeed, angularSpeedVariation):
            emitter.angle = angle
            emitter.angleVariation = angleVariation
            emitter.angularSpeed = angularSpeed
            emitter.angularSpeedVariation = angularSpeedVariation
        case let .variation(size, color):
            emitter.sizeVariation = size
            emitter.colorVariation = color
        case let .colorImage(image):
            emitter.colorImage = image
        case let .function(function):
            emitter.spawnFunction = function
        case let .stitched(module):
            emitter.spawnModules.append(module)
        }
    }
}

extension UpdateModule {
    func apply(to emitter: inout ParticleEmitter) {
        switch self {
        case let .gravity(gravity):
            emitter.gravity = gravity
        case let .drag(drag):
            emitter.drag = drag
        case let .flocking(flocking):
            emitter.flocking = flocking
        case let .collision(restitution, restitutionVariation, friction, frictionVariation, diesOnCollision, radius, collidesWithSceneDepth):
            emitter.restitution = restitution
            emitter.restitutionVariation = restitutionVariation
            emitter.friction = friction
            emitter.frictionVariation = frictionVariation
            emitter.diesOnCollision = diesOnCollision
            emitter.collisionRadius = radius
            emitter.collidesWithSceneDepth = collidesWithSceneDepth
        case .planeConstraint:
            emitter.constrainsToPlane = true
        case let .colorOverLife(color, opacity, alternate):
            emitter.colorOverLife = color
            emitter.opacityOverLife = opacity
            emitter.alternateColorOverLife = alternate
        case let .sizeOverLife(curve):
            emitter.sizeOverLife = curve
        case let .colorBySpeed(curve, range):
            emitter.colorBySpeed = curve
            emitter.colorBySpeedRange = range
        case let .colorByPosition(curve, start, end, atBirth):
            emitter.colorByPosition = curve
            emitter.colorByPositionStart = start
            emitter.colorByPositionEnd = end
            emitter.colorByPositionAtBirth = atBirth
        case let .imageSequence(sequence):
            emitter.imageSequence = sequence
        case let .events(reportsCollisions, reportsDeaths):
            emitter.reportsCollisions = reportsCollisions
            emitter.reportsDeaths = reportsDeaths
        case let .subEmitters(subEmitters):
            emitter.subEmitters += subEmitters
        case let .triggers(triggers):
            emitter.triggers += triggers
        case let .function(function):
            emitter.updateFunction = function
        case let .collisionFunction(function):
            emitter.collisionFunction = function
        case let .deathFunction(function):
            emitter.deathFunction = function
        case let .stitched(module):
            emitter.updateModules.append(module)
        }
    }
}

extension RenderModule {
    func apply(to emitter: inout ParticleEmitter) {
        switch self {
        case let .sprite(blendMode, sortMode, orientation, softness, isLit, minimumScreenSize):
            emitter.blendMode = blendMode
            emitter.sortMode = sortMode
            emitter.orientation = orientation
            emitter.softness = softness
            emitter.isLit = isLit
            emitter.minimumScreenSize = minimumScreenSize
        case let .foil(foil):
            emitter.foil = foil
        case let .mesh(mesh):
            emitter.particleMesh = mesh
        case let .trail(trail):
            emitter.trail = trail
        case let .ribbon(ribbon):
            emitter.ribbon = ribbon
        case let .light(light):
            emitter.light = light
        case let .levelOfDetail(near, far, farRateScale, scalesSize, cullingRadius, simulatesWhenCulled):
            emitter.lodNearDistance = near
            emitter.lodFarDistance = far
            emitter.lodFarRateScale = farRateScale
            emitter.lodScalesSize = scalesSize
            emitter.cullingRadius = cullingRadius
            emitter.simulatesWhenCulled = simulatesWhenCulled
        }
    }
}
