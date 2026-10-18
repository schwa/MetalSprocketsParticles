import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
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

    func step(_ system: ParticleSystem, seconds: Float) throws {
        for _ in 0..<Int((seconds / deltaTime).rounded()) {
            try runner.run(try system.simulate(deltaTime: deltaTime))
        }
    }

    func alive(_ system: ParticleSystem, _ emitter: ParticleSystem.Emitter) -> [Particle] {
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return emitter.range.map { pointer[$0] }.filter { $0.velocity.w > 0 && $0.position.w < $0.velocity.w }
    }

    @Test func instancesFollowEmittersInTheBuffer() throws {
        let system = try ParticleSystem(device: runner.device, capacity: 10, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 4, settings: stillChild())))
        #expect(system.emitters.count == 1)
        let child = try #require(system.subEmitterInstances.first)
        #expect(child.capacity == 40)
        #expect(child.range == 10..<50)
        #expect(system.capacity == 50)
    }

    @Test func onDeathSpawnsChildrenWhereTheParentDied() throws {
        let system = try ParticleSystem(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 6, settings: stillChild())))
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
        let system = try ParticleSystem(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onBirth, countPerEvent: 3, settings: stillChild())))
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
        let system = try ParticleSystem(device: runner.device, capacity: 1, emitter: falling)
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
        let system = try ParticleSystem(device: runner.device, capacity: 1, emitter: moving)
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
        let system = try ParticleSystem(device: runner.device, capacity: 1, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 2, velocityFactor: 0.5, settings: moving)))
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
            let system = try ParticleSystem(device: runner.device, capacity: 64, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 8, settings: spray)) {
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
        let system = try ParticleSystem(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onDeath, countPerEvent: 2, settings: stillChild())))
        system.emitter.subEmitters[0].countPerEvent = 5
        try step(system, seconds: deltaTime)
        #expect(system.subEmitterInstances.first?.capacity == 20)
        system.emitter.subEmitters = []
        try step(system, seconds: deltaTime)
        #expect(system.subEmitterInstances.isEmpty)
    }

    @Test func restartRemovesChildren() throws {
        let system = try ParticleSystem(device: runner.device, capacity: 4, emitter: parent(SubEmitter(occasion: .onBirth, countPerEvent: 3, settings: stillChild())))
        system.burst(2)
        try step(system, seconds: deltaTime)
        system.restart()
        try step(system, seconds: deltaTime)
        #expect(alive(system, system.subEmitterInstances[0]).isEmpty)
    }
}
