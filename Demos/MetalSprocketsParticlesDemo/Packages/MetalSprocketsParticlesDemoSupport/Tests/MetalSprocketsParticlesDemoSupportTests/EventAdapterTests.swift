@testable import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import simd
import Testing

// Switching kinds is tested in the library (ParticleKindTests); these cover the demo's per-field adapters.

struct SubEmitterAdapterTests {
    @Test func trailInterval() {
        var sub = SubEmitter.sparks
        sub.trailInterval = 0.2
        #expect(sub.occasion == .whileAlive(interval: 0.2))
        sub.occasion.kind = .collision
        #expect(sub.trailInterval == 0.05)
    }
}

struct TriggerAdapterTests {
    @Test func conditionKindSwitchesAndKeepsOtherFieldsSensible() {
        var trigger = EmissionTrigger(.event("boom"), .burst(10))
        trigger.eventName = "bang"
        #expect(trigger.condition == .event("bang"))
        trigger.condition.kind = .every
        trigger.seconds = 2
        #expect(trigger.condition == .every(seconds: 2))
        trigger.condition.kind = .particlesEnter
        trigger.threshold = 25
        trigger.volume.center = [1, 2, 3]
        trigger.volume.radius = 0.75
        #expect(trigger.condition == .particlesEnter(volume: .sphere(center: [1, 2, 3], radius: 0.75), count: 25))
        trigger.condition.kind = .colliderHit
        trigger.colliderIndex = 2
        #expect(trigger.condition == .colliderHit(index: 2, count: 1))
        // Fields that do not apply are ignored.
        trigger.seconds = 9
        #expect(trigger.condition == .colliderHit(index: 2, count: 1))
    }

    @Test func burstCount() {
        var trigger = EmissionTrigger(.event("x"), .stop)
        #expect(trigger.burstCount == 100)
        trigger.burstCount = 42
        #expect(trigger.action == .burst(42))
    }

    @MainActor
    @Test func sendEventReachesTheSystem() throws {
        let model = ParticlesDemoModel()
        let system = try #require(model.system)
        model.selectedEmitter.settings.birthRate = 0
        model.selectedEmitter.settings.triggers = [EmissionTrigger(.event("pop"), .burst(5))]
        model.eventToSend = "pop"
        model.sendEvent()
        #expect(system.pendingEvents == ["pop"])
    }
}
