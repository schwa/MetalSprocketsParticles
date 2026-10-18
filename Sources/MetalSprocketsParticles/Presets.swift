import simd
import SwiftMesh

private func emitter(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
    var emitter = ParticleEmitter()
    configure(&emitter)
    return emitter
}

private let ground = Collider.plane(normal: [0, 1, 0], distance: 0)

public extension ParticlePreset {
    static let all: [ParticlePreset] = [
        .fountain, .campfire, .fireworks, .sparks, .smoke, .snow, .rain, .magicTrail, .comet, .galaxy, .waterfall, .confetti,
        .portal, .hearts, .moonPhases, .colorSmoke, .pond, .ringOfFire, .swarms, .geyser, .bumper, .teapot, .timeWarp,
        .awning, .lantern, .dunk,
    ]

    /// Tracked objects: a ball (the tracked object "ball") bounces through a pool; each time it enters the water, an
    /// objectEnters trigger bursts a splash. An emitter following the same motion draws the ball.
    static let dunk: ParticlePreset = {
        let ballMotion = EmitterMotion(kind: .bounce, radius: 2.4, speed: 2, offset: [0, -0.3, 0])
        let water = TriggerVolume.box(center: [0, -0.1, 0], halfExtents: [1.5, 0.25, 1.5])
        return ParticlePreset("Dunk", cameraEye: [0, 2.5, 5.5], cameraTarget: [0, 0.8, 0]) {
            TrackedObject("ball", motion: ballMotion)
            Layer("Ball", settings: emitter {
                $0.shape = .point
                $0.velocity = .zero
                $0.velocitySpread = 0
                $0.gravity = .zero
                $0.lifetime = 0.05...0.05
                $0.birthRate = 120
                $0.sizeOverLife = .constant(0.2)
                $0.colorOverLife = .constant([1, 0.45, 0.3, 1])
            }, motion: ballMotion, simulationSpace: .local, capacity: 20)
            Layer("Splash", settings: emitter {
                $0.position = [0, 0.05, 0]
                $0.shape = .disc(radius: 0.3)
                $0.birthLocation = .surface
                $0.birthDirection = .normal
                $0.velocity = [0, 3.2, 0]
                $0.velocitySpread = 1.2
                $0.gravity = [0, -9.8, 0]
                $0.lifetime = 0.7...1.1
                $0.birthRate = 0
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.03, to: 0.01)
                $0.colorOverLife = .linear(from: [0.6, 0.85, 1, 1], to: [0.4, 0.6, 1, 0])
                $0.triggers = [EmissionTrigger(.objectEnters(name: "ball", volume: water), .burst(400))]
            }, capacity: 2_000)
            Layer("Surface", settings: emitter {
                $0.orientation = .fixed(normal: [0, 1, 0])
                $0.shape = .plane(size: [3, 3])
                $0.velocity = .zero
                $0.velocitySpread = 0
                $0.gravity = .zero
                $0.lifetime = 1.5...2.5
                $0.birthRate = 6
                $0.warmupDuration = 2
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.05, to: 0.5)
                $0.opacityOverLife = .linear(from: 0.6, to: 0)
                $0.colorOverLife = .constant([0.4, 0.6, 1, 1])
            }, sprite: .ring, capacity: 40)
        }
    }().commented("A ball bounces through a pool, and every time it enters the water a splash bursts up. Shows a tracked object and an object-enters trigger.")

    /// Lighting: smoke and dust motes lit by a warm lantern (point light) near their base and cool moonlight from the
    /// side, over low ambient light. The lantern's glow is a small unlit emitter.
    static let lantern: ParticlePreset = {
        let lanternPosition: SIMD3<Float> = [0, 0.6, 0.8]
        return ParticlePreset(
            "Lantern",
            layers: [
                Layer("Smoke", settings: emitter {
                    $0.isLit = true
                    $0.sortMode = .backToFront
                    $0.position = [0, 0.2, 0]
                    $0.shape = .disc(radius: 0.3)
                    $0.velocity = [0, 0.7, 0]
                    $0.velocitySpread = 0.2
                    $0.gravity = .zero
                    $0.drag = 0.3
                    $0.lifetime = 4...5
                    $0.birthRate = 30
                    $0.warmupDuration = 5
                    $0.sizeOverLife = .linear(from: 0.25, to: 0.9)
                    $0.opacityOverLife = ParticleCurve([.init(0, 0), .init(0.15, 0.7), .init(1, 0)])
                    $0.colorOverLife = .constant([0.9, 0.9, 0.9, 1])
                    $0.angleVariation = .pi
                    $0.angularSpeedVariation = 0.3
                }, sprite: .smoke, capacity: 400),
                Layer("Dust", settings: emitter {
                    $0.isLit = true
                    $0.position = [0, 1.2, 0]
                    $0.shape = .sphere(radius: 1.4)
                    $0.velocity = .zero
                    $0.velocitySpread = 0.05
                    $0.gravity = .zero
                    $0.lifetime = 3...6
                    $0.birthRate = 120
                    $0.warmupDuration = 6
                    $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.3, 0.02), .init(1, 0)])
                    $0.colorOverLife = .constant([1, 1, 1, 1])
                }, capacity: 1_000),
                Layer("Lantern Glow", settings: emitter {
                    // Sorted like the smoke, so it draws in front of it (the lantern is nearer the camera).
                    $0.sortMode = .backToFront
                    $0.position = lanternPosition
                    $0.shape = .point
                    $0.velocity = .zero
                    $0.velocitySpread = 0
                    $0.gravity = .zero
                    $0.lifetime = 1...1
                    $0.birthRate = 20
                    $0.warmupDuration = 1
                    $0.blendMode = .additive
                    $0.sizeOverLife = .constant(0.18)
                    $0.colorOverLife = .constant([1, 0.65, 0.25, 0.8])
                }, capacity: 40),
            ],
            forceFields: [.turbulence(strength: 0.4, scale: 0.8, speed: 0.3)],
            lights: [
                .point(position: lanternPosition, color: [1, 0.6, 0.25], intensity: 2.5, range: 2.5),
                .directional(direction: [1, -0.3, -0.2], color: [0.4, 0.5, 0.8], intensity: 0.6),
            ],
            ambientLight: [0.05, 0.05, 0.07],
            cameraEye: [0, 1.8, 4.5],
            cameraTarget: [0, 1.3, 0]
        )
    }().commented("Smoke and dust lit by a warm lantern and cool moonlight. Shows particle lighting: point and directional lights over low ambient light.")

    /// Category masks: rain (category 1) falls through a tilted awning (category 2) and slants in the wind (category 1),
    /// while sparks from a grinder above collide with both and ignore the wind.
    static let awning: ParticlePreset = {
        let rainCategory: UInt32 = 0b01
        let awningCategory: UInt32 = 0b10
        return ParticlePreset(
            "Awning",
            layers: [
                Layer("Rain", settings: emitter {
                    $0.collisionMask = rainCategory
                    $0.fieldMask = rainCategory
                    $0.position = [0, 5, 0]
                    $0.shape = .plane(size: [6, 4])
                    $0.velocity = [0, -7, 0]
                    $0.velocitySpread = 0.2
                    $0.lifetime = 1.5...1.5
                    $0.birthRate = 1_500
                    $0.warmupDuration = 1.5
                    $0.diesOnCollision = true
                    $0.orientation = .velocityAligned(stretch: 1)
                    $0.sizeOverLife = .constant(0.008)
                    $0.colorOverLife = .constant([0.6, 0.7, 0.9, 0.5])
                    $0.subEmitters = [SubEmitter(occasion: .onCollision, countPerEvent: 2, settings: emitter {
                        $0.shape = .point
                        $0.velocity = [0, 1, 0]
                        $0.velocitySpread = 0.5
                        $0.lifetime = 0.2...0.35
                        $0.sizeOverLife = .linear(from: 0.01, to: 0.003)
                        $0.colorOverLife = .linear(from: [0.7, 0.8, 1, 0.7], to: [0.7, 0.8, 1, 0])
                    })]
                }, capacity: 6_000),
                Layer("Sparks", settings: emitter {
                    $0.collisionMask = rainCategory | awningCategory
                    $0.fieldMask = awningCategory
                    $0.position = [0.3, 3.2, 0]
                    $0.shape = .point
                    $0.velocity = [0, -2, 0]
                    $0.velocitySpread = 1.5
                    $0.lifetime = 1.2...1.8
                    $0.birthRate = 900
                    $0.warmupDuration = 1
                    $0.restitution = 0.6
                    $0.friction = 0.1
                    $0.blendMode = .additive
                    $0.orientation = .velocityAligned(stretch: 0.6)
                    $0.sizeOverLife = .linear(from: 0.03, to: 0.008)
                    $0.colorOverLife = .linear(from: [1, 0.85, 0.4, 1], to: [1, 0.3, 0.05, 0])
                }, sprite: .spark, capacity: 2_000),
            ],
            colliders: [
                ground,
                // Thick enough that falling sparks cannot step over it in one frame (no continuous collision yet, #72).
                .box(center: [0, 2, 0], halfExtents: [1.6, 0.15, 1.2], rotation: simd_quatf(angle: -0.2, axis: [0, 0, 1]), categoryBitMask: awningCategory),
            ],
            forceFields: [.wind(velocity: [5, 0, 0], strength: 3, categoryBitMask: rainCategory)],
            cameraEye: [0, 2.6, 6.5],
            cameraTarget: [0, 1.6, 0]
        )
    }().commented("Rain falls straight through an awning and slants in the wind, while sparks from a grinder land on the awning and slide off. Shows category masks: each emitter chooses which colliders and fields affect it.")

    /// Clocks spiral into a glowing core, each ticking through the clock-face flipbook from its own hour.
    static let timeWarp: ParticlePreset = {
        let center: SIMD3<Float> = [0, 1.5, 0]
        return ParticlePreset(
            "Time Warp",
            layers: [
                Layer("Clocks", settings: emitter {
                    $0.sortMode = .backToFront
                    $0.position = center
                    $0.shape = .torus(radius: 2.4, tubeRadius: 0.3)
                    $0.birthLocation = .surface
                    $0.birthDirection = .tangent
                    $0.velocity = [0, 0, 1.5]
                    $0.velocitySpread = 0.1
                    $0.gravity = .zero
                    $0.drag = 0.4
                    $0.lifetime = 3...3.5
                    $0.birthRate = 16
                    $0.warmupDuration = 5
                    $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.1, 0.2), .init(0.8, 0.14), .init(1, 0)])
                    $0.colorOverLife = .constant([1, 1, 1, 1])
                    $0.angleVariation = .pi
                    $0.angularSpeedVariation = 2
                    var hours = ParticleSprite.clockFaces.defaultImageSequence!
                    hours.frameRate = 6
                    hours.initialFrameVariation = 12
                    $0.imageSequence = hours
                }, sprite: .clockFaces, capacity: 200),
                Layer("Core", settings: emitter {
                    $0.position = center
                    $0.shape = .sphere(radius: 0.25)
                    $0.velocity = .zero
                    $0.velocitySpread = 0.3
                    $0.gravity = .zero
                    $0.drag = 1
                    $0.lifetime = 0.8...1.4
                    $0.birthRate = 40
                    $0.warmupDuration = 2
                    $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.3, 0.22), .init(1, 0)])
                    $0.colorOverLife = .constant([1, 1, 1, 1])
                    $0.angularSpeedVariation = 3
                }, sprite: .glowingStar, capacity: 200),
            ],
            forceFields: [
                .vortex(center: center, strength: 2.5, radius: 4),
                .attractor(center: center, strength: 2.2, radius: 4),
            ],
            cameraEye: [0, 4, 6],
            cameraTarget: center
        )
    }().commented("Clocks orbit a glowing star, each ticking through the hours from its own starting time. Shows an emoji flipbook in a vortex.")

    /// The Utah teapot (from SwiftMesh) outlined in glowing particles and slowly dissolving into sand that pours onto
    /// the ground. Both layers emit from the mesh surface.
    static let teapot: ParticlePreset = {
        let mesh = Mesh.teapot(diameter: 2.4)
        // Side on, so the spout and handle show.
        let motion = EmitterMotion(offset: [0, 1, 0], yaw: .pi / 2)
        return ParticlePreset(
            "Teapot",
            layers: [
                Layer("Glow", settings: emitter {
                    $0.shape = .mesh
                    $0.velocity = .zero
                    $0.velocitySpread = 0.02
                    $0.gravity = .zero
                    $0.lifetime = 0.6...1
                    $0.birthRate = 40_000
                    $0.warmupDuration = 1
                    $0.blendMode = .additive
                    $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.3, 0.008), .init(1, 0)])
                    $0.colorOverLife = .constant([0.3, 0.7, 1, 1])
                }, motion: motion, capacity: 50_000, mesh: mesh),
                Layer("Sand", settings: emitter {
                    $0.shape = .mesh
                    $0.velocity = [0.4, 0.3, 0]
                    $0.velocitySpread = 0.3
                    $0.gravity = [0, -4, 0]
                    $0.lifetime = 3...4
                    $0.birthRate = 6_000
                    $0.warmupDuration = 3
                    $0.restitution = 0
                    $0.friction = 0.9
                    $0.sizeOverLife = .constant(0.01)
                    $0.colorOverLife = ParticleCurve([.init(0, [1, 0.85, 0.5, 1]), .init(0.8, [0.9, 0.6, 0.3, 1]), .init(1, [0.9, 0.6, 0.3, 0])])
                    $0.colorVariation = [0.03, 0.1, 0.2, 0]
                }, motion: motion, capacity: 30_000, mesh: mesh),
            ],
            colliders: [ground],
            forceFields: [.turbulence(strength: 0.5, scale: 1.5, speed: 0.4)],
            cameraEye: [0, 2.5, 5],
            cameraTarget: [0, 1, 0]
        )
    }().commented("The Utah teapot outlined in glowing particles, slowly dissolving into sand that pours onto the ground. Shows emission from the surface of a mesh.")

    /// Emission triggers: balls drop onto a bumper (collider hit: spark burst), some bounce into a goal on the left
    /// (particles enter a volume: star burst), a ring pulses on the ground every 2 seconds (timer), and
    /// sending the event "boom" fires a shower of confetti.
    static let bumper: ParticlePreset = {
        let goal = TriggerVolume.box(center: [-1.6, 0.25, 0], halfExtents: [0.5, 0.25, 1])
        return ParticlePreset(
            "Bumper",
            layers: [
                Layer("Balls", settings: emitter {
                    $0.position = [0, 4, 0]
                    $0.shape = .point
                    $0.velocity = .zero
                    $0.velocitySpread = 0.15
                    $0.lifetime = 4...4
                    $0.birthRate = 6
                    $0.restitution = 0.7
                    $0.friction = 0.2
                    $0.sizeOverLife = .constant(0.07)
                    $0.colorOverLife = .constant([1, 1, 1, 1])
                }, capacity: 100),
                Layer("Bumper Sparks", settings: emitter {
                    $0.position = [0, 1.5, 0]
                    $0.shape = .sphere(radius: 0.42)
                    $0.birthLocation = .surface
                    $0.birthDirection = .normal
                    // Short-lived and slow, so sparks stay near the bumper and never fall into the goal.
                    $0.velocity = [0, 1.2, 0]
                    $0.velocitySpread = 0.3
                    $0.gravity = .zero
                    $0.drag = 2
                    $0.lifetime = 0.2...0.4
                    $0.birthRate = 0
                    $0.blendMode = .additive
                    $0.sizeOverLife = .linear(from: 0.03, to: 0)
                    $0.colorOverLife = .linear(from: [1, 0.8, 0.3, 1], to: [1, 0.2, 0, 0])
                    $0.triggers = [EmissionTrigger(.colliderHit(index: 1), .burst(150))]
                }, sprite: .spark, capacity: 3_000),
                Layer("Goal Stars", settings: emitter {
                    $0.position = [-1.6, 0.3, 0]
                    $0.shape = .disc(radius: 0.4)
                    $0.velocity = [0, 2.5, 0]
                    $0.velocitySpread = 1
                    $0.gravity = [0, -2, 0]
                    $0.lifetime = 0.8...1.2
                    $0.birthRate = 0
                    $0.blendMode = .additive
                    $0.sizeOverLife = .linear(from: 0.08, to: 0)
                    $0.colorOverLife = .constant([0.3, 1, 0.5, 1])
                    $0.angularSpeedVariation = 6
                    $0.triggers = [EmissionTrigger(.particlesEnter(volume: goal), .burst(30))]
                }, sprite: .star, capacity: 2_000),
                Layer("Pulse", settings: emitter {
                    $0.orientation = .fixed(normal: [0, 1, 0])
                    $0.position = [0, 0.02, 0]
                    $0.shape = .point
                    $0.velocity = .zero
                    $0.velocitySpread = 0
                    $0.gravity = .zero
                    $0.lifetime = 1.2...1.2
                    $0.birthRate = 0
                    $0.blendMode = .additive
                    $0.sizeOverLife = .linear(from: 0.1, to: 2.5)
                    $0.opacityOverLife = .linear(from: 1, to: 0)
                    $0.colorOverLife = .constant([0.3, 0.6, 1, 1])
                    $0.triggers = [EmissionTrigger(.every(seconds: 2), .burst(1))]
                }, sprite: .ring, capacity: 10),
                Layer("Confetti", settings: emitter {
                    $0.position = [0, 3.5, 0]
                    $0.shape = .sphere(radius: 0.2)
                    $0.velocity = [0, 3, 0]
                    $0.velocitySpread = 3
                    $0.gravity = [0, -3, 0]
                    $0.drag = 1.5
                    $0.lifetime = 2.5...3
                    $0.birthRate = 0
                    $0.restitution = 0
                    $0.friction = 1
                    $0.sizeOverLife = .constant(0.04)
                    $0.colorOverLife = .constant([1, 0.3, 0.4, 1])
                    $0.colorVariation = [0.5, 0, 0, 0]
                    $0.angleVariation = .pi
                    $0.angularSpeedVariation = 8
                    $0.triggers = [EmissionTrigger(.event("boom"), .burst(800))]
                }, sprite: .triangle, capacity: 2_000),
            ],
            colliders: [ground, .sphere(center: [0, 1.5, 0], radius: 0.4)],
            cameraEye: [0, 2.5, 6],
            cameraTarget: [0, 1.4, 0]
        )
    }().commented("Balls drop onto a bumper. Each hit bursts sparks, balls that bounce into the goal burst stars, a ring pulses every 2 seconds, and sending the event 'boom' fires confetti. Shows the emission triggers.")

    /// A geyser that erupts for 1.5 seconds every 4 (emit/idle loop): a water column from a cylinder, opaque rock
    /// debris, and steam rising from a cone, blended with screen so it brightens without blowing out.
    static let geyser: ParticlePreset = {
        func erupting(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
            emitter {
                $0.emissionDuration = 1.5
                $0.idleDuration = 2.5
                $0.loops = true
                configure(&$0)
            }
        }
        return ParticlePreset(
            "Geyser",
            layers: [
                Layer("Water", settings: erupting {
                    $0.shape = .cylinder(radius: 0.15, height: 0.1)
                    $0.velocity = [0, 9, 0]
                    $0.velocitySpread = 0.8
                    $0.lifetime = 1.5...2
                    $0.birthRate = 8_000
                    $0.restitution = 0.1
                    $0.sizeOverLife = .linear(from: 0.02, to: 0.01)
                    $0.colorOverLife = .linear(from: [0.75, 0.9, 1, 0.8], to: [0.6, 0.8, 1, 0])
                }, capacity: 20_000),
                Layer("Rocks", settings: erupting {
                    $0.shape = .cylinder(radius: 0.2, height: 0.1)
                    $0.velocity = [0, 7, 0]
                    $0.velocitySpread = 2
                    $0.lifetime = 3...3
                    $0.birthRate = 40
                    $0.restitution = 0.3
                    $0.friction = 0.8
                    $0.blendMode = .opaque
                    $0.sizeOverLife = .constant(0.05)
                    $0.sizeVariation = 0.5
                    $0.colorOverLife = .constant([0.35, 0.3, 0.27, 1])
                    $0.colorVariation = [0, 0, 0.15, 0]
                    $0.angleVariation = .pi
                    $0.angularSpeedVariation = 10
                }, sprite: .triangle, capacity: 300),
                Layer("Steam", settings: emitter {
                    $0.shape = .cone(radius: 0.5, height: 0.6)
                    $0.velocity = [0, 1, 0]
                    $0.velocitySpread = 0.3
                    $0.gravity = .zero
                    $0.lifetime = 2...3
                    $0.birthRate = 40
                    $0.warmupDuration = 3
                    $0.blendMode = .screen
                    $0.sizeOverLife = .linear(from: 0.2, to: 0.8)
                    $0.opacityOverLife = ParticleCurve([.init(0, 0), .init(0.2, 0.2), .init(1, 0)])
                    $0.colorOverLife = .constant([0.6, 0.65, 0.7, 1])
                    $0.angleVariation = .pi
                }, sprite: .smoke, capacity: 500),
            ],
            colliders: [ground],
            forceFields: [.wind(velocity: [0.6, 0, 0], strength: 0.4)],
            cameraEye: [0, 3, 8],
            cameraTarget: [0, 2.5, 0]
        )
    }().commented("A geyser erupts for 1.5 seconds every 4: water shoots from a cylinder, rocks tumble out and bounce, and steam rises from a cone. Shows the emit/idle loop, opaque particles, and screen blending.")

    /// Two identical firefly swarms circling side by side. The gold one simulates in local space and travels as a
    /// tight cloud; the blue one simulates in world space and leaves its fireflies behind as a trail.
    static let swarms: ParticlePreset = {
        func swarm(_ name: String, color: SIMD4<Float>, x: Float, space: SimulationSpace) -> Layer {
            Layer(name, settings: emitter {
                $0.shape = .sphere(radius: 0.25)
                $0.velocity = .zero
                $0.velocitySpread = 0.4
                $0.gravity = .zero
                $0.drag = 1
                $0.lifetime = 1.5...2
                $0.birthRate = 300
                $0.warmupDuration = 2
                $0.blendMode = .additive
                $0.sizeOverLife = ParticleCurve([.init(0, 0), .init(0.2, 0.04), .init(1, 0)])
                $0.colorOverLife = .constant(color)
            }, motion: EmitterMotion(kind: .circle, radius: 1, speed: 1.5, offset: [x, 1.5, 0]), simulationSpace: space, capacity: 1_000)
        }
        return ParticlePreset(
            "Swarms",
            layers: [
                swarm("Local Swarm", color: [1, 0.8, 0.3, 1], x: -1.4, space: .local),
                swarm("World Swarm", color: [0.3, 0.7, 1, 1], x: 1.4, space: .world),
            ],
            cameraEye: [0, 4, 6]
        )
    }().commented("Two identical firefly swarms circle side by side. The gold one simulates in local space and travels as a tight cloud; the blue one simulates in world space and leaves a trail.")

    /// Rain drops on a pond: each drop spreads a ripple that lies flat on the water (fixed orientation).
    static let pond = ParticlePreset(
        "Pond",
        layers: [
            Layer("Ripples", settings: emitter {
                $0.orientation = .fixed(normal: [0, 1, 0])
                $0.position = [0, 0.01, 0]
                $0.shape = .plane(size: [6, 6])
                $0.velocity = .zero
                $0.velocitySpread = 0
                $0.gravity = .zero
                $0.lifetime = 1.5...2.5
                $0.birthRate = 12
                $0.warmupDuration = 3
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.02, to: 0.7)
                $0.opacityOverLife = .linear(from: 0.9, to: 0)
                $0.colorOverLife = .constant([0.6, 0.85, 1, 1])
            }, sprite: .ring, capacity: 200),
            Layer("Drops", settings: emitter {
                // Emoji droplets, billboarded so their point stays up.
                $0.position = [0, 4, 0]
                $0.shape = .plane(size: [6, 6])
                $0.velocity = [0, -6, 0]
                $0.velocitySpread = 0
                $0.gravity = [0, -9.8, 0]
                $0.lifetime = 2...2
                $0.birthRate = 40
                $0.warmupDuration = 2
                $0.diesOnCollision = true
                $0.sizeOverLife = .constant(0.12)
                $0.colorOverLife = .constant([1, 1, 1, 1])
            }, sprite: .droplet, capacity: 200),
        ],
        colliders: [ground],
        cameraEye: [0, 3.5, 5],
        cameraTarget: [0, 0, 0]
    ).commented("Raindrops fall into a pond, and each one spreads a ripple that lies flat on the water. Shows fixed (flat) orientation and emoji droplet sprites.")

    /// A ring of emoji flames seen from above. Y-aligned flames stay upright and only turn around Y, so they do not
    /// tip over toward the camera like billboards would.
    static let ringOfFire = ParticlePreset(
        "Ring of Fire",
        layers: [
            Layer("Flames", settings: emitter {
                $0.orientation = .yAligned
                $0.sortMode = .backToFront
                $0.shape = .torus(radius: 2, tubeRadius: 0.05)
                $0.velocity = [0, 0.6, 0]
                $0.velocitySpread = 0.1
                $0.gravity = .zero
                $0.lifetime = 0.8...1.2
                $0.birthRate = 150
                $0.warmupDuration = 2
                $0.sizeOverLife = ParticleCurve([.init(0, 0.1), .init(0.3, 0.3), .init(1, 0.05)])
                $0.opacityOverLife = ParticleCurve([.init(0, 0), .init(0.15, 1), .init(0.7, 1), .init(1, 0)])
                $0.colorOverLife = .constant([1, 1, 1, 1])
            }, sprite: .fire, capacity: 1_000),
            Layer("Embers", settings: emitter {
                $0.shape = .torus(radius: 2, tubeRadius: 0.1)
                $0.velocity = [0, 1.5, 0]
                $0.velocitySpread = 0.6
                $0.gravity = [0, 0.3, 0]
                $0.lifetime = 1...2
                $0.birthRate = 80
                $0.warmupDuration = 2
                $0.blendMode = .additive
                $0.sizeOverLife = .linear(from: 0.02, to: 0)
                $0.colorOverLife = .linear(from: [1, 0.7, 0.2, 1], to: [1, 0.2, 0, 0])
            }, capacity: 500),
        ],
        forceFields: [.turbulence(strength: 1, scale: 1, speed: 0.6)],
        cameraEye: [0, 4.5, 5],
        cameraTarget: [0, 0.3, 0]
    ).commented("A ring of emoji flames seen from above. The flames are Y-aligned: they stay upright and turn only around Y, instead of tipping toward the camera like billboards.")

    /// Thick, nearly opaque puffs of colored smoke billowing up and out. Every puff overlaps others, so drawing them
    /// back to front matters: switch Sort to None to see far puffs paint over near ones.
    static let colorSmoke = ParticlePreset(
        "Color Smoke",
        layers: [
            Layer("Puffs", settings: emitter {
                $0.sortMode = .backToFront
                $0.position = [0, 0.3, 0]
                $0.shape = .sphere(radius: 0.3)
                $0.velocity = [0, 1.2, 0]
                $0.velocitySpread = 1.2
                $0.gravity = .zero
                $0.drag = 0.8
                $0.lifetime = 3...4
                $0.birthRate = 60
                $0.warmupDuration = 4
                $0.sizeOverLife = ParticleCurve([.init(0, 0.15), .init(1, 0.6)])
                $0.sizeVariation = 0.3
                $0.opacityOverLife = ParticleCurve([.init(0, 0), .init(0.08, 0.95), .init(0.7, 0.9), .init(1, 0)])
                $0.colorOverLife = .constant([1, 0.3, 0.5, 1])
                $0.colorVariation = [0.5, 0.1, 0.1, 0]
                $0.angleVariation = .pi
                $0.angularSpeedVariation = 0.6
            }, sprite: .smoke, capacity: 1_000),
        ],
        forceFields: [.turbulence(strength: 0.6, scale: 0.7, speed: 0.3)]
    ).commented("Thick, nearly opaque colored smoke billows up and out. Every puff overlaps others, so drawing back to front matters: set Sort to None to see far puffs paint over near ones.")

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
    ).commented("Emoji hearts float up and wobble, with pink sparkles. Shows emoji sprites drawn with Core Text: tint them white so they keep their own colors.")

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
    ).commented("Emoji moons orbit slowly, each cycling through the moon phases from its own starting phase. Shows a sprite-sheet flipbook with random start frames.")

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
    }().commented("A sorcerer's portal: a spinning ring of fire that throws sparks off its rim like a Catherine wheel. Shows tangential birth direction and a spinning emitter whose births spread along its rotation.")

    static let fountain = ParticlePreset(
        "Fountain",
        layers: [Layer("Fountain", settings: .fountain, capacity: 100_000)],
        colliders: ParticleEmitter.fountainColliders(time: 0),
        animatesColliders: true
    ).commented("A water fountain sprays up and falls back onto the ground and a few colliders that move around. Shows gravity, bouncing, and colliders that push and carry particles as they move.")

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
    ).commented("Flames, rising smoke, and embers over two logs. The flames are additive smoke puffs, the smoke is alpha-blended and sorted back to front, the embers are velocity-stretched sparks, and turbulence makes everything flicker. The logs are rotated capsule colliders.")

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
    }().commented("Rockets climb from the ground, leave sparkle trails, and burst into shells of stars when they burn out. Shows sub-emitters: a while-alive trail and an on-death burst.")

    static let sparks = ParticlePreset("Sparks", cameraEye: [0.4, 1.6, 4], cameraTarget: [0.4, 0.8, 0]) {
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
        }, capacity: 10_000)
        ground
        Collider.box(center: [1.6, 0.6, 0], halfExtents: [0.1, 0.6, 1])
    }.commented("Grinder sparks streak across the floor and bounce off a wall. Shows velocity-aligned stretching, bounce with per-particle variation, and friction. Written with the preset result builder.")

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
    ).commented("Soft smoke drifts up and sideways in the wind, curling in turbulence. Shows alpha-blended sprites drawn back to front, wind, and turbulence.")

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
    ).commented("Snowflakes drift down through gentle turbulence and settle on the ground and on a sphere. Shows plane emission over a large area, turbulence, and particles that come to rest on colliders.")

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
                // Each drop that hits the ground or the slab splashes where it lands.
                $0.subEmitters = [SubEmitter(occasion: .onCollision, countPerEvent: 3, settings: emitter {
                    $0.shape = .point
                    $0.velocity = [0, 1.2, 0]
                    $0.velocitySpread = 0.6
                    $0.lifetime = 0.25...0.4
                    $0.sizeOverLife = .linear(from: 0.012, to: 0.003)
                    $0.colorOverLife = .linear(from: [0.7, 0.8, 1, 0.7], to: [0.7, 0.8, 1, 0])
                })]
            }, capacity: 50_000),
        ],
        colliders: [ground, .box(center: [0, 1.4, 0.5], halfExtents: [1.4, 0.05, 1.2], rotation: simd_quatf(angle: 0.25, axis: [0, 0, 1]))]
    ).commented("Rain falls onto the ground and a tilted slab. Each drop dies when it hits and splashes where it lands. Shows velocity stretching, die-on-collision, and an on-collision sub-emitter.")

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
    ).commented("A wand of stars traces a figure eight, leaving a continuous trail and drifting dust. Shows a moving emitter, births spread along its path, and inherited velocity.")

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
    ).commented("A comet circles overhead with a long glowing tail and a bright core. Shows a fast-moving emitter that still leaves a smooth trail.")

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
    }().commented("Two spiral arms of stars swirl around a bright core. Shows torus emitters, a vortex force field, and an attractor.")

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
    ).commented("A sheet of water pours over a ledge, hits rocks, and throws up mist. Shows a box emitter, collisions, and soft sorted mist.")

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
    ).commented("Confetti flutters down, tumbling as it falls, and settles on the ground. Shows textured sprites with random spin, turbulence, and friction.")
}
