import Metal
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

/// `ParticleEmitter.emissionOverTime` shapes births over time and lets effects finish.
@Suite(.requiresMetal4)
struct EmissionEnvelopeTests {
    let device = MTLCreateSystemDefaultDevice()!
    let deltaTime: Float = 1.0 / 60.0
    /// Full for 10 seconds, then down to nothing by 12.
    let runAndFade = ParticleCurve<Float>([.init(0, 1), .init(10, 1), .init(12, 0)])

    func emitter(_ configure: (inout ParticleEmitter) -> Void) -> ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.birthRate = 100
        emitter.lifetime = 1...1
        configure(&emitter)
        return emitter
    }

    /// Births per frame over `seconds`.
    func births(_ system: ParticleSystemRuntime, seconds: Float) throws -> [Int] {
        try (0..<Int((seconds / deltaTime).rounded())).map { _ in
            try system.planFrame(deltaTime: deltaTime).dispatches
                .filter { $0.uniforms.spawn.sliceStart == 0 }
                .reduce(0) { $0 + Int($1.uniforms.spawn.count) }
        }
    }

    @Test func integralIsExactForStraightSegments() {
        #expect(abs(runAndFade.integral(from: 0, to: 12) - 11) < 1e-4)
        #expect(abs(runAndFade.integral(from: 11, to: 12) - 0.25) < 1e-5)
        #expect(runAndFade.integral(from: 12, to: 20) == 0)
        #expect(ParticleCurve<Float>.constant(2).integral(from: 1, to: 4) == 6)
    }

    @Test func runAndFadeEmitsTheAreaUnderTheCurveThenStops() throws {
        let system = try ParticleSystemRuntime(device: device, capacity: 2_000, emitter: emitter { $0.emissionOverTime = runAndFade })
        let counts = try births(system, seconds: 14)
        let afterEnd = counts.dropFirst(Int(12.05 / deltaTime))
        #expect(abs(counts.reduce(0, +) - 1_100) <= 1)
        #expect(afterEnd.allSatisfy { $0 == 0 })
        // The fade from 10 to 12 s has area 1, so it emits one second's worth: about 100.
        let fade = counts[Int(10 / deltaTime)..<Int(12 / deltaTime)].reduce(0, +)
        #expect(abs(fade - 100) <= 2)
    }

    @Test func fadeInRampsUp() throws {
        let system = try ParticleSystemRuntime(device: device, capacity: 2_000, emitter: emitter {
            $0.emissionOverTime = ParticleCurve([.init(0, 0), .init(1, 1)])
        })
        let counts = try births(system, seconds: 2)
        #expect(abs(counts.prefix(60).reduce(0, +) - 50) <= 1)
        #expect(abs(counts.suffix(60).reduce(0, +) - 100) <= 1)
    }

    @Test func finishesAfterTheEnvelopeEndsAndParticlesDie() throws {
        let system = try ParticleSystemRuntime(device: device, capacity: 2_000, emitter: emitter {
            $0.emissionOverTime = ParticleCurve([.init(0, 1), .init(2, 0)])
        })
        _ = try births(system, seconds: 2.5)
        // Emission ended near 2 s, but particles born then live 1 s.
        #expect(!system.isFinished)
        _ = try births(system, seconds: 1)
        #expect(system.emitters[0].isFinished)
        #expect(system.isFinished)
    }

    @Test func confettiPresetFinishes() throws {
        let system = try ParticleSystemRuntime(device: device, emitters: [], capacity: 1)
        try system.load(.confetti)
        _ = try births(system, seconds: 2)
        #expect(!system.isFinished)
        _ = try births(system, seconds: 8)
        #expect(system.isFinished)
    }

    @Test func infiniteEmittersAndTriggeredEmittersNeverFinish() throws {
        let infinite = try ParticleSystemRuntime(device: device, capacity: 500, emitter: emitter { _ in })
        _ = try births(infinite, seconds: 3)
        #expect(!infinite.isFinished)
        let triggered = try ParticleSystemRuntime(device: device, capacity: 500, emitter: emitter {
            $0.birthRate = 0
            $0.triggers = [EmissionTrigger(.event("go"), .burst(5))]
        })
        _ = try births(triggered, seconds: 3)
        #expect(!triggered.isFinished)
    }

    @Test func burstOnlyEmitterFinishesWhenItsParticlesDie() throws {
        let system = try ParticleSystemRuntime(device: device, capacity: 50, emitter: emitter { $0.birthRate = 0 })
        system.burst(10)
        _ = try births(system, seconds: 0.5)
        #expect(!system.isFinished)
        _ = try births(system, seconds: 1)
        #expect(system.isFinished)
    }
}
