import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Positioned bursts and view-geometry colliders, for 2D overlays.
@Suite(.serialized, .requiresMetal4)
struct OverlayTests {
    let runner: Runner
    let deltaTime: Float = 1.0 / 60.0

    init() throws {
        runner = try Runner()
    }

    func still(_ configure: (inout EmitterModules) -> Void = { _ in }) -> EmitterModules {
        var emitter = EmitterModules.standard
        emitter.edit(ShapeModule.self) { $0.shape = .point }
        emitter.edit(VelocityModule.self) { $0.velocity = .zero }
        emitter.edit(VelocityModule.self) { $0.spread = 0 }
        emitter.edit(GravityModule.self) { $0.acceleration = .zero }
        emitter.edit(LifetimeModule.self) { $0.range = 10...10 }
        emitter.edit(RateModule.self) { $0.birthRate = 0 }
        configure(&emitter)
        return emitter
    }

    func live(_ runtime: ParticleSystemRuntime) -> [Particle] {
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: runtime.capacity)
        return (0..<runtime.capacity).map { pointer[$0] }.filter { $0.velocity.w > 0 && $0.position.w < $0.velocity.w }
    }

    /// The 2D overlay demo's confetti (OverlayEffects in the demo), burst above a button: it spreads across the window.
    /// In points, spread and speed variation must be hundreds of points a second; with 0.7 and 0.4 (meant for meters)
    /// every particle moved as one and the burst stayed a blob (#140).
    @Test func overlayConfettiSpreads() throws {
        var confetti = EmitterModules.standard
        confetti.edit(ShapeModule.self) { $0.shape = .point }
        confetti.edit(RateModule.self) { $0.birthRate = 0 }
        confetti.edit(VelocityModule.self) { $0.velocity = [0, -900, 0] }
        confetti.edit(VelocityModule.self) { $0.spread = 600 }
        confetti.edit(VelocityModule.self) { $0.speedVariation = 300 }
        confetti.edit(GravityModule.self) { $0.acceleration = [0, 1_400, 0] }
        confetti.edit(DragModule.self) { $0.amount = 1.2 }
        confetti.edit(LifetimeModule.self) { $0.range = 3...4 }
        confetti.edit(SizeOverLifeModule.self) { $0.curve = .constant(7) }
        confetti.edit(CollisionModule.self) { $0.restitution = 0.3 }
        confetti.edit(CollisionModule.self) { $0.friction = 0.6 }
        confetti[PlaneConstraintModule.self] = PlaneConstraintModule()
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 300, modules: confetti)
        let button = CGRect(x: 230, y: 420, width: 140, height: 50)
        runtime.burst(300, at: [Float(button.midX), Float(button.minY) - 8, 0])
        let colliders = Collider.edges(of: CGSize(width: 600, height: 540)) + [.box(frame: button)]
        for _ in 0..<20 {
            try runner.run(try runtime.simulate(deltaTime: deltaTime, colliders: colliders))
        }
        let positions = live(runtime).map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        #expect((xs.max() ?? 0) - (xs.min() ?? 0) > 100)
        #expect((ys.min() ?? .infinity) < Float(button.minY) - 100)
    }

    @Test func burstsSpawnAtTheirPointsWithoutMovingTheEmitter() throws {
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 32, modules: still { $0.edit(ShapeModule.self) { $0.position = [5, 5, 0] } })
        runtime.burst(3, at: [100, 50, 0])
        runtime.burst(2, at: [-20, 10, 0])
        runtime.burst(4)
        try runner.run(try runtime.simulate(deltaTime: deltaTime))
        let positions = live(runtime).map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
        #expect(positions.count == 9)
        // The emitter's origin moves to each point; the shape keeps its (5, 5) offset from the origin.
        #expect(positions.filter { simd_distance($0, [105, 55, 0]) < 1e-3 }.count == 3)
        #expect(positions.filter { simd_distance($0, [-15, 15, 0]) < 1e-3 }.count == 2)
        // The plain burst still comes from the emitter, which has not moved.
        #expect(positions.filter { simd_distance($0, [5, 5, 0]) < 1e-3 }.count == 4)
        #expect(runtime.emitters[0].transform == matrix_identity_float4x4)
    }

    @Test func burstsSurviveTransformsPassedEachFrame() throws {
        // ParticleView passes emitter transforms every frame; a positioned burst must not be overwritten by them.
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 8, modules: still())
        runtime.burst(2, at: [30, 40, 0])
        try runner.run(try runtime.simulate(deltaTime: deltaTime, transforms: [matrix_identity_float4x4]))
        #expect(live(runtime).allSatisfy { simd_distance(SIMD3($0.position.x, $0.position.y, $0.position.z), [30, 40, 0]) < 1e-3 })
        #expect(live(runtime).count == 2)
    }

    @Test func pausedBurstsWaitAndKeepTheEmitterUnfinished() throws {
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 8, modules: still())
        runtime.state = .paused
        runtime.burst(2, at: [1, 2, 0])
        try runner.run(try runtime.simulate(deltaTime: deltaTime))
        #expect(live(runtime).isEmpty)
        #expect(!runtime.emitters[0].isFinished)
        runtime.state = .playing
        try runner.run(try runtime.simulate(deltaTime: deltaTime))
        #expect(live(runtime).count == 2)
    }

    @Test func edgesKeepParticlesInsideTheView() throws {
        // Fast particles flying out in every direction from the middle of a 200 × 100 view.
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 64, modules: still {
            $0.edit(VelocityModule.self) { $0.velocity = [0, -400, 0] }
            $0.edit(VelocityModule.self) { $0.spread = .pi }
            $0.edit(CollisionModule.self) { $0.restitution = 0.5 }
            $0[PlaneConstraintModule.self] = PlaneConstraintModule()
        })
        runtime.colliders = Collider.edges(of: CGSize(width: 200, height: 100))
        runtime.burst(64, at: [100, 50, 0])
        for _ in 0..<60 {
            try runner.run(try runtime.simulate(deltaTime: deltaTime))
        }
        #expect(live(runtime).allSatisfy { (0...200).contains($0.position.x) && (0...100).contains($0.position.y) })
    }

    @Test func frameBoxCoversTheFrame() {
        let box = Collider.box(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
        #expect(box == .box(center: [60, 40, 0], halfExtents: [50, 20, 50]))
        #expect(Collider.floor(of: CGSize(width: 300, height: 200)) == .plane(normal: [0, -1, 0], distance: -200))
    }
}
