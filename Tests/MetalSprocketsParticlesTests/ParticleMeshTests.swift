import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing

@Suite(.serialized, .requiresMetal4)
struct ParticleMeshTests {
    /// Positions and normals from the interleaved vertex data.
    func split(_ mesh: ParticleMesh) -> (positions: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        let vertices = mesh.vertices
        let positions = stride(from: 0, to: vertices.count, by: 2).map { SIMD3(vertices[$0].x, vertices[$0].y, vertices[$0].z) }
        let normals = stride(from: 1, to: vertices.count, by: 2).map { SIMD3(vertices[$0].x, vertices[$0].y, vertices[$0].z) }
        return (positions, normals)
    }

    @Test func builtInShapesHaveOutwardUnitNormals() {
        for (mesh, vertexCount) in [(ParticleMesh.cube, 36), (.tetrahedron, 12), (.coin, 16 * 12)] {
            let (positions, normals) = split(mesh)
            #expect(positions.count == vertexCount)
            #expect(normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
            // Convex and centered: every face normal points away from the center.
            for triangle in stride(from: 0, to: positions.count, by: 3) {
                let centroid = (positions[triangle] + positions[triangle + 1] + positions[triangle + 2]) / 3
                #expect(simd_dot(centroid, normals[triangle]) > 0)
            }
            #expect(positions.allSatisfy { simd_reduce_max(abs($0)) <= 1 + 1e-5 })
        }
    }

    @Test func swiftMeshesAreTriangulatedWithFlatNormals() {
        let square = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]], faces: [[0, 1, 2, 3]])
        let (positions, normals) = split(ParticleMesh(mesh: square))
        #expect(positions.count == 6)
        #expect(normals.allSatisfy { abs(abs($0.y) - 1) < 1e-5 })
    }

    @Test func particleMeshesRoundTripThroughEffectFiles() throws {
        var emitter = ParticleEmitter()
        emitter.particleMesh = .coin
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: JSONEncoder().encode(emitter)).particleMesh == .coin)
    }

    /// One opaque cube particle, 0.5 across, in the middle: solid at the center, nothing near the corners of the view.
    @Test func meshParticlesDrawSolidShapes() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        var settings = ParticleEmitter()
        settings.shape = .point
        settings.velocity = .zero
        settings.velocitySpread = 0
        settings.gravity = .zero
        settings.lifetime = 10...10
        settings.birthRate = 0
        settings.angleVariation = 0
        settings.sizeOverLife = .constant(0.5)
        settings.colorOverLife = .constant([1, 0, 0, 1])
        settings.blendMode = .opaque
        settings.particleMesh = .cube
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, emitter: settings)
        system.burst(1)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        let pixels = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage.rgbaPixels()
        let center = pixels[32 * 64 + 32]
        #expect(center.x > 100 && center.y == 0 && center.z == 0)
        let corner = pixels[2 * 64 + 2]
        #expect(corner.x == 0 && corner.y == 0 && corner.z == 0)
    }
}
