import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import Testing

/// Effect files come from users and other tools; bad values must fail cleanly or be fixed up, not crash.
@Suite(.serialized, .requiresMetal4)
struct HostileInputTests {
    @Test func emptyCurvesInAFileDoNotCrash() throws {
        let modules: EmitterModules
        do {
            let empty = Data(#"{ "keyframes": [] }"#.utf8)
            let floats = try JSONDecoder().decode(ParticleCurve<Float>.self, from: empty)
            let colors = try JSONDecoder().decode(ParticleCurve<SIMD4<Float>>.self, from: empty)
            modules = EmitterModules {
                RateModule(birthRate: 100, overTime: floats)
                ColorOverLifeModule(color: colors, opacity: floats)
                SizeOverLifeModule(curve: floats)
            }
        } catch {
            return // Rejecting the file is fine too.
        }
        let runner = try Runner()
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 64, modules: modules)
        try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
    }

    @Test func hugeNestedSubEmitterCountsThrowInsteadOfCrashing() throws {
        var child = EmitterModules.standard
        var sub = SubEmitter(occasion: .onDeath, countPerEvent: 1_000_000, modules: child)
        for _ in 0..<2 {
            child[SubEmittersModule.self] = SubEmittersModule(emitters: [sub])
            sub = SubEmitter(occasion: .onDeath, countPerEvent: 1_000_000, modules: child)
        }
        var parent = EmitterModules.standard
        parent[SubEmittersModule.self] = SubEmittersModule(emitters: [sub])
        #expect(throws: (any Error).self) {
            _ = try ParticleSystemRuntime(capacity: 1_000_000, modules: parent)
        }
    }
}
