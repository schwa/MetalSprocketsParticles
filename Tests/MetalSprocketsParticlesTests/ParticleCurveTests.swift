import CoreGraphics
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

@Suite(.requiresMetal4)
struct ParticleCurveTests {
    @Test func linearInterpolatesBetweenKeyframes() {
        let curve = ParticleCurve<Float>([.init(0, 0), .init(0.5, 10), .init(1, 0)])
        #expect(curve.value(at: 0.25) == 5)
        #expect(curve.value(at: 0.5) == 10)
        #expect(curve.value(at: 0.75) == 5)
    }

    @Test func clampsOutsideKeyframes() {
        let curve = ParticleCurve<Float>([.init(0.2, 1), .init(0.8, 3)])
        #expect(curve.value(at: 0) == 1)
        #expect(curve.value(at: 1) == 3)
    }

    @Test func keyframesAreSorted() {
        let curve = ParticleCurve<Float>([.init(1, 3), .init(0, 1)])
        #expect(curve.keyframes.map(\.time) == [0, 1])
        #expect(curve.value(at: 0.5) == 2)
    }

    @Test func powerEasesLate() {
        let curve = ParticleCurve<Float>.power(from: 0, to: 1, exponent: 2)
        #expect(abs(curve.value(at: 0.5) - 0.25) < 0.01)
    }

    @Test func startAndEndEditFirstAndLastKeyframes() {
        var curve = ParticleCurve<Float>([.init(0, 0), .init(0.5, 5), .init(1, 0)])
        curve.start = 1
        curve.end = 2
        #expect(curve.keyframes.map(\.value) == [1, 5, 2])
        var constant = ParticleCurve<Float>.constant(4)
        constant.end = 8
        #expect(constant.value(at: 0) == 4)
        #expect(constant.value(at: 1) == 8)
    }

    @Test func editedKeyframesSampleInTimeOrder() {
        var curve = ParticleCurve<Float>([.init(0, 0), .init(1, 10)])
        // Move the first stop past the second without re-sorting.
        curve.keyframes[0].time = 2
        #expect(curve.value(at: 1) == 10)
        #expect(curve.value(at: 1.5) == 5)
        #expect(curve.start == 10)
        #expect(curve.end == 0)
    }

    @Test func removingTheLastKeyframeIsIgnored() {
        var curve = ParticleCurve<Float>.constant(3)
        curve.keyframes.removeAll()
        #expect(curve.keyframes.count == 1)
        #expect(curve.value(at: 0.5) == 3)
    }

    @Test func emitterStartEndAccessorsMatchCurves() {
        // Flat settings only; goes with ParticleEmitter in #229.
        var emitter = ParticleEmitter()
        emitter.colorStart = [1, 0, 0, 1]
        emitter.sizeEnd = 0.5
        #expect(emitter.colorOverLife.value(at: 0) == [1, 0, 0, 1])
        #expect(emitter.sizeOverLife.value(at: 1) == 0.5)
    }
}

@Suite(.serialized, .requiresMetal4)
struct ParticleCurveGPUTests {
    /// One still, procedurally drawn particle at the origin, 1 s lifetime, viewed head-on after `steps` frames.
    func centerPixel(steps: Int, configure: (inout EmitterModules) -> Void) throws -> SIMD4<UInt8> {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .sphere(radius: 0) }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 1...1 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        emitter.edit(SizeOverLifeModule.self) { $0.curve = .constant(0.5) }
        configure(&emitter)
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, modules: emitter, seed: 0)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 3], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<steps {
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0)
                try RenderPass { try system.render(projection: projection, view: view) }
            })
        }
        return try #require(rendering).cgImage.centerPixel()
    }

    let redGreenBlue = ParticleCurve<SIMD4<Float>>([.init(0, [1, 0, 0, 1]), .init(0.5, [0, 1, 0, 1]), .init(1, [0, 0, 1, 1])])

    @Test func colorFollowsMultiStopGradient() throws {
        // 30 steps: age 0.483...0.5, near the green stop.
        let middle = try centerPixel(steps: 30) { $0.edit(ColorOverLifeModule.self) { $0.color = redGreenBlue } }
        #expect(middle.y > 230)
        #expect(middle.x < 60)
        #expect(middle.z < 10)
        // 55 steps: age 0.9...0.917, mostly blue.
        let late = try centerPixel(steps: 55) { $0.edit(ColorOverLifeModule.self) { $0.color = redGreenBlue } }
        #expect(late.z > late.y)
        #expect(late.x < 10)
    }

    @Test func opacityCurveFades() throws {
        // Fade in then out: invisible at birth and death, opaque in the middle.
        let fade = ParticleCurve<Float>([.init(0, 0), .init(0.5, 1), .init(1, 0)])
        let middle = try centerPixel(steps: 30) {
            $0.edit(ColorOverLifeModule.self) { $0.color = .constant([1, 1, 1, 1]) }
            $0.edit(ColorOverLifeModule.self) { $0.opacity = fade }
        }
        let early = try centerPixel(steps: 1) {
            $0.edit(ColorOverLifeModule.self) { $0.color = .constant([1, 1, 1, 1]) }
            $0.edit(ColorOverLifeModule.self) { $0.opacity = fade }
        }
        #expect(middle.x > 240)
        // After one step opacity is at most ~0.033 linear, which the sRGB target encodes as ~51.
        #expect(early.x < 60)
    }
}
