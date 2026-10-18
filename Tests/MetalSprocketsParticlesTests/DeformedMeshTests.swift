import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing

/// Mesh emitters following a morphing or skinned mesh through `EmitterMesh.setDeformedPositions`.
@Suite(.serialized)
struct DeformedMeshTests {
    let runner: Runner
    /// A unit square at y = 0, two triangles.
    let restPositions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]]
    let indices: [UInt32] = [0, 1, 2, 0, 2, 3]

    init() throws {
        runner = try Runner()
    }

    /// Positions written like an interleaved vertex buffer: 4 bytes of padding, then a packed float3, 16 bytes per
    /// vertex.
    func interleavedBuffer(_ positions: [SIMD3<Float>]) throws -> MTLBuffer {
        var bytes = [Float](repeating: -1, count: positions.count * 4)
        for (index, position) in positions.enumerated() {
            bytes[index * 4 + 1] = position.x
            bytes[index * 4 + 2] = position.y
            bytes[index * 4 + 3] = position.z
        }
        return try #require(runner.device.makeBuffer(bytes: bytes, length: bytes.count * 4, options: .storageModeShared))
    }

    /// Bursts `count` still particles from the mesh and returns their positions after one step.
    func emit(_ mesh: EmitterMesh, location: ParticleBirthLocation = .surface, count: Int = 64) throws -> [SIMD3<Float>] {
        var settings = ParticleEmitter()
        settings.shape = .mesh
        settings.birthLocation = location
        settings.velocity = .zero
        settings.velocitySpread = 0
        settings.gravity = .zero
        settings.lifetime = 10...10
        settings.birthRate = 0
        let system = try ParticleSystemRuntime(device: runner.device, capacity: count, emitter: settings)
        system.emitters[0].mesh = mesh
        system.burst(count)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: count)
        return (0..<count).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    @Test func waveKeepsTheFixedEndAndBendsTheFreeEnd() {
        let wave = MeshDeformation.wave(amplitude: 0.5, wavelength: 1, speed: 1)
        let positions: [SIMD3<Float>] = [[0, 0, 0], [0, 1, 0], [2, 0, 0], [2, 1, 0]]
        let deformed = (0..<20).map { wave.deform(positions, time: Float($0) * 0.1) }
        #expect(deformed.allSatisfy { $0[0] == positions[0] && $0[1] == positions[1] })
        #expect(deformed.allSatisfy { abs($0[2].z) <= 0.5 && abs($0[3].z) <= 0.5 })
        #expect(deformed.contains { abs($0[2].z) > 0.3 })
        #expect(MeshDeformation.none.deform(positions, time: 3) == positions)
    }

    @Test func systemAnimatesAMeshDeformationEachFrame() throws {
        // A flat square in the XY plane (z = 0) that waves along Z.
        var settings = ParticleEmitter()
        settings.shape = .mesh
        settings.birthLocation = .surface
        settings.velocity = .zero
        settings.velocitySpread = 0
        settings.gravity = .zero
        settings.lifetime = 10...10
        settings.birthRate = 0
        var description = EmitterDescription("Flag", settings: settings, capacity: 256)
        description.mesh = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2], [0, 2, 3]])
        description.meshDeformation = .wave(amplitude: 0.4, wavelength: 1, speed: 1)
        let system = try ParticleSystemRuntime(device: runner.device, emitters: [], capacity: 1)
        try system.apply([description])
        for _ in 0..<10 {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        system.burst(256)
        try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: 256)
        let depths = (0..<256).map { pointer[$0].position.z }
        #expect(depths.contains { abs($0) > 0.05 })
        #expect(depths.allSatisfy { abs($0) <= 0.40001 })
    }

    @Test func restPoseByDefault() throws {
        let mesh = try EmitterMesh(device: runner.device, positions: restPositions, indices: indices)
        let positions = try emit(mesh)
        #expect(positions.allSatisfy { abs($0.y) < 1e-5 && (-1e-5...1.00001).contains($0.x) })
    }

    @Test func surfaceFollowsDeformedPositions() throws {
        let mesh = try EmitterMesh(device: runner.device, positions: restPositions, indices: indices)
        // Lifted by 5 and stretched to 3 wide in x.
        let deformed = restPositions.map { SIMD3($0.x * 3, $0.y + 5, $0.z) }
        mesh.setDeformedPositions(try interleavedBuffer(deformed), offset: 4, stride: 16)
        let positions = try emit(mesh)
        #expect(positions.allSatisfy { abs($0.y - 5) < 1e-4 })
        #expect(positions.contains { $0.x > 1.5 })
        #expect(positions.allSatisfy { (-1e-4...3.0001).contains($0.x) && (-1e-4...1.0001).contains($0.z) })
    }

    @Test func verticesFollowDeformedPositions() throws {
        let mesh = try EmitterMesh(device: runner.device, positions: restPositions, indices: indices)
        let deformed = restPositions.map { $0 + [0, 2, 0] }
        mesh.setDeformedPositions(try interleavedBuffer(deformed), offset: 4, stride: 16)
        let positions = try emit(mesh, location: .vertices)
        #expect(positions.allSatisfy { position in deformed.contains { simd_distance($0, position) < 1e-5 } })
    }

    @Test func clearingDeformationReturnsToRest() throws {
        let mesh = try EmitterMesh(device: runner.device, positions: restPositions, indices: indices)
        mesh.setDeformedPositions(try interleavedBuffer(restPositions.map { $0 + [0, 7, 0] }), offset: 4, stride: 16)
        mesh.setDeformedPositions(nil)
        #expect(try emit(mesh).allSatisfy { abs($0.y) < 1e-5 })
    }
}
