import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesShaders
import simd
import Testing

/// User Metal functions (`UpdateFunctionModule`) compiled at runtime and called from the simulation kernel.
@Suite(.serialized, .requiresMetal4)
struct ParticleFunctionTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// Sets velocity to parameters[0].xyz every step.
    let setVelocity = ParticleFunction(source: """
    [[visible]] void setVelocity(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
        particle.velocity = parameters[0].xyz;
    }
    """, name: "setVelocity", parameters: [[0, 5, 0, 0]])

    func fallingEmitter(_ configure: (inout EmitterModules) -> Void = { _ in }) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = [0, -9.8, 0] }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        configure(&emitter)
        return emitter
    }

    /// Velocities of every particle after bursting `count` per emitter and running `frames` steps.
    func velocities(_ system: ParticleSystemRuntime, count: Int, frames: Int = 30) throws -> [[SIMD3<Float>]] {
        for emitter in system.emitters {
            emitter.burst(count)
        }
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return system.emitters.map { emitter in
            emitter.range.prefix(count).map { SIMD3(pointer[$0].velocity.x, pointer[$0].velocity.y, pointer[$0].velocity.z) }
        }
    }

    @Test func updateFunctionAppliesOnlyToItsEmitter() throws {
        let lifted = fallingEmitter { $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: setVelocity) }
        let system = try ParticleSystemRuntime(device: runner.device, modules: [lifted, fallingEmitter()], capacity: 32)
        let result = try velocities(system, count: 16)
        // Gravity is applied before the function, so the function wins; the other emitter just falls.
        #expect(result[0].allSatisfy { simd_distance($0, [0, 5, 0]) < 1e-4 })
        #expect(result[1].allSatisfy { $0.y < -4 })
    }

    @Test func parametersReachTheFunction() throws {
        var function = setVelocity
        function.parameters = [[2, 0, -3, 0]]
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: fallingEmitter { $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: function) })
        let result = try velocities(system, count: 16)
        #expect(result[0].allSatisfy { simd_distance($0, [2, 0, -3]) < 1e-4 })
    }

    /// Puts each new particle on a ring of radius parameters[0].x at height parameters[0].y, still, living
    /// parameters[0].z seconds.
    let ring = ParticleFunction(source: """
    [[visible]] void ring(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
        float angle = float(particle.id) * 0.7;
        particle.position = float3(cos(angle), 0, sin(angle)) * parameters[0].x + float3(0, parameters[0].y, 0);
        particle.velocity = float3(0);
        particle.lifetime = parameters[0].z;
    }
    """, name: "ring", parameters: [[2, 1, 3.5, 0]])

    @Test func spawnFunctionPlacesNewParticles() throws {
        let emitter = fallingEmitter {
            $0.edit(GravityModule.self) { $0.acceleration = .zero }
            $0[SpawnFunctionModule.self] = SpawnFunctionModule(function: ring)
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: emitter)
        system.burst(16)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 16)
        for index in 0..<16 {
            let particle = pointer[index]
            #expect(abs(simd_length(SIMD2(particle.position.x, particle.position.z)) - 2) < 1e-4)
            #expect(abs(particle.position.y - 1) < 1e-4)
            #expect(particle.velocity.w == 3.5)
        }
    }

    @Test func spawnAndUpdateFunctionsWorkTogether() throws {
        let emitter = fallingEmitter {
            $0[SpawnFunctionModule.self] = SpawnFunctionModule(function: ring)
            $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: setVelocity)
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: emitter)
        let result = try velocities(system, count: 16, frames: 10)
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 16)
        #expect(result[0].allSatisfy { simd_distance($0, [0, 5, 0]) < 1e-4 })
        // Started on the ring at y = 1 and rose at 5 units/s.
        #expect((0..<16).allSatisfy { pointer[$0].position.y > 1.5 && abs(simd_length(SIMD2(pointer[$0].position.x, pointer[$0].position.z)) - 2) < 1e-3 })
    }

    @Test func oneFunctionWithDifferentParametersInTwoSlots() throws {
        // Same source and name, different parameters: still one compiled function, which must be linked once.
        var spawnVersion = setVelocity
        spawnVersion.parameters = [[0, 1, 0, 0]]
        let emitter = fallingEmitter {
            $0[SpawnFunctionModule.self] = SpawnFunctionModule(function: spawnVersion)
            $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: setVelocity)
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: emitter)
        let result = try velocities(system, count: 16, frames: 3)
        #expect(result[0].allSatisfy { simd_distance($0, [0, 5, 0]) < 1e-4 })
    }

    @Test func oneFunctionCanBeBothSpawnAndUpdate() throws {
        // Linking the same function twice would fail pipeline creation.
        let emitter = fallingEmitter {
            $0[SpawnFunctionModule.self] = SpawnFunctionModule(function: setVelocity)
            $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: setVelocity)
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: emitter)
        let result = try velocities(system, count: 16, frames: 3)
        #expect(result[0].allSatisfy { simd_distance($0, [0, 5, 0]) < 1e-4 })
    }

    /// Particles dropped 0.5 above a floor, `frames` steps; returns them all.
    func dropOntoFloor(frames: Int, _ configure: (inout EmitterModules) -> Void) throws -> [Particle] {
        var emitter = fallingEmitter(configure)
        emitter.edit(ShapeModule.self) { $0.position = [0, 0.5, 0] }
        emitter.edit(CollisionModule.self) { $0.restitution = 1 }
        emitter.edit(CollisionModule.self) { $0.friction = 0 }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 8, modules: emitter)
        system.colliders = [.plane(normal: [0, 1, 0], distance: 0)]
        system.burst(8)
        for _ in 0..<frames {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 8)
        return (0..<8).map { pointer[$0] }
    }

    @Test func collisionFunctionCanStopTheBounce() throws {
        let stick = ParticleFunction(source: """
        [[visible]] void stick(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            particle.velocity = float3(0);
        }
        """, name: "stick")
        // Hits the floor after about 0.32 s; with restitution 1 it would be back up near 0.5 by 0.64 s.
        let bouncing = try dropOntoFloor(frames: 40) { _ in }
        let sticking = try dropOntoFloor(frames: 40) { $0[CollisionFunctionModule.self] = CollisionFunctionModule(function: stick) }
        #expect(bouncing.allSatisfy { $0.position.y > 0.1 })
        #expect(sticking.allSatisfy { $0.position.y < 0.05 && $0.velocity.w > $0.position.w })
    }

    @Test func collisionFunctionCanKill() throws {
        let kill = ParticleFunction(source: """
        [[visible]] void kill(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            particle.age = particle.lifetime;
        }
        """, name: "kill")
        let particles = try dropOntoFloor(frames: 40) { $0[CollisionFunctionModule.self] = CollisionFunctionModule(function: kill) }
        #expect(particles.allSatisfy { $0.position.w >= $0.velocity.w })
    }

    @Test func deathFunctionCanRespawnAndRunsOncePerDeath() throws {
        // Moves the particle up by 10 at death. With parameters[0].x > 0 it also lives another second.
        let source = """
        [[visible]] void onDeath(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            particle.position.y += 10;
            particle.lifetime += parameters[0].x;
        }
        """
        let respawn = try dropOntoFloor(frames: 30) {
            $0.edit(LifetimeModule.self) { $0.range = 0.2...0.2 }
            $0[DeathFunctionModule.self] = DeathFunctionModule(function: ParticleFunction(source: source, name: "onDeath", parameters: [[1, 0, 0, 0]]))
        }
        #expect(respawn.allSatisfy { $0.position.y > 9 && $0.position.w < $0.velocity.w })
        // Without the extension the particle dies once; dead particles are not updated, so it moved up exactly once.
        let once = try dropOntoFloor(frames: 30) {
            $0.edit(LifetimeModule.self) { $0.range = 0.2...0.2 }
            $0[DeathFunctionModule.self] = DeathFunctionModule(function: ParticleFunction(source: source, name: "onDeath", parameters: [[0, 0, 0, 0]]))
        }
        #expect(once.allSatisfy { $0.position.y > 9 && $0.position.y < 11 && $0.position.w >= $0.velocity.w })
    }

    @Test func unsetParametersReadAsZero() throws {
        // The file gives one parameter; the code reads entry 7, which must be a padded zero, not memory past the buffer.
        let readsSeven = ParticleFunction(source: """
        [[visible]] void readsSeven(thread ParticleState &particle, float deltaTime, float time, constant float4 *parameters) {
            particle.velocity = parameters[7].xyz + float3(0, 1, 0);
        }
        """, name: "readsSeven", parameters: [[9, 9, 9, 9]])
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: fallingEmitter { $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: readsSeven) })
        let result = try velocities(system, count: 16, frames: 2)
        #expect(result[0].allSatisfy { simd_distance($0, [0, 1, 0]) < 1e-5 })
    }

    @Test func compileErrorsThrowFromSimulate() throws {
        let broken = ParticleFunction(source: "[[visible]] void broken(thread ParticleState &particle) { oops; }", name: "broken")
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 16, modules: fallingEmitter { $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: broken) })
        #expect(throws: (any Error).self) {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
    }

    func preset(_ function: ParticleFunction, inSubEmitter: Bool = false) -> ParticleSystem {
        var settings = fallingEmitter()
        if inSubEmitter {
            var childSettings = EmitterModules.standard
            childSettings[UpdateFunctionModule.self] = UpdateFunctionModule(function: function)
            settings[SubEmittersModule.self] = SubEmittersModule(emitters: [SubEmitter(occasion: .onDeath, countPerEvent: 1, modules: childSettings)])
        } else {
            settings[UpdateFunctionModule.self] = UpdateFunctionModule(function: function)
        }
        return ParticleSystem("Test", layers: [ParticleSystem.Layer("Layer", modules: settings, capacity: 16)])
    }

    func functionError(_ body: () throws -> Void) -> ParticleFunctionError? {
        do {
            try body()
            return nil
        } catch {
            return error as? ParticleFunctionError
        }
    }

    @Test func loadReportsCompileErrorsByName() throws {
        let broken = ParticleFunction(source: "[[visible]] void broken(thread ParticleState &particle) { oops; }", name: "broken")
        let system = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        let error = functionError { try system.load(preset(broken)) }
        #expect(error?.name == "broken")
        #expect(error?.localizedDescription.contains("oops") == true)
    }

    @Test func validationCoversSubEmitterFunctions() {
        let broken = ParticleFunction(source: "nonsense", name: "broken")
        #expect(functionError { try preset(broken, inSubEmitter: true).validateFunctions(device: runner.device) }?.name == "broken")
        #expect(functionError { try preset(setVelocity, inSubEmitter: true).validateFunctions(device: runner.device) } == nil)
    }

    @Test func effectFilesKeepFunctions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("function-effect-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ParticleSystem.strangeAttractor.write(to: url)
        let loaded = try ParticleSystem(contentsOf: url)
        #expect(loaded.layers[0].modules[UpdateFunctionModule.self] == ParticleSystem.strangeAttractor.layers[0].modules[UpdateFunctionModule.self])
        let system = try ParticleSystemRuntime(device: runner.device, modules: [], capacity: 1)
        try system.load(loaded)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
    }

    @Test func updateFunctionRoundTripsThroughJSON() throws {
        let emitter = fallingEmitter { $0[UpdateFunctionModule.self] = UpdateFunctionModule(function: setVelocity) }
        let decoded = try roundTrip(emitter)
        #expect(decoded[UpdateFunctionModule.self]?.function == setVelocity)
        var spawning = fallingEmitter()
        spawning[SpawnFunctionModule.self] = SpawnFunctionModule(function: ring)
        spawning[CollisionFunctionModule.self] = CollisionFunctionModule(function: setVelocity)
        spawning[DeathFunctionModule.self] = DeathFunctionModule(function: ring)
        let events = try roundTrip(spawning)
        #expect(events[SpawnFunctionModule.self]?.function == ring && events[CollisionFunctionModule.self]?.function == setVelocity && events[DeathFunctionModule.self]?.function == ring)
        let plain = try roundTrip(fallingEmitter())
        #expect(plain[UpdateFunctionModule.self] == nil)
    }
}
