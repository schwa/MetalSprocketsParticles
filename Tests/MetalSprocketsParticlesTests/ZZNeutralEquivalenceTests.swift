@testable import MetalSprocketsParticles
import Testing

/// Temporary (#229): module-native defaults equal the flat ones they replace.
struct ZZNeutralEquivalenceTests {
    @Test func defaultsMatchFlat() {
        #expect(EmitterModules.standard == EmitterModules(ParticleEmitter()))
        #expect(EmitterModules.default2D == EmitterModules(ParticleEmitter.default2D))
        let neutral = ParticleEmitter.neutral
        var shape = ParticleEmitter.neutral
        NeutralModules.shape.apply(to: &shape)
        #expect(shape == neutral)
        #expect(NeutralModules.rate == RateModule(lifting: neutral))
        #expect(NeutralModules.lifetime.range == neutral.lifetime)
        #expect(NeutralModules.collision == CollisionModule(lifting: neutral))
        var sprite = neutral
        NeutralModules.sprite.apply(to: &sprite)
        #expect(sprite == neutral)
        #expect(NeutralModules.colorOverLife.color == neutral.colorOverLife && NeutralModules.colorOverLife.opacity == neutral.opacityOverLife)
        #expect(NeutralModules.colorOverLife.alternate == neutral.alternateColorOverLife)
        #expect(NeutralModules.sizeOverLife.curve == neutral.sizeOverLife)
        #expect(NeutralModules.colorBySpeed.range == neutral.colorBySpeedRange)
        #expect(NeutralModules.colorByPosition.start == neutral.colorByPositionStart && NeutralModules.colorByPosition.end == neutral.colorByPositionEnd)
        #expect(neutral.inheritVelocity == 0 && neutral.velocity == .zero && neutral.gravity == .zero && neutral.drag == 0)
    }
}
