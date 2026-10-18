import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import Testing

/// Effect files come from users and other tools; bad values must fail cleanly or be fixed up, not crash.
@Suite(.serialized)
struct HostileInputTests {
    @Test func emptyCurvesInAFileDoNotCrash() throws {
        var emitter = ParticleEmitter()
        emitter.birthRate = 100
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(emitter)) as? [String: Any])
        for key in ["colorOverLife", "sizeOverLife", "opacityOverLife", "emissionOverTime"] {
            object[key] = ["keyframes": [Any]()]
        }
        let decoded: ParticleEmitter
        do {
            decoded = try JSONDecoder().decode(ParticleEmitter.self, from: JSONSerialization.data(withJSONObject: object))
        } catch {
            return // Rejecting the file is fine too.
        }
        let runner = try Runner()
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 64, emitter: decoded)
        try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
    }

    @Test func hugeNestedSubEmitterCountsThrowInsteadOfCrashing() throws {
        var child = ParticleEmitter()
        var sub = SubEmitter(occasion: .onDeath, countPerEvent: 1_000_000, settings: child)
        for _ in 0..<2 {
            child.subEmitters = [sub]
            sub = SubEmitter(occasion: .onDeath, countPerEvent: 1_000_000, settings: child)
        }
        var parent = ParticleEmitter()
        parent.subEmitters = [sub]
        #expect(throws: (any Error).self) {
            _ = try ParticleSystemRuntime(capacity: 1_000_000, emitter: parent)
        }
    }
}
