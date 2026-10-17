import MetalSprockets
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import simd
import SwiftUI
import Testing

struct ColorPipelineTests {
    /// Golden images and particles-render use OffscreenRenderer. If the app renders to a different format, tests
    /// check different colors than users see (#15).
    @Test func appRendersToSameFormatAsOffscreenRenderer() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 4, height: 4))
        #expect(ParticlesView.colorPixelFormat == renderer.colorTexture.pixelFormat)
    }
}

struct InspectorAdapterTests {
    @Test func lifetimeBoundsStayOrdered() {
        var emitter = ParticleEmitter()
        emitter.lifetime = 1...2
        emitter.lifetimeMinimum = 3
        #expect(emitter.lifetime == 3...3)
        emitter.lifetimeMaximum = 0.5
        #expect(emitter.lifetime == 0.5...0.5)
    }

    @Test func limitedEmissionToggle() {
        var emitter = ParticleEmitter()
        #expect(!emitter.hasLimitedEmission)
        emitter.hasLimitedEmission = true
        #expect(emitter.emissionDuration == 1)
        emitter.limitedEmissionDuration = 4
        emitter.hasLimitedEmission = true
        #expect(emitter.emissionDuration == 4)
        emitter.hasLimitedEmission = false
        #expect(emitter.emissionDuration == nil)
    }

    @Test func forceFieldStrengthAddsUpdatesAndRemoves() {
        var fields: [ForceField] = []
        fields.turbulenceStrength = 3
        fields.vortexStrength = -2
        #expect(fields.count == 2)
        #expect(fields.turbulenceStrength == 3)
        #expect(fields.vortexStrength == -2)
        fields.turbulenceStrength = 5
        #expect(fields.count == 2)
        #expect(fields.turbulenceStrength == 5)
        fields.turbulenceStrength = 0
        #expect(fields.count == 1)
        #expect(fields.turbulenceStrength == 0)
    }

    @Test func orientationKindKeepsStretch() {
        var emitter = ParticleEmitter()
        emitter.velocityStretch = 0.7
        #expect(emitter.orientationKind == .velocityAligned)
        emitter.orientationKind = .yAligned
        #expect(emitter.orientation == .yAligned)
        #expect(emitter.velocityStretch == 0)
        emitter.orientationKind = .velocityAligned
        #expect(emitter.orientation == .velocityAligned(stretch: 0))
    }

    @Test func colorRoundTripsThroughLinearSRGB() {
        var curve = ParticleCurve<SIMD4<Float>>.linear(from: [1, 0.7, 0.2, 1], to: [0.8, 0.1, 0.05, 0])
        let start = curve.start
        curve.startColor = curve.startColor
        #expect(abs(curve.start - start).max() < 1e-4)
        curve.endColor = Color(.sRGBLinear, red: 0, green: 0.5, blue: 1, opacity: 0.25)
        #expect(abs(curve.end - SIMD4<Float>(0, 0.5, 1, 0.25)).max() < 1e-4)
    }

    @MainActor
    @Test func modelPushesChangesToSystem() throws {
        let model = ParticlesDemoModel(capacity: 16)
        let system = try #require(model.system)
        model.emitter.birthRate = 123
        model.speedFactor = 2
        model.isEmitting = false
        model.playback = .paused
        #expect(system.emitter.birthRate == 123)
        #expect(system.speedFactor == 2)
        #expect(!system.isEmitting)
        #expect(system.state == .paused)
        model.restart()
        #expect(system.state == .playing)
        #expect(model.playback == .playing)
    }
}
