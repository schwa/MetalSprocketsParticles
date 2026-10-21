import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import Testing

/// `bornParticleCount` and `diedParticleCount`, counted on the GPU and read a few frames late (#135).
@Suite(.serialized, .requiresMetal4)
struct BirthDeathCountTests {
    func emitter(_ configure: (inout EmitterModules) -> Void) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        configure(&emitter)
        return emitter
    }

    @Test func steadyEmissionBalancesBirthsAndDeaths() throws {
        let runner = try Runner()
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1_000, modules: emitter {
            $0.edit(RateModule.self) { $0.birthRate = 600 }
            $0.edit(LifetimeModule.self) { $0.range = 0.5...0.5 }
        })
        var born: [Int] = []
        var died: [Int] = []
        for _ in 0..<120 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
            born.append(system.bornParticleCount)
            died.append(system.diedParticleCount)
        }
        // 600 a second at 60 steps a second: 10 births a step, and as many deaths once lives run out.
        let lateBorn = born.suffix(30).reduce(0, +)
        let lateDied = died.suffix(30).reduce(0, +)
        #expect(abs(lateBorn - 300) <= 2)
        #expect(abs(lateDied - 300) <= 12)
        // The per-second rates average the last frames.
        #expect(abs(system.birthsPerSecond - 600) < 10)
        #expect(abs(system.deathsPerSecond - 600) < 30)
    }

    @Test func subEmitterChildrenCountAsBirths() throws {
        let runner = try Runner()
        let child = emitter {
            $0.edit(RateModule.self) { $0.birthRate = 0 }
            $0.edit(LifetimeModule.self) { $0.range = 0.05...0.05 }
        }
        let parent = emitter {
            $0.edit(RateModule.self) { $0.birthRate = 0 }
            $0.edit(LifetimeModule.self) { $0.range = 0.05...0.05 }
            $0[SubEmittersModule.self] = SubEmittersModule(emitters: [SubEmitter(occasion: .onDeath, countPerEvent: 3, modules: child)])
        }
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 4, modules: parent)
        system.burst(4)
        var born = 0
        var died = 0
        for _ in 0..<30 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
            born += system.bornParticleCount
            died += system.diedParticleCount
        }
        // 4 parents, then 3 children each when they die; all 16 die.
        #expect(born == 16)
        #expect(died == 16)
    }
}
