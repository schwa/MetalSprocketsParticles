import MetalSprocketsParticles
import simd

// Writable computed properties for editing sub-emitters and triggers with key-path bindings. Setters on properties that
// do not apply to the current case are ignored. Switching between cases uses the library's writable `kind` properties.

extension SubEmitter {
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

    /// The `atAge` seconds, or 1 for other occasions. Setting it switches to `atAge`.
    var transitionAge: Float {
        get {
            if case let .atAge(seconds) = occasion {
                return seconds
            }
            return 1
        }
        set { occasion = .atAge(seconds: newValue) }
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

extension EmissionTrigger {
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
}
