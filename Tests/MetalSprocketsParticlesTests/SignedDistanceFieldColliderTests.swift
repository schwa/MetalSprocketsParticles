import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing

/// `Collider.Shape.signedDistanceField`: a baked distance grid as a collider (#149). Collision comes in #150.
@Suite(.serialized, .requiresMetal4)
struct SignedDistanceFieldColliderTests {
    /// A sphere's exact signed distance on a 9×7×5 grid (uneven, so axis mix-ups show), centered on `center`.
    func sphereField(radius: Float = 0.5, center: SIMD3<Float> = .zero) -> SignedDistanceField {
        let resolution = SIMD3<Int>(9, 7, 5)
        let spacing = SIMD3<Float>(0.25, 0.25, 0.25)
        let origin = center - spacing * SIMD3<Float>(resolution &- 1) / 2
        var values: [Float] = []
        for z in 0..<resolution.z {
            for y in 0..<resolution.y {
                for x in 0..<resolution.x {
                    values.append(simd_length(origin + spacing * SIMD3<Float>(Float(x), Float(y), Float(z)) - center) - radius)
                }
            }
        }
        return SignedDistanceField(origin: origin, spacing: spacing, resolution: resolution, values: values)
    }

    @Test func roundTripsThroughEffectFiles() throws {
        let collider = Collider.signedDistanceField(
            sphereField(), center: [1, 2, 3], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0]), categoryBitMask: 0b101
        )
        let decoded = try JSONDecoder().decode(Collider.self, from: JSONEncoder().encode(collider))
        #expect(decoded == collider)
    }

    /// What SignedDistanceField's initializer traps on, and sizes a hostile file could ask for, are decoding errors.
    @Test func badFieldsDoNotLoad() throws {
        func json(resolution: [Int], byteCount: Int) throws -> Data {
            let object: [String: Any] = [
                "kind": "signedDistanceField",
                "field": [
                    "origin": [0, 0, 0], "spacing": [1, 1, 1], "resolution": resolution,
                    "values": Data(count: byteCount).base64EncodedString(),
                ],
            ]
            return try JSONSerialization.data(withJSONObject: object)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Collider.self, from: json(resolution: [2, 2, 2], byteCount: 4 * 7)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Collider.self, from: json(resolution: [1, 2, 2], byteCount: 4 * 4)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Collider.self, from: json(resolution: [1_000, 1_000, 1_000], byteCount: 4)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Collider.self, from: json(resolution: [Int.max, 2, 2], byteCount: 4)) }
        #expect(try JSONDecoder().decode(Collider.self, from: json(resolution: [2, 2, 2], byteCount: 4 * 8)).categoryBitMask == .max)
    }

    @Test func runtimeUploadsEachGridOnceAndReusesIt() throws {
        let runner = try Runner()
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: ParticleEmitter())
        let field = sphereField()
        runtime.colliders = [.signedDistanceField(field), .signedDistanceField(field, center: [2, 0, 0])]
        try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        #expect(runtime.signedDistanceFieldTextures.count == 1)
        let texture = try #require(runtime.signedDistanceFieldTexture(for: field))
        #expect(texture.textureType == .type3D)
        #expect(texture.pixelFormat == .r32Float)
        let size = SIMD3<Int>(texture.width, texture.height, texture.depth)
        #expect(size == SIMD3<Int>(9, 7, 5))

        // The texture holds the values in grid order: read back a sample off every axis's center.
        var sample: Float = 0
        texture.getBytes(&sample, bytesPerRow: 4, bytesPerImage: 4, from: MTLRegionMake3D(7, 2, 1, 1, 1, 1), mipmapLevel: 0, slice: 0)
        #expect(sample == field[7, 2, 1])

        // Moving the colliders keeps the texture.
        runtime.colliders = runtime.colliders.map { $0.translated(by: [0, 1, 0]) }
        try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        #expect(runtime.signedDistanceFieldTexture(for: field) === texture)

        // A different grid gets its own; grids no collider uses are dropped.
        let other = sphereField(radius: 0.3)
        runtime.colliders = [.signedDistanceField(other)]
        try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        #expect(runtime.signedDistanceFieldTextures.count == 1)
        #expect(runtime.signedDistanceFieldTexture(for: field) == nil)
        #expect(runtime.signedDistanceFieldTexture(for: other) != nil)
    }

    /// Drawn as the grid's bounds, placed by the collider's center and rotation.
    @Test func wireframeShowsTheBounds() {
        let rotation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let collider = Collider.signedDistanceField(sphereField(), center: [1, 0, 0], rotation: rotation)
        let lines = collider.wireframe
        #expect(lines.count == 24) // A box: 12 edges.
        let box = Collider.box(center: [1, 0, 0], halfExtents: [1, 0.75, 0.5], rotation: rotation)
        for (line, expected) in zip(lines, box.wireframe) {
            #expect(simd_distance(line, expected) < 1e-5)
        }
    }

    /// Until #150, distance field colliders are skipped: particles fall through as if nothing were there.
    @Test func particlesPassThroughForNow() throws {
        func fall(colliders: [Collider]) throws -> [SIMD3<Float>] {
            let runner = try Runner()
            var emitter = ParticleEmitter()
            emitter.shape = .point
            emitter.position = [0, 1, 0]
            emitter.velocity = .zero
            emitter.velocitySpread = 0
            emitter.gravity = [0, -9.8, 0]
            emitter.lifetime = 10...10
            emitter.birthRate = 0
            let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter)
            runtime.colliders = colliders
            runtime.burst(4)
            for _ in 0..<60 {
                try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
            }
            let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
            return (0..<4).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
        }
        let free = try fall(colliders: [])
        let throughField = try fall(colliders: [.signedDistanceField(sphereField())])
        #expect(free == throughField)
        #expect(free.allSatisfy { $0.y < -2 })
    }
}
