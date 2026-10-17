@testable import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import simd
import Testing

struct SubEmitterAdapterTests {
    @Test func occasionKindRoundTrips() {
        var sub = SubEmitter.sparks
        sub.occasionKind = .whileAlive
        #expect(sub.occasion == .whileAlive(interval: 0.05))
        sub.trailInterval = 0.2
        #expect(sub.occasion == .whileAlive(interval: 0.2))
        sub.occasionKind = .onCollision
        #expect(sub.occasion == .onCollision)
        #expect(sub.trailInterval == 0.05)
    }
}

struct TriggerAdapterTests {
    @Test func conditionKindSwitchesAndKeepsOtherFieldsSensible() {
        var trigger = EmissionTrigger(.event("boom"), .burst(10))
        trigger.eventName = "bang"
        #expect(trigger.condition == .event("bang"))
        trigger.conditionKind = .every
        trigger.seconds = 2
        #expect(trigger.condition == .every(seconds: 2))
        trigger.conditionKind = .particlesEnter
        trigger.threshold = 25
        trigger.volume.center = [1, 2, 3]
        trigger.volume.radius = 0.75
        #expect(trigger.condition == .particlesEnter(volume: .sphere(center: [1, 2, 3], radius: 0.75), count: 25))
        trigger.conditionKind = .colliderHit
        trigger.colliderIndex = 2
        #expect(trigger.condition == .colliderHit(index: 2, count: 1))
        // Fields that do not apply are ignored.
        trigger.seconds = 9
        #expect(trigger.condition == .colliderHit(index: 2, count: 1))
    }

    @Test func actionKindKeepsBurstCount() {
        var trigger = EmissionTrigger(.event("x"), .burst(300))
        trigger.actionKind = .stop
        #expect(trigger.action == .stop)
        trigger.actionKind = .burst
        #expect(trigger.action == .burst(100))
        trigger.burstCount = 42
        #expect(trigger.action == .burst(42))
    }

    @Test func volumeBoxToggle() {
        var volume = TriggerVolume.sphere(center: [0, 1, 0], radius: 0.5)
        volume.isBox = true
        #expect(volume == .box(center: [0, 1, 0], halfExtents: [0.5, 0.5, 0.5]))
        volume.isBox = false
        #expect(volume == .sphere(center: [0, 1, 0], radius: 0.5))
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
