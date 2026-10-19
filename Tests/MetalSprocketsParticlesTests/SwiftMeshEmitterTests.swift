import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing

@Suite(.serialized, .requiresMetal4)
struct SwiftMeshEmitterTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    func spawn(_ mesh: Mesh, location: ParticleBirthLocation) throws -> [SIMD3<Float>] {
        var emitter = ParticleEmitter()
        emitter.shape = .mesh
        emitter.birthLocation = location
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1_024, emitter: emitter, seed: 2)
        system.emitters[0].mesh = try EmitterMesh(device: runner.device, mesh: mesh)
        system.burst(1_024)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    /// One square face, which SwiftMesh stores as a single quad, not two triangles.
    let square = Mesh(positions: [[0, 0, 0], [2, 0, 0], [2, 0, 2], [0, 0, 2]], faces: [[0, 1, 2, 3]])

    @Test func polygonFacesAreTriangulated() throws {
        let mesh = try EmitterMesh(device: runner.device, mesh: square)
        #expect(mesh.triangleCount == 2)
        #expect(mesh.vertexCount == 4)
    }

    @Test func surfaceEmissionCoversTheWholeFace() throws {
        let points = try spawn(square, location: .surface)
        #expect(points.allSatisfy { abs($0.y) < 1e-5 && $0.x >= -1e-5 && $0.x <= 2 + 1e-5 && $0.z >= -1e-5 && $0.z <= 2 + 1e-5 })
        // Both triangles get used: points on both sides of the diagonal x = z.
        #expect(points.contains { $0.x > $0.z + 0.2 })
        #expect(points.contains { $0.z > $0.x + 0.2 })
    }

    @Test func vertexEmissionUsesMeshVertices() throws {
        let points = Set(try spawn(square, location: .vertices))
        #expect(points == [[0, 0, 0], [2, 0, 0], [2, 0, 2], [0, 0, 2]])
    }

    @Test func cubeSurfacePointsLieOnTheCube() throws {
        let cube = Mesh.cube(extents: [2, 2, 2])
        let half = cube.positions.reduce(SIMD3<Float>.zero) { simd_max($0, abs($1)) }
        let points = try spawn(cube, location: .surface)
        for point in points {
            // On the surface: inside the cube, with at least one coordinate on a face.
            #expect(all(abs(point) .<= half + 1e-4))
            #expect((abs(point) - half).max() > -1e-4)
        }
    }
}
