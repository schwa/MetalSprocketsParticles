import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct SubEmitterTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    /// Still children: no velocity, no gravity, long-lived, so tests can check where they started.
    func stillChild() -> ParticleEmitter {
        var child = ParticleEmitter()
        child.shape = .point
        child.velocity = .zero
        child.velocitySpread = 0
        child.gravity = .zero
        child.drag = 0
        child.lifetime = 10...10
        return child
    }

    func parent(_ sub: SubEmitter, configure: (inout ParticleEmitter) -> Void = { _ in }) -> ParticleEmitter {
        var parent = ParticleEmitter()
        parent.position = [0, 1, 0]
        parent.shape = .point
        parent.velocity = [1, 0, 0]
        parent.velocitySpread = 0
        parent.gravity = .zero
        parent.drag = 0
        parent.lifetime = 0.5...0.5
        parent.birthRate = 0
        parent.subEmitters = [sub]
        configure(&parent)
        return parent
    }

    func step(_ system: ParticleSystemRuntime, seconds: Float) throws {
        for _ in 0..<Int((seconds / deltaTime).rounded()) {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func alive(_ system: ParticleSystemRuntime, _ emitter: ParticleSystemRuntime.Emitter) -> [Particle] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return emitter.range.map { pointer[$0] }.filter { $0.velocity.w > 0 && $0.position.w < $0.velocity.w }
    }

    @Test func atAgeTransitionTurnsTheParentIntoItsChild() throws {
        // The parent lives 5 s but turns into a still-spawned child at 0.25 s, keeping its position and velocity.
        let transition = SubEmitter.transition(on: .atAge(seconds: 0.25), into: stillChild())
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(transition) { $0.lifetime = 5...5 })
        system.burst(4)
        try step(system, seconds: 0.2)
        #expect(alive(system, system.emitters[0]).count == 4)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
        try step(system, seconds: 0.2)
        #expect(alive(system, system.emitters[0]).isEmpty)
        let children = alive(system, system.subEmitterInstances[0])
        #expect(children.count == 4)
        // Moving at 1 unit/s along x for 0.4 s in total, with no break at the transition.
        #expect(children.allSatisfy { abs($0.velocity.x - 1) < 1e-4 && abs($0.position.x - 0.4) < 0.03 && abs($0.position.y - 1) < 1e-4 })
    }

    @Test func transitionsCanContinueTheParentsLife() throws {
        // Parent lives 2 s and turns into a child (own lifetime 10 s) at 0.5 s.
        func children(continuesLife: Bool) throws -> [Particle] {
            let transition = SubEmitter.transition(on: .atAge(seconds: 0.5), into: stillChild(), continuesLife: continuesLife)
            let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(transition) { $0.lifetime = 2...2 })
            system.burst(4)
            try step(system, seconds: 0.75)
            return alive(system, system.subEmitterInstances[0])
        }
        let fresh = try children(continuesLife: false)
        let continuing = try children(continuesLife: true)
        #expect(fresh.count == 4 && continuing.count == 4)
        // A fresh child is about 0.25 s into a 10 s life; a continuing one is about 0.75 s into the parent's 2 s life.
        #expect(fresh.allSatisfy { $0.position.w < 0.3 && $0.velocity.w == 10 })
        #expect(continuing.allSatisfy { abs($0.position.w - 0.75) < 0.05 && $0.velocity.w == 2 })
    }

    @Test func enteringAVolumeTransitionsOnlyParticlesThatCrossIt() throws {
        // Particles move along +x at 1 unit/s from (0, 1, 0). The box spans x 0.4...0.6 around y = 1, so they enter it
        // at about 0.4 s and have all turned into children by 0.75 s.
        let box = TriggerVolume.box(center: [0.5, 1, 0], halfExtents: [0.1, 0.5, 0.5])
        let transition = SubEmitter.transition(on: .onEntering(box), into: stillChild())
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(transition) { $0.lifetime = 5...5 })
        system.burst(4)
        try step(system, seconds: 0.25)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
        try step(system, seconds: 0.5)
        #expect(alive(system, system.emitters[0]).isEmpty)
        let children = alive(system, system.subEmitterInstances[0])
        #expect(children.count == 4)
        #expect(children.allSatisfy { $0.position.x > 0.4 })
        let decoded = try JSONDecoder().decode(SubEmitter.self, from: try JSONEncoder().encode(transition))
        #expect(decoded == transition)
    }

    /// Parent -> child -> grandchild, each turning into the next 0.25 s after it was born.
    func chain(depth: Int) -> SubEmitter {
        var settings = stillChild()
        settings.lifetime = 5...5
        var sub = SubEmitter.transition(on: .atAge(seconds: 0.25), into: settings)
        for _ in 1..<depth {
            var outer = settings
            outer.subEmitters = [sub]
            sub = .transition(on: .atAge(seconds: 0.25), into: outer)
        }
        return sub
    }

    @Test func transitionsChain() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(chain(depth: 2)) { $0.lifetime = 5...5 })
        #expect(system.subEmitterInstances.count == 2)
        #expect(system.subEmitterInstances[1].parent === system.subEmitterInstances[0])
        system.burst(4)
        try step(system, seconds: 0.4)
        // The parent turned into the child at 0.25 s; the child has not turned yet.
        #expect(alive(system, system.emitters[0]).isEmpty)
        #expect(alive(system, system.subEmitterInstances[0]).count == 4)
        #expect(alive(system, system.subEmitterInstances[1]).isEmpty)
        try step(system, seconds: 0.25)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
        let grandchildren = alive(system, system.subEmitterInstances[1])
        #expect(grandchildren.count == 4)
        // Still moving with the original parent's velocity, about 0.65 s along x.
        #expect(grandchildren.allSatisfy { abs($0.velocity.x - 1) < 1e-4 && abs($0.position.x - 0.65) < 0.05 })
    }

    @Test func nestingStopsAtTheMaximumDepth() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(chain(depth: ParticleSystemRuntime.maxSubEmitterDepth + 2)))
        #expect(system.subEmitterInstances.count == ParticleSystemRuntime.maxSubEmitterDepth)
    }

    @Test func addingANestedSubEmitterRebuilds() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(chain(depth: 1)))
        #expect(system.subEmitterInstances.count == 1)
        system.emitters[0].settings.subEmitters = [chain(depth: 2)]
        try runner.run(try system.simulate(deltaTime: deltaTime))
        #expect(system.subEmitterInstances.count == 2)
    }

    @Test func missingTheVolumeDoesNotTransition() throws {
        let away = TriggerVolume.sphere(center: [0, -5, 0], radius: 0.5)
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(.transition(on: .onEntering(away), into: stillChild())) { $0.lifetime = 5...5 })
        system.burst(4)
        try step(system, seconds: 1)
        #expect(alive(system, system.emitters[0]).count == 4)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
    }

    @Test func collisionTransitionReplacesOnlyParticlesThatHit() throws {
        let transition = SubEmitter.transition(on: .onCollision, into: stillChild(), sprite: .spark)
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(transition) {
            $0.lifetime = 5...5
            $0.velocity = .zero
            $0.gravity = [0, -9.8, 0]
        })
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        system.burst(4)
        try step(system, seconds: 0.3)
        #expect(alive(system, system.emitters[0]).count == 4)
        try step(system, seconds: 0.3)
        #expect(alive(system, system.emitters[0]).isEmpty)
        #expect(alive(system, system.subEmitterInstances[0]).count == 4)
        // The child draws with its own sprite.
        #expect(system.subEmitterInstances[0].texture != nil)
    }

    @Test func transitionSettingsRoundTripAndOldFilesStillLoad() throws {
        let transition = SubEmitter.transition(on: .atAge(seconds: 2), into: stillChild(), sprite: .star)
        let decoded = try JSONDecoder().decode(SubEmitter.self, from: try JSONEncoder().encode(transition))
        #expect(decoded == transition)
        // Saved before sprite and replacesParent existed.
        var old = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(SubEmitter(occasion: .onDeath, countPerEvent: 3, settings: stillChild()))) as? [String: Any])
        old["sprite"] = nil
        old["replacesParent"] = nil
        let loaded = try JSONDecoder().decode(SubEmitter.self, from: try JSONSerialization.data(withJSONObject: old))
        #expect(loaded.sprite == .softDot && !loaded.replacesParent && loaded.countPerEvent == 3)
    }

    @Test func instancesFollowEmittersInTheBuffer() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 10, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 4, settings: stillChild())))
        #expect(system.emitters.count == 1)
        let child = try #require(system.subEmitterInstances.first)
        #expect(child.capacity == 40)
        #expect(child.range == 10..<50)
        #expect(system.capacity == 50)
    }

    @Test func onDeathSpawnsChildrenWhereTheParentDied() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 6, settings: stillChild())))
        system.burst(1)
        try step(system, seconds: 0.3)
        let child = system.subEmitterInstances[0]
        #expect(alive(system, child).isEmpty)
        try step(system, seconds: 0.4)
        let children = alive(system, child)
        #expect(children.count == 6)
        // The parent moved at 1 m/s for 0.5 s from x = 0. Birth jitter is up to one step.
        for particle in children {
            #expect(abs(particle.position.x - 0.5) < 0.03)
            #expect(abs(particle.position.y - 1) < 1e-4)
        }
    }

    @Test func onBirthSpawnsChildrenWithTheParent() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onBirth, countPerEvent: 3, settings: stillChild())))
        system.burst(2)
        try step(system, seconds: deltaTime)
        #expect(alive(system, system.subEmitterInstances[0]).count == 6)
    }

    @Test func onCollisionSpawnsChildrenAtTheHit() throws {
        let falling = parent(SubEmitter(occasion: .onCollision, countPerEvent: 5, settings: stillChild())) {
            $0.velocity = [0, -2, 0]
            $0.lifetime = 5...5
            $0.restitution = 0
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: falling)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        system.burst(1)
        try step(system, seconds: 1)
        let children = alive(system, system.subEmitterInstances[0])
        #expect(children.count == 5)
        #expect(children.allSatisfy { abs($0.position.y) < 0.05 })
    }

    @Test func whileAliveLeavesATrail() throws {
        var trail = stillChild()
        trail.lifetime = 0.2...0.2
        let moving = parent(SubEmitter(occasion: .whileAlive(interval: 0.05), countPerEvent: 8, settings: trail)) {
            $0.lifetime = 5...5
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: moving)
        system.burst(1)
        try step(system, seconds: 1)
        let children = alive(system, system.subEmitterInstances[0])
        // A 0.2 s trail sampled every 0.05 s: three or four points, 0.05 m apart behind a parent moving at 1 m/s.
        #expect((3...5).contains(children.count))
        let xs = children.map(\.position.x).sorted()
        for (behind, ahead) in zip(xs, xs.dropFirst()) {
            #expect(abs(ahead - behind - 0.05) < 0.002)
        }
    }

    @Test func childrenInheritParentVelocity() throws {
        var moving = stillChild()
        moving.lifetime = 10...10
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 2, velocityFactor: 0.5, settings: moving)))
        system.burst(1)
        try step(system, seconds: 0.55)
        for child in alive(system, system.subEmitterInstances[0]) {
            #expect(abs(child.velocity.x - 0.5) < 1e-4)
        }
    }

    @Test func subEmittersAreDeterministic() throws {
        func run() throws -> [SIMD4<Float>] {
            var spray = stillChild()
            spray.velocitySpread = 1
            spray.shape = .sphere(radius: 0.1)
            let system = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 8, settings: spray)) {
                $0.birthRate = 120
                $0.velocitySpread = 1
            }, seed: 9)
            try step(system, seconds: 1)
            let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
            return (0..<system.capacity).map { pointer[$0].position }
        }
        // Two runs on purpose: results must be deterministic.
        // swiftlint:disable:next identical_operands
        #expect(try run() == run())
    }

    @Test func changingTheLayoutRebuilds() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 2, settings: stillChild())))
        system.emitter.subEmitters[0].countPerEvent = 5
        try step(system, seconds: deltaTime)
        #expect(system.subEmitterInstances.first?.capacity == 20)
        system.emitter.subEmitters = []
        try step(system, seconds: deltaTime)
        #expect(system.subEmitterInstances.isEmpty)
    }

    @Test func restartRemovesChildren() throws {
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onBirth, countPerEvent: 3, settings: stillChild())))
        system.burst(2)
        try step(system, seconds: deltaTime)
        system.restart()
        try step(system, seconds: deltaTime)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
    }
}
