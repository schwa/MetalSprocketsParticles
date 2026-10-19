import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh
import Testing

/// `Collider.Shape.signedDistanceField`: a baked distance grid as a collider (#149), which particles collide with (#150).
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

    // MARK: Baking from meshes (#151)

    @Test func aBakedCubeMatchesItsExactDistance() throws {
        let collider = try #require(Collider.signedDistanceField(mesh: .box(extents: [1, 1, 1]), resolution: 24))
        guard case let .signedDistanceField(field, _, _) = collider.shape else {
            Issue.record("Not a distance field")
            return
        }
        let spacing = field.spacing.max()
        var worst: Float = 0
        for index in field.values.indices {
            let q = abs(field.position(ofIndex: index)) - SIMD3<Float>(repeating: 0.5)
            let exact = simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
            worst = max(worst, abs(field.values[index] - exact))
        }
        #expect(worst < spacing)
        // Padding keeps the grid's edge outside the mesh.
        #expect(field.values[0] > 0)
    }

    /// `resolution` samples along the longest side, the same spacing on the others, plus `padding` cells all round.
    @Test func bakedGridsHaveCubeCellsAndPadding() throws {
        let collider = try #require(Collider.signedDistanceField(mesh: .box(extents: [2, 1, 0.5]), resolution: 33, padding: 2))
        guard case let .signedDistanceField(field, _, _) = collider.shape else {
            Issue.record("Not a distance field")
            return
        }
        #expect(field.resolution.x == 33)
        #expect(field.spacing.max() / field.spacing.min() < 1.1)
        // Two cells of padding before the mesh starts at x = -1.
        #expect(abs(field.origin.x - (-1 - 2 * field.spacing.x)) < 1e-4)
    }

    @Test func meshesWithoutTrianglesBakeNothing() {
        #expect(Collider.signedDistanceField(mesh: Mesh(positions: [], faces: [[Int]]())) == nil)
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

    /// An exact signed distance on a fine grid covering -extent...extent on every axis.
    func field(extent: Float = 1, samples: Int = 41, distance: (SIMD3<Float>) -> Float) -> SignedDistanceField {
        let spacing = 2 * extent / Float(samples - 1)
        let origin = SIMD3<Float>(repeating: -extent)
        var values: [Float] = []
        values.reserveCapacity(samples * samples * samples)
        for z in 0..<samples {
            for y in 0..<samples {
                for x in 0..<samples {
                    values.append(distance(origin + spacing * SIMD3<Float>(Float(x), Float(y), Float(z))))
                }
            }
        }
        return SignedDistanceField(origin: origin, spacing: SIMD3(repeating: spacing), resolution: SIMD3(repeating: samples), values: values)
    }

    /// Where particles end after falling from `start` with `velocity` for a second, all four on the same path.
    func land(
        on colliders: [Collider], from start: SIMD3<Float> = [0, 1.5, 0], velocity: SIMD3<Float> = .zero, radius: Float = 0, categoryMask: UInt32 = .max
    ) throws -> [SIMD3<Float>] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = start
        emitter.velocity = velocity
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0
        emitter.friction = 1
        emitter.collisionRadius = radius
        emitter.categoryMask = categoryMask
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter)
        runtime.colliders = colliders
        runtime.burst(4)
        for _ in 0..<60 {
            try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
        return (0..<4).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    var ball: SignedDistanceField {
        field { simd_length($0) - 0.5 }
    }

    /// One grid cell: trilinear filtering of an exact distance is close to the surface, not on it.
    let cell: Float = 2.0 / 40

    @Test func particlesRestOnTheSurface() throws {
        let landed = try land(on: [.signedDistanceField(ball)])
        #expect(landed.allSatisfy { abs($0.y - 0.5) < cell })
    }

    @Test func theColliderIsPlacedByItsCenterAndRotation() throws {
        // A flat 0.6 × 0.1 × 0.6 slab, turned 90° about x so it stands up, then moved: from above it is 0.6 deep in
        // y around y = 1 - 0.3, so particles rest on top at y = 1.3.
        let slab = field { point in
            let q = abs(point) - SIMD3<Float>(0.3, 0.05, 0.3)
            return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
        }
        let collider = Collider.signedDistanceField(slab, center: [2, 1, 0], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        let landed = try land(on: [collider], from: [2, 2.5, 0])
        #expect(landed.allSatisfy { abs($0.y - 1.3) < cell })
    }

    /// Faster than a cell per step (`45` m/s is 0.75 per step against a 0.1-thick wall): caught by sampling along the
    /// step, not left to tunnel through.
    @Test func fastParticlesDoNotPassThroughAThinWall() throws {
        let wall = field { abs($0.y) - 0.05 }
        let landed = try land(on: [.signedDistanceField(wall)], from: [0, 0.9, 0], velocity: [0, -45, 0])
        #expect(landed.allSatisfy { $0.y > 0 && $0.y < 0.05 + cell })
    }

    @Test func collisionRadiusGrowsTheSurface() throws {
        let landed = try land(on: [.signedDistanceField(ball)], radius: 0.1)
        #expect(landed.allSatisfy { abs($0.y - 0.6) < cell })
    }

    @Test func categoryMasksApply() throws {
        let landed = try land(on: [.signedDistanceField(ball, categoryBitMask: 0b10)], categoryMask: 0b01)
        #expect(landed.allSatisfy { $0.y < -2 })
    }

    /// Outside the grid nothing collides, even where the field is negative at the grid's border (a half-space below
    /// y = 0), which clamped sampling would otherwise carry outside.
    @Test func nothingCollidesOutsideTheGrid() throws {
        let ground = field { $0.y }
        #expect(try land(on: [.signedDistanceField(ground)]).allSatisfy { abs($0.y) < cell })
        #expect(try land(on: [.signedDistanceField(ground)], from: [1.5, 1.5, 0]).allSatisfy { $0.y < -2 })
    }
}
