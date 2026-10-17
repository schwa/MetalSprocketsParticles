import MetalSprocketsParticles
import simd

// Writable computed properties for editing sub-emitters and triggers with key-path bindings. Setters on properties that
// do not apply to the current case are ignored.

enum OccasionKind: String, CaseIterable, Identifiable {
    case onBirth = "On Birth"
    case onDeath = "On Death"
    case onCollision = "On Collision"
    case whileAlive = "While Alive"

    var id: Self { self }
}

extension SubEmitter {
    var occasionKind: OccasionKind {
        get {
            switch occasion {
            case .onBirth: .onBirth
            case .onDeath: .onDeath
            case .onCollision: .onCollision
            case .whileAlive: .whileAlive
            }
        }
        set {
            occasion = switch newValue {
            case .onBirth: .onBirth
            case .onDeath: .onDeath
            case .onCollision: .onCollision
            case .whileAlive: .whileAlive(interval: trailInterval)
            }
        }
    }

    /// The `whileAlive` interval, or 0.05 for other occasions. Setting it switches to `whileAlive`.
    var trailInterval: Float {
        get {
            if case let .whileAlive(interval) = occasion {
                return interval
            }
            return 0.05
        }
        set { occasion = .whileAlive(interval: newValue) }
    }

    /// A small burst of short-lived sparks, a sensible starting point for a new sub-emitter.
    static var sparks: SubEmitter {
        var settings = ParticleEmitter()
        settings.shape = .point
        settings.velocity = [0, 1.5, 0]
        settings.velocitySpread = 1.5
        settings.lifetime = 0.4...0.8
        settings.blendMode = .additive
        settings.sizeOverLife = .linear(from: 0.015, to: 0.003)
        settings.colorOverLife = .linear(from: [1, 0.9, 0.6, 1], to: [1, 0.3, 0.05, 0])
        return SubEmitter(occasion: .onDeath, countPerEvent: 20, settings: settings)
    }
}

enum TriggerConditionKind: String, CaseIterable, Identifiable {
    case event = "Event"
    case after = "After"
    case every = "Every"
    case objectEnters = "Object Enters"
    case particlesEnter = "Particles Enter"
    case colliderHit = "Collider Hit"

    var id: Self { self }
}

enum TriggerActionKind: String, CaseIterable, Identifiable {
    case burst = "Burst"
    case start = "Start"
    case stop = "Stop"
    case restart = "Restart"

    var id: Self { self }
}

extension EmissionTrigger {
    var conditionKind: TriggerConditionKind {
        get {
            switch condition {
            case .event: .event
            case .after: .after
            case .every: .every
            case .objectEnters: .objectEnters
            case .particlesEnter: .particlesEnter
            case .colliderHit: .colliderHit
            }
        }
        set {
            guard newValue != conditionKind else {
                return
            }
            let volume = TriggerVolume.sphere(center: [0, 1, 0], radius: 0.5)
            condition = switch newValue {
            case .event: .event("boom")
            case .after: .after(seconds: 1)
            case .every: .every(seconds: 1)
            case .objectEnters: .objectEnters(name: "object", volume: volume)
            case .particlesEnter: .particlesEnter(volume: volume, count: 1)
            case .colliderHit: .colliderHit(index: 0, count: 1)
            }
        }
    }

    var eventName: String {
        get {
            switch condition {
            case let .event(name), let .objectEnters(name, _): name
            default: ""
            }
        }
        set {
            switch condition {
            case .event: condition = .event(newValue)
            case let .objectEnters(_, volume): condition = .objectEnters(name: newValue, volume: volume)
            default: break
            }
        }
    }

    var seconds: Float {
        get {
            switch condition {
            case let .after(seconds), let .every(seconds): seconds
            default: 0
            }
        }
        set {
            switch condition {
            case .after: condition = .after(seconds: newValue)
            case .every: condition = .every(seconds: newValue)
            default: break
            }
        }
    }

    /// The volume of `objectEnters` and `particlesEnter` conditions.
    var volume: TriggerVolume {
        get {
            switch condition {
            case let .objectEnters(_, volume), let .particlesEnter(volume, _): volume
            default: .sphere(center: .zero, radius: 0)
            }
        }
        set {
            switch condition {
            case let .objectEnters(name, _): condition = .objectEnters(name: name, volume: newValue)
            case let .particlesEnter(_, count): condition = .particlesEnter(volume: newValue, count: count)
            default: break
            }
        }
    }

    var threshold: Int {
        get {
            switch condition {
            case let .particlesEnter(_, count), let .colliderHit(_, count): count
            default: 1
            }
        }
        set {
            switch condition {
            case let .particlesEnter(volume, _): condition = .particlesEnter(volume: volume, count: newValue)
            case let .colliderHit(index, _): condition = .colliderHit(index: index, count: newValue)
            default: break
            }
        }
    }

    var colliderIndex: Int {
        get {
            if case let .colliderHit(index, _) = condition {
                return index
            }
            return 0
        }
        set {
            if case let .colliderHit(_, count) = condition {
                condition = .colliderHit(index: newValue, count: count)
            }
        }
    }

    var actionKind: TriggerActionKind {
        get {
            switch action {
            case .burst: .burst
            case .start: .start
            case .stop: .stop
            case .restart: .restart
            }
        }
        set {
            action = switch newValue {
            case .burst: .burst(burstCount)
            case .start: .start
            case .stop: .stop
            case .restart: .restart
            }
        }
    }

    /// The burst size, or 100 for other actions. Setting it switches to `burst`.
    var burstCount: Int {
        get {
            if case let .burst(count) = action {
                return count
            }
            return 100
        }
        set { action = .burst(newValue) }
    }
}

extension TriggerVolume {
    var center: SIMD3<Float> {
        get {
            switch self {
            case let .sphere(center, _), let .box(center, _): center
            }
        }
        set {
            switch self {
            case let .sphere(_, radius): self = .sphere(center: newValue, radius: radius)
            case let .box(_, halfExtents): self = .box(center: newValue, halfExtents: halfExtents)
            }
        }
    }

    /// Sphere radius, or the box's largest half extent. Setting it on a box makes it a cube of that half extent.
    var radius: Float {
        get {
            switch self {
            case let .sphere(_, radius): radius
            case let .box(_, halfExtents): halfExtents.max()
            }
        }
        set {
            switch self {
            case let .sphere(center, _): self = .sphere(center: center, radius: newValue)
            case let .box(center, _): self = .box(center: center, halfExtents: SIMD3(repeating: newValue))
            }
        }
    }

    var isBox: Bool {
        get {
            if case .box = self {
                return true
            }
            return false
        }
        set {
            self = newValue ? .box(center: center, halfExtents: SIMD3(repeating: radius)) : .sphere(center: center, radius: radius)
        }
    }
}
