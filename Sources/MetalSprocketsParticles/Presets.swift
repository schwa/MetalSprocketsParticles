import simd

private func emitter(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
    var emitter = ParticleEmitter()
    configure(&emitter)
    return emitter
}

private let ground = Collider.plane(normal: [0, 1, 0], distance: 0)

public extension ParticlePreset {
    static let all: [ParticlePreset] = [
        .fountain, .campfire, .fireworks, .sparks, .smoke, .snow, .rain, .magicTrail, .comet, .galaxy, .waterfall, .confetti,
        .portal, .hearts, .moonPhases,
    ]

    /// Emoji hearts drift up and wobble, with a few sparkles. Emoji sprites keep their own colors (white tint).
    static let hearts = ParticlePreset(
        "Hearts",
        layers: [
            Layer("Hearts", settings: emitter {
                $0.sortMode = .backToFront
                $0.shape = .disc(radius: 1.2)
                $0.velocity = [0, 0.9, 0]
                $0.velocitySpread = 0.3
                $0.gravity = .zero
                $0.drag = 0.3
                $0.lifetime = 4...5
                $0.birthRate = 25
                $0.warmupDuration = 5
                $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.1, 0.18), .init(1, 0.12)])
                $0.sizeVariation = 0.4
                $0.opacityOverLife = ParticleCurve([.init(0, 1), .init(0.75, 1), .init(1, 0)])
                $0.colorOverLife = .constant([1, 1, 1, 1])
                $0.angleVariation = 0.35
                $0.angularSpeedVariation = 0.8
            }, sprite: .heart, capacity: 500),
            Layer("Sparkles", settings: emitter {
                $0.shape = .disc(radius: 1.2)
                $0.velocity = [0, 0.7, 0]
                $0.velocitySpread = 0.5
                $0.gravity = .zero
                $0.lifetime = 2...3
                $0.birthRate = 30
                $0.warmupDuration = 3
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.06, to: 0)
                $0.colorOverLife = .linear(from: [1, 0.6, 0.8, 1], to: [1, 0.3, 0.5, 0])
                $0.angularSpeedVariation = 3
            }, sprite: .spark, capacity: 500),
        ],
        forceFields: [.turbulence(strength: 0.8, scale: 0.8, speed: 0.4)]
    )

    /// Emoji moons orbit slowly, each playing the moon-phase flipbook from its own starting phase.
    static let moonPhases = ParticlePreset(
        "Moon Phases",
        layers: [
            Layer("Moons", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 1.5, 0]
                $0.shape = .torus(radius: 1.8, tubeRadius: 0.4)
                $0.birthDirection = .tangent
                $0.velocity = [0, 0, 0.6]
                $0.velocitySpread = 0.05
                $0.gravity = .zero
                $0.lifetime = 6...8
                $0.birthRate = 12
                $0.warmupDuration = 8
                $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.15, 0.22), .init(0.85, 0.22), .init(1, 0)])
                $0.sizeVariation = 0.3
                $0.colorOverLife = .constant([1, 1, 1, 1])
                var phases = ParticleSprite.moonPhases.defaultImageSequence!
                phases.frameRate = 3
                phases.initialFrameVariation = 8
                $0.imageSequence = phases
            }, sprite: .moonPhases, capacity: 200),
            Layer("Stardust", settings: emitter {
                $0.position = [0, 1.5, 0]
                $0.shape = .sphere(radius: 4)
                $0.birthLocation = .surface
                $0.velocity = .zero
                $0.velocitySpread = 0.02
                $0.gravity = .zero
                $0.lifetime = 3...6
                $0.birthRate = 150
                $0.warmupDuration = 6
                $0.blendMode = .additive
                $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.5, 0.02), .init(1, 0)])
                $0.colorOverLife = .constant([0.7, 0.8, 1, 1])
            }, capacity: 1_000),
        ],
        forceFields: [.vortex(center: [0, 1.5, 0], axis: [0, 1, 0], strength: 0.3, radius: 4)]
    )

    /// A sorcerer's portal: a spinning ring of fire that throws sparks off its rim like a Catherine wheel.
    static let portal: ParticlePreset = {
        let center: SIMD3<Float> = [0, 1.6, 0]
        // The rim shapes lie in the XZ plane; a pitch of pi/2 stands them up facing the camera. A negative pitch flips
        // the ring's axis, so its tangent runs the other way.
        let clockwise = EmitterMotion(offset: center, pitch: .pi / 2, spin: 3)
        let counterclockwise = EmitterMotion(offset: center, pitch: -.pi / 2, spin: -2)
        return ParticlePreset(
            "Portal",
            layers: [
                Layer("Ring", settings: emitter {
                    $0.shape = .disc(radius: 1.1)
                    $0.birthLocation = .surface
                    $0.birthDirection = .tangent
                    $0.velocity = [0, 0.3, 0]
                    $0.velocitySpread = 0.05
                    $0.gravity = .zero
                    $0.lifetime = 0.15...0.3
                    $0.birthRate = 12_000
                    $0.blendMode = .additive
                    $0.sizeOverLife = .linear(from: 0.05, to: 0.015)
                    $0.colorOverLife = .linear(from: [1, 0.55, 0.15, 0.2], to: [1, 0.25, 0.03, 0])
                }, motion: clockwise, capacity: 6_000),
                Layer("Sparks", settings: emitter {
                    $0.shape = .disc(radius: 1.1)
                    $0.birthLocation = .surface
                    $0.birthDirection = .tangent
                    $0.velocity = [0, 4, 0]
                    $0.velocitySpread = 0.5
                    $0.speedVariation = 1.5
                    $0.gravity = [0, -4, 0]
                    $0.drag = 0.8
                    $0.lifetime = 0.4...1.1
                    $0.birthRate = 5_000
                    $0.restitution = 0.3
                    $0.blendMode = .additive
                    $0.orientation = .velocityAligned(stretch: 1.8)
                    $0.sizeOverLife = .linear(from: 0.009, to: 0.004)
                    $0.colorOverLife = ParticleCurve([
                        .init(0, [1, 0.85, 0.45, 1]),
                        .init(0.25, [1, 0.5, 0.1, 1]),
                        .init(1, [0.7, 0.12, 0.02, 0]),
                    ])
                }, motion: clockwise, capacity: 8_000),
                Layer("Inner Shimmer", settings: emitter {
                    $0.shape = .disc(radius: 0.95)
                    $0.birthLocation = .surface
                    $0.birthDirection = .tangent
                    $0.velocity = [0, 1.2, 0]
                    $0.velocitySpread = 0.1
                    $0.gravity = .zero
                    $0.drag = 1
                    $0.lifetime = 0.2...0.4
                    $0.birthRate = 2_500
                    $0.blendMode = .additive
                    $0.orientation = .velocityAligned(stretch: 0.5)
                    $0.sizeOverLife = .constant(0.008)
                    $0.colorOverLife = .linear(from: [1, 0.85, 0.5, 0.7], to: [1, 0.4, 0.1, 0])
                }, motion: counterclockwise, capacity: 2_000),
            ],
            colliders: [ground],
            cameraEye: [0, 1.6, 4.5],
            cameraTarget: center
        )
    }()

    static let fountain = ParticlePreset(
        "Fountain",
        layers: [Layer("Fountain", settings: .fountain, capacity: 100_000)],
        colliders: ParticleEmitter.fountainColliders(time: 0),
        animatesColliders: true
    )

    static let campfire = ParticlePreset(
        "Campfire",
        layers: [
            Layer("Smoke", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 1.1, 0]
                $0.shape = .disc(radius: 0.15)
                $0.velocity = [0, 0.8, 0]
                $0.velocitySpread = 0.15
                $0.gravity = [0, 0.1, 0]
                $0.drag = 0.2
                $0.lifetime = 3...4.5
                $0.birthRate = 90
                $0.warmupDuration = 4
                $0.sizeOverLife = .linear(from: 0.12, to: 0.5)
                $0.colorOverLife = ParticleCurve([.init(0, [0.2, 0.19, 0.18, 0]), .init(0.15, [0.22, 0.21, 0.2, 0.18]), .init(1, [0.4, 0.4, 0.42, 0])])
                $0.angleVariation = .pi
                $0.angularSpeedVariation = 0.6
            }, sprite: .smoke, capacity: 2_000),
            Layer("Flames", settings: emitter {
                $0.position = [0, 0.15, 0]
                $0.shape = .disc(radius: 0.3)
                $0.velocity = [0, 1.4, 0]
                $0.velocitySpread = 0.2
                $0.gravity = [0, 2, 0]
                $0.drag = 0.8
                $0.lifetime = 0.6...1.2
                $0.birthRate = 2_000
                $0.blendMode = .additive
                $0.sizeOverLife = ParticleCurve([.init(0, 0.08), .init(0.35, 0.16), .init(1, 0.02)])
                $0.colorOverLife = ParticleCurve([
                    .init(0, [1, 0.85, 0.45, 0.35]),
                    .init(0.3, [1, 0.45, 0.08, 0.3]),
                    .init(0.7, [0.6, 0.12, 0.03, 0.15]),
                    .init(1, [0.2, 0.03, 0.01, 0]),
                ])
                $0.angleVariation = .pi
                $0.angularSpeedVariation = 2
                $0.sizeVariation = 0.4
            }, sprite: .smoke, capacity: 5_000),
            Layer("Embers", settings: emitter {
                $0.position = [0, 0.3, 0]
                $0.shape = .disc(radius: 0.25)
                $0.velocity = [0, 2.8, 0]
                $0.velocitySpread = 1
                $0.gravity = [0, -1.5, 0]
                $0.drag = 0.4
                $0.lifetime = 1.2...2.8
                $0.birthRate = 60
                $0.blendMode = .additive
                $0.orientation = .velocityAligned(stretch: 0.5)
                $0.sizeOverLife = .constant(0.012)
                $0.colorOverLife = .linear(from: [1, 0.7, 0.3, 1], to: [1, 0.2, 0.05, 0])
                $0.restitution = 0.2
            }, capacity: 1_000),
        ],
        colliders: [
            ground,
            .capsule(start: [-0.5, 0.08, -0.2], end: [0.5, 0.08, 0.2], radius: 0.08),
            .capsule(start: [-0.4, 0.08, 0.35], end: [0.4, 0.08, -0.35], radius: 0.08),
        ],
        forceFields: [.turbulence(strength: 1.2, scale: 1.4, speed: 0.6)],
        cameraEye: [0, 1.8, 5.5],
        cameraTarget: [0, 1.3, 0]
    )

    static let fireworks: ParticlePreset = {
        // Rockets climb from the ground, leave a sparkle trail, and burst into a shell of stars when they burn out.
        func rockets(_ name: String, at x: Float, hue: SIMD4<Float>, rate: Float) -> Layer {
            let trail = emitter {
                $0.shape = .point
                $0.velocity = .zero
                $0.velocitySpread = 0.15
                $0.gravity = [0, -1, 0]
                $0.lifetime = 0.3...0.6
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.018, to: 0.003)
                $0.colorOverLife = .linear(from: [1, 0.85, 0.55, 1], to: [1, 0.4, 0.1, 0])
            }
            // A hollow shell: every star leaves the burst point at about the same speed.
            let burst = emitter {
                $0.shape = .sphere(radius: 0.02)
                $0.birthLocation = .surface
                $0.birthDirection = .normal
                $0.velocity = [0, 3.2, 0]
                $0.velocitySpread = 0.25
                $0.gravity = [0, -1.5, 0]
                $0.drag = 1.1
                $0.lifetime = 1.4...2.2
                $0.blendMode = .additive
                $0.orientation = .velocityAligned(stretch: 0.5)
                $0.sizeOverLife = .linear(from: 0.026, to: 0.008)
                $0.colorOverLife = ParticleCurve([.init(0, [1, 1, 1, 1]), .init(0.12, hue), .init(1, hue * [1, 1, 1, 0])])
                $0.colorVariation = [0.04, 0, 0.2, 0]
            }
            return Layer(name, settings: emitter {
                $0.position = [x, 0, 0]
                $0.shape = .disc(radius: 0.6)
                $0.velocity = [0, 6.5, 0]
                $0.velocitySpread = 0.7
                $0.gravity = [0, -4, 0]
                $0.drag = 0
                $0.lifetime = 1.0...1.3
                $0.birthRate = rate
                $0.warmupDuration = 3
                $0.blendMode = .additive
                $0.sizeOverLife = .constant(0.02)
                $0.colorOverLife = .constant([1, 0.85, 0.6, 1])
                $0.subEmitters = [
                    SubEmitter(occasion: .whileAlive(interval: 0.02), countPerEvent: 25, velocityFactor: 0.2, settings: trail),
                    SubEmitter(occasion: .onDeath, countPerEvent: 500, velocityFactor: 0.3, settings: burst),
                ]
            }, capacity: 8)
        }
        return ParticlePreset(
            "Fireworks",
            layers: [
                rockets("Red", at: -1.6, hue: [1, 0.2, 0.15, 1], rate: 0.7),
                rockets("Gold", at: 0, hue: [1, 0.75, 0.25, 1], rate: 0.6),
                rockets("Blue", at: 1.6, hue: [0.3, 0.5, 1, 1], rate: 0.8),
            ],
            cameraEye: [0, 2.5, 10],
            cameraTarget: [0, 3.2, 0]
        )
    }()

    static let sparks = ParticlePreset(
        "Sparks",
        layers: [
            Layer("Sparks", settings: emitter {
                $0.position = [-0.8, 1.2, 0]
                $0.shape = .point
                $0.velocity = [3.5, 1.2, 0]
                $0.velocitySpread = 1.6
                $0.speedVariation = 1.5
                $0.gravity = [0, -9.8, 0]
                $0.drag = 0.3
                $0.lifetime = 0.6...1.6
                $0.birthRate = 2_500
                $0.restitution = 0.35
                $0.restitutionVariation = 0.15
                $0.friction = 0.3
                $0.blendMode = .additive
                $0.orientation = .velocityAligned(stretch: 0.6)
                $0.sizeOverLife = .linear(from: 0.012, to: 0.006)
                $0.colorOverLife = ParticleCurve([.init(0, [1, 0.95, 0.7, 1]), .init(0.4, [1, 0.55, 0.15, 1]), .init(1, [0.8, 0.15, 0.02, 0])])
            }, capacity: 10_000),
        ],
        colliders: [ground, .box(center: [1.6, 0.6, 0], halfExtents: [0.1, 0.6, 1])],
        cameraEye: [0.4, 1.6, 4],
        cameraTarget: [0.4, 0.8, 0]
    )

    static let smoke = ParticlePreset(
        "Smoke",
        layers: [
            Layer("Smoke", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 0.1, 0]
                $0.shape = .disc(radius: 0.4)
                $0.velocity = [0, 0.9, 0]
                $0.velocitySpread = 0.2
                $0.gravity = [0, 0.1, 0]
                $0.drag = 0.25
                $0.lifetime = 4...6
                $0.birthRate = 800
                $0.warmupDuration = 5
                $0.sizeOverLife = .linear(from: 0.15, to: 0.9)
                $0.colorOverLife = ParticleCurve([.init(0, [0.5, 0.5, 0.52, 0]), .init(0.1, [0.55, 0.55, 0.57, 0.07]), .init(0.5, [0.6, 0.6, 0.62, 0.05]), .init(1, [0.7, 0.7, 0.72, 0])])
                $0.colorVariation = [0, 0, 0.1, 0.03]
            }, capacity: 6_000),
        ],
        forceFields: [.wind(velocity: [0.8, 0, 0], strength: 0.25), .turbulence(strength: 0.8, scale: 0.8, speed: 0.4)],
        cameraEye: [0.5, 2.5, 9],
        cameraTarget: [1, 2.5, 0]
    )

    static let snow = ParticlePreset(
        "Snow",
        layers: [
            Layer("Snow", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 5, 0]
                $0.shape = .plane(size: [10, 10])
                $0.velocity = [0, -0.6, 0]
                $0.velocitySpread = 0.1
                $0.gravity = [0, -0.4, 0]
                $0.drag = 1.2
                $0.lifetime = 14...14
                $0.birthRate = 700
                $0.warmupDuration = 10
                $0.restitution = 0
                $0.friction = 1
                $0.sizeOverLife = .constant(0.02)
                $0.sizeVariation = 0.6
                $0.colorOverLife = ParticleCurve([.init(0, [0.9, 0.95, 1, 0]), .init(0.05, [0.9, 0.95, 1, 0.9]), .init(0.9, [0.9, 0.95, 1, 0.9]), .init(1, [0.9, 0.95, 1, 0])])
            }, capacity: 12_000),
        ],
        colliders: [ground, .sphere(center: [0, 0, 0], radius: 1)],
        forceFields: [.turbulence(strength: 0.6, scale: 0.6, speed: 0.3)],
        cameraEye: [0, 2.5, 7],
        cameraTarget: [0, 1.5, 0]
    )

    static let rain = ParticlePreset(
        "Rain",
        layers: [
            Layer("Rain", settings: emitter {
                $0.position = [0, 6, 0]
                $0.shape = .plane(size: [10, 8])
                $0.velocity = [0.6, -8, 0]
                $0.velocitySpread = 0.2
                $0.lifetime = 1.5...1.5
                $0.birthRate = 12_000
                $0.diesOnCollision = true
                $0.orientation = .velocityAligned(stretch: 1.2)
                $0.sizeOverLife = .constant(0.008)
                $0.colorOverLife = .constant([0.6, 0.7, 0.9, 0.45])
            }, capacity: 50_000),
            Layer("Splashes", settings: emitter {
                $0.position = [0, 0.02, 0]
                $0.shape = .plane(size: [10, 8])
                $0.velocity = [0, 1.2, 0]
                $0.velocitySpread = 0.6
                $0.lifetime = 0.25...0.4
                $0.birthRate = 6_000
                $0.sizeOverLife = .linear(from: 0.012, to: 0.003)
                $0.colorOverLife = .linear(from: [0.7, 0.8, 1, 0.7], to: [0.7, 0.8, 1, 0])
            }, capacity: 3_000),
        ],
        colliders: [ground, .box(center: [0, 1.4, 0.5], halfExtents: [1.4, 0.05, 1.2], rotation: simd_quatf(angle: 0.25, axis: [0, 0, 1]))]
    )

    static let magicTrail = ParticlePreset(
        "Magic Trail",
        layers: [
            Layer("Stars", settings: emitter {
                $0.shape = .sphere(radius: 0.08)
                $0.velocity = .zero
                $0.velocitySpread = 0.3
                $0.gravity = [0, -0.3, 0]
                $0.drag = 0.8
                $0.lifetime = 1.2...2.2
                $0.birthRate = 300
                $0.inheritVelocity = 0.25
                // Alpha, not additive: stars overlap heavily near the emitter and would blow out to white.
                $0.sizeOverLife = ParticleCurve([.init(0, 0.0), .init(0.1, 0.1), .init(1, 0.0)])
                $0.colorOverLife = .linear(from: [0.8, 0.45, 1, 0.8], to: [0.2, 0.7, 1, 0])
                $0.colorVariation = [0.12, 0.1, 0, 0]
                $0.angleVariation = .pi
                $0.angularSpeed = 2
                $0.angularSpeedVariation = 3
            }, sprite: .star, motion: EmitterMotion(kind: .figureEight, radius: 2, speed: 1.4, offset: [0, 1.6, 0]), capacity: 5_000),
            Layer("Dust", settings: emitter {
                $0.shape = .sphere(radius: 0.15)
                $0.velocity = .zero
                $0.velocitySpread = 0.15
                $0.gravity = [0, 0.1, 0]
                $0.lifetime = 2...3
                $0.birthRate = 800
                $0.blendMode = .additive
                $0.sizeOverLife = .constant(0.01)
                $0.colorOverLife = .linear(from: [1, 0.9, 1, 0.25], to: [0.6, 0.6, 1, 0])
            }, motion: EmitterMotion(kind: .figureEight, radius: 2, speed: 1.4, offset: [0, 1.6, 0]), capacity: 10_000),
        ],
        cameraEye: [0, 3, 4.5],
        cameraTarget: [0, 1.5, 0]
    )

    static let comet = ParticlePreset(
        "Comet",
        layers: [
            Layer("Tail", settings: emitter {
                $0.shape = .sphere(radius: 0.1)
                $0.velocity = [0, 0.25, 0]
                $0.velocitySpread = 0.15
                $0.gravity = .zero
                $0.drag = 0.3
                $0.lifetime = 2...3.5
                $0.birthRate = 6_000
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.02, to: 0.07)
                $0.colorOverLife = ParticleCurve([.init(0, [0.6, 0.85, 1, 0.25]), .init(0.3, [0.25, 0.45, 1, 0.1]), .init(1, [0.1, 0.1, 0.6, 0])])
            }, motion: EmitterMotion(kind: .circle, radius: 2.2, speed: 1.1, offset: [0, 1.8, 0]), capacity: 25_000),
            Layer("Core", settings: emitter {
                $0.shape = .sphere(radius: 0.06)
                $0.velocity = .zero
                $0.velocitySpread = 0.05
                $0.gravity = .zero
                $0.lifetime = 0.15...0.25
                $0.birthRate = 1_500
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.07, to: 0.03)
                $0.colorOverLife = .linear(from: [1, 1, 1, 0.3], to: [0.6, 0.8, 1, 0])
            }, motion: EmitterMotion(kind: .circle, radius: 2.2, speed: 1.1, offset: [0, 1.8, 0]), capacity: 2_000),
        ]
    )

    static let galaxy: ParticlePreset = {
        // Two arms: short arcs on opposite sides of a ring. Drag keeps the vortex from flinging stars out, and the
        // attractor pulls them into a spiral toward the core.
        func arm(_ name: String, turn: Float) -> Layer {
            Layer(name, settings: emitter {
                $0.shape = .torus(radius: 2.2, tubeRadius: 0.25)
                $0.sweepAngle = 0.9
                $0.velocity = .zero
                $0.velocitySpread = 0.05
                $0.gravity = .zero
                $0.drag = 1.5
                $0.lifetime = 5...8
                $0.birthRate = 4_000
                $0.warmupDuration = 6
                $0.blendMode = .additive
                $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.1, 0.012), .init(0.9, 0.01), .init(1, 0)])
                $0.sizeVariation = 0.6
                $0.colorOverLife = .linear(from: [0.5, 0.6, 1, 0.8], to: [1, 0.8, 0.6, 0.8])
                $0.colorVariation = [0.08, 0.3, 0.3, 0]
            }, motion: EmitterMotion(offset: [0, 1.5, 0], yaw: turn), capacity: 40_000)
        }
        return ParticlePreset(
            "Galaxy",
            layers: [
                arm("Arm 1", turn: 0),
                arm("Arm 2", turn: .pi),
                Layer("Core", settings: emitter {
                    $0.shape = .sphere(radius: 0.25)
                    $0.velocity = .zero
                    $0.velocitySpread = 0.05
                    $0.gravity = .zero
                    $0.lifetime = 1...2
                    $0.birthRate = 1_500
                    $0.blendMode = .additive
                    $0.sizeOverLife = .constant(0.05)
                    $0.colorOverLife = ParticleCurve([.init(0, [1, 0.9, 0.7, 0]), .init(0.3, [1, 0.85, 0.6, 0.12]), .init(1, [1, 0.8, 0.5, 0])])
                }, motion: EmitterMotion(offset: [0, 1.5, 0]), capacity: 3_000),
            ],
            forceFields: [
                .vortex(center: [0, 1.5, 0], strength: 3, radius: 0),
                .attractor(center: [0, 1.5, 0], strength: 1.2, radius: 0),
            ],
            cameraEye: [0, 5, 4.5],
            cameraTarget: [0, 1.5, 0]
        )
    }()

    static let waterfall = ParticlePreset(
        "Waterfall",
        layers: [
            Layer("Water", settings: emitter {
                $0.position = [0, 3.2, -1]
                $0.shape = .box(size: [2, 0.05, 0.2])
                $0.velocity = [0, 0, 1.6]
                $0.velocitySpread = 0.12
                $0.gravity = [0, -9.8, 0]
                $0.drag = 0.1
                $0.lifetime = 2...2.5
                $0.birthRate = 35_000
                $0.restitution = 0.25
                $0.friction = 0.2
                $0.orientation = .velocityAligned(stretch: 0.4)
                $0.sizeOverLife = .constant(0.01)
                $0.colorOverLife = .linear(from: [0.75, 0.88, 1, 0.5], to: [0.6, 0.75, 1, 0.15])
            }, capacity: 90_000),
            Layer("Mist", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 0.2, 0.2]
                $0.shape = .box(size: [2.4, 0.2, 1.2])
                $0.velocity = [0, 0.4, 0.3]
                $0.velocitySpread = 0.3
                $0.gravity = .zero
                $0.drag = 0.6
                $0.lifetime = 1.5...3
                $0.birthRate = 150
                $0.warmupDuration = 3
                $0.sizeOverLife = .linear(from: 0.2, to: 0.6)
                $0.colorOverLife = ParticleCurve([.init(0, [0.8, 0.9, 1, 0]), .init(0.2, [0.8, 0.9, 1, 0.12]), .init(1, [0.8, 0.9, 1, 0])])
                $0.angleVariation = .pi
            }, sprite: .smoke, capacity: 1_000),
        ],
        colliders: [
            ground,
            .sphere(center: [-0.4, 0.2, 0.4], radius: 0.45),
            .sphere(center: [0.5, 0.15, 0.7], radius: 0.35),
            .box(center: [0, 1.5, -1.3], halfExtents: [1.3, 1.6, 0.3]),
        ],
        cameraEye: [5, 2.2, 3.5],
        cameraTarget: [0, 1.4, 0]
    )

    static let confetti = ParticlePreset(
        "Confetti",
        layers: [
            Layer("Confetti", settings: emitter {
                // A slow shower from above; flat pieces that tumble in the turbulence and settle on the ground.
                $0.sortMode = .backToFront
                $0.position = [0, 5, 0]
                $0.shape = .plane(size: [6, 4])
                $0.velocity = [0, -0.5, 0]
                $0.velocitySpread = 0.3
                $0.gravity = [0, -1.5, 0]
                $0.drag = 2
                $0.lifetime = 9...9
                $0.birthRate = 500
                $0.warmupDuration = 7
                $0.restitution = 0
                $0.friction = 1
                $0.sizeOverLife = ParticleCurve([.init(0, 0.04), .init(0.9, 0.04), .init(1, 0)])
                $0.sizeVariation = 0.3
                $0.colorOverLife = .constant([1, 0.25, 0.3, 1])
                $0.colorVariation = [0.5, 0.1, 0, 0]
                $0.angleVariation = .pi
                $0.angularSpeedVariation = 8
            }, sprite: .triangle, capacity: 6_000),
        ],
        colliders: [ground],
        forceFields: [.turbulence(strength: 2, scale: 1, speed: 0.5)]
    )
}
