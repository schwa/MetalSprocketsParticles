import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import simd
import Testing

struct ParticleKindTests {
    /// Setting each kind gives a value of that kind; setting the current kind changes nothing.
    func checkRoundTrip<Value: Equatable, Kind: ParticleKind>(_ start: Value, _ kind: WritableKeyPath<Value, Kind>) {
        for target in Kind.allCases {
            var value = start
            value[keyPath: kind] = target
            #expect(value[keyPath: kind] == target, "\(Value.self) → \(target.name)")
            let converted = value
            value[keyPath: kind] = target
            #expect(value == converted)
        }
        #expect(Set(Kind.allCases.map(\.name)).count == Kind.allCases.count, "\(Kind.self) names are unique")
    }

    @Test func everyKindRoundTrips() {
        checkRoundTrip(EmitterShape.sphere(radius: 2), \.kind)
        checkRoundTrip(ParticleOrientation.velocityAligned(stretch: 1), \.kind)
        checkRoundTrip(Collider.sphere(center: [1, 2, 3], radius: 1), \.kind)
        checkRoundTrip(ForceField.turbulence(strength: 1), \.kind)
        checkRoundTrip(SubEmitter.Occasion.whileAlive(interval: 0.2), \.kind)
        checkRoundTrip(TriggerVolume.box(center: [1, 0, 0], halfExtents: [1, 2, 3]), \.kind)
        checkRoundTrip(EmissionTrigger.Condition.colliderHit(index: 2, count: 5), \.kind)
        checkRoundTrip(EmissionTrigger.Action.burst(7), \.kind)
    }

    @Test func conversionsKeepWhatCarriesOver() {
        var shape = EmitterShape.sphere(radius: 2)
        shape.kind = .torus
        #expect(shape == .torus(radius: 2, tubeRadius: 0.4))
        var collider = Collider.sphere(center: [1, 2, 3], radius: 1)
        collider.kind = .box
        #expect(collider == .box(center: [1, 2, 3], halfExtents: [0.4, 0.4, 0.4]))
        var volume = TriggerVolume.sphere(center: [0, 1, 0], radius: 0.5)
        volume.kind = .box
        #expect(volume == .box(center: [0, 1, 0], halfExtents: [0.5, 0.5, 0.5]))
        volume.kind = .sphere
        #expect(volume == .sphere(center: [0, 1, 0], radius: 0.5))
    }

    @Test func optionEnumsListEveryCaseWithANameOnce() {
        func check<Kind: ParticleKind>(_: Kind.Type) {
            #expect(!Kind.allCases.isEmpty)
            #expect(Set(Kind.allCases).count == Kind.allCases.count)
            #expect(Set(Kind.allCases.map(\.name)).count == Kind.allCases.count)
        }
        check(ParticleBlendMode.self)
        check(ParticleBirthLocation.self)
        check(ParticleBirthDirection.self)
        check(ParticleImageSequenceMode.self)
        check(SimulationSpace.self)
        check(ParticleSortMode.self)
        check(EmitterMotion.Kind.self)
        check(ParticleSprite.self)
    }
}
