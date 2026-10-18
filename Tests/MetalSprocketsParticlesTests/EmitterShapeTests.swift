import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized)
struct EmitterShapeTests {
    let runner: Runner
    let epsilon: Float = 1e-4

    init() throws {
        runner = try Runner()
    }

    /// Birth positions (and velocities) of `count` particles spawned in one zero-length step.
    func spawn(
        _ shape: EmitterShape,
        location: ParticleBirthLocation = .volume,
        direction: ParticleBirthDirection = .velocity,
        speed: Float = 0,
        sweep: Float = 2 * .pi,
        count: Int = 1_024,
        mesh: EmitterMesh? = nil
    ) throws -> [(position: SIMD3<Float>, velocity: SIMD3<Float>)] {
        var emitter = ParticleEmitter()
        emitter.shape = shape
        emitter.birthLocation = location
        emitter.birthDirection = direction
        emitter.sweepAngle = sweep
        emitter.velocity = [0, speed, 0]
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystemRuntime(device: runner.device, capacity: count, emitter: emitter, seed: 5)
        system.emitters[0].mesh = mesh
        system.burst(count)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: count)
        return UnsafeBufferPointer(start: pointer, count: count).map {
            (SIMD3($0.position.x, $0.position.y, $0.position.z), SIMD3($0.velocity.x, $0.velocity.y, $0.velocity.z))
        }
    }

    func positions(_ shape: EmitterShape, location: ParticleBirthLocation = .volume, sweep: Float = 2 * .pi, mesh: EmitterMesh? = nil) throws -> [SIMD3<Float>] {
        try spawn(shape, location: location, sweep: sweep, mesh: mesh).map(\.position)
    }

    func radial(_ point: SIMD3<Float>) -> Float {
        simd_length(SIMD2(point.x, point.z))
    }

    @Test func point() throws {
        #expect(try positions(.point).allSatisfy { $0 == .zero })
    }

    @Test func sphereVolumeAndSurface() throws {
        let volume = try positions(.sphere(radius: 2))
        #expect(volume.allSatisfy { simd_length($0) <= 2 + epsilon })
        #expect(volume.contains { simd_length($0) < 1 })
        let surface = try positions(.sphere(radius: 2), location: .surface)
        #expect(surface.allSatisfy { abs(simd_length($0) - 2) < epsilon })
    }

    @Test func sweepLimitsAzimuth() throws {
        let points = try positions(.sphere(radius: 1), location: .surface, sweep: .pi / 2)
        #expect(points.allSatisfy { $0.x >= -epsilon && $0.z >= -epsilon })
    }

    @Test func boxVolumeAndSurface() throws {
        let half: SIMD3<Float> = [1, 0.5, 0.25]
        let volume = try positions(.box(size: half * 2))
        #expect(volume.allSatisfy { all(abs($0) .<= half + epsilon) })
        let surface = try positions(.box(size: half * 2), location: .surface)
        #expect(surface.allSatisfy { (abs($0) / half).max() > 1 - epsilon })
    }

    @Test func planeIsFlat() throws {
        let points = try positions(.plane(size: [2, 4]))
        #expect(points.allSatisfy { abs($0.y) < epsilon && abs($0.x) <= 1 + epsilon && abs($0.z) <= 2 + epsilon })
    }

    @Test func discFillAndRim() throws {
        let fill = try positions(.disc(radius: 1.5))
        #expect(fill.allSatisfy { abs($0.y) < epsilon && radial($0) <= 1.5 + epsilon })
        let rim = try positions(.disc(radius: 1.5), location: .surface)
        #expect(rim.allSatisfy { abs(radial($0) - 1.5) < epsilon })
    }

    @Test func cylinderSideAndVolume() throws {
        let side = try positions(.cylinder(radius: 1, height: 2), location: .surface)
        #expect(side.allSatisfy { abs(radial($0) - 1) < epsilon && abs($0.y) <= 1 + epsilon })
        let volume = try positions(.cylinder(radius: 1, height: 2))
        #expect(volume.allSatisfy { radial($0) <= 1 + epsilon && abs($0.y) <= 1 + epsilon })
    }

    @Test func coneTapersToApex() throws {
        let volume = try positions(.cone(radius: 1, height: 2))
        #expect(volume.allSatisfy { $0.y >= -epsilon && $0.y <= 2 + epsilon && radial($0) <= 1 - $0.y / 2 + epsilon })
        let surface = try positions(.cone(radius: 1, height: 2), location: .surface)
        #expect(surface.allSatisfy { abs(radial($0) - (1 - $0.y / 2)) < epsilon })
    }

    @Test func torusSurfaceIsTubeRadiusFromRing() throws {
        let points = try positions(.torus(radius: 1.5, tubeRadius: 0.25), location: .surface)
        for point in points {
            let tubeOffset = SIMD2(radial(point) - 1.5, point.y)
            #expect(abs(simd_length(tubeOffset) - 0.25) < epsilon)
        }
    }

    @Test func normalDirectionPointsOutward() throws {
        let particles = try spawn(.sphere(radius: 1), location: .surface, direction: .normal, speed: 2)
        for particle in particles {
            #expect(simd_distance(particle.velocity, simd_normalize(particle.position) * 2) < 1e-3)
        }
    }

    func twoTriangleMesh() throws -> EmitterMesh {
        // A small triangle (area 0.5) and a big one (area 1.5), both flat at y = 0 and apart in x.
        try EmitterMesh(
            device: runner.device,
            positions: [[0, 0, 0], [1, 0, 0], [0, 0, 1], [10, 0, 0], [13, 0, 0], [10, 0, 1]],
            indices: [0, 1, 2, 3, 4, 5]
        )
    }

    @Test func meshSurfaceIsAreaWeighted() throws {
        let points = try positions(.mesh, location: .surface, mesh: twoTriangleMesh())
        #expect(points.allSatisfy { abs($0.y) < epsilon })
        let big = Float(points.filter { $0.x >= 10 - epsilon }.count) / Float(points.count)
        // Expected 0.75 by area.
        #expect(abs(big - 0.75) < 0.05)
    }

    @Test func meshVerticesAreExact() throws {
        let points = try positions(.mesh, location: .vertices, mesh: twoTriangleMesh())
        let vertices: Set<SIMD3<Float>> = [[0, 0, 0], [1, 0, 0], [0, 0, 1], [10, 0, 0], [13, 0, 0], [10, 0, 1]]
        #expect(points.allSatisfy { vertices.contains($0) })
        #expect(Set(points).count == 6)
    }

    @Test func meshVolumeFallsBackToSurface() throws {
        let points = try positions(.mesh, location: .volume, mesh: twoTriangleMesh())
        #expect(points.allSatisfy { abs($0.y) < epsilon })
    }

    @Test func meshShapeWithoutMeshEmitsAtCenter() throws {
        #expect(try positions(.mesh).allSatisfy { $0 == .zero })
    }

    @Test func radiusAccessorMapsToSphere() {
        var emitter = ParticleEmitter()
        emitter.radius = 0.3
        #expect(emitter.shape == .sphere(radius: 0.3))
        emitter.shape = .box(size: [1, 1, 1])
        #expect(emitter.radius == 0)
    }
}
