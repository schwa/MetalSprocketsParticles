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

    // MARK: Moving with scene-graph nodes (#152)

    /// A flat 1.2 × 0.1 × 1.2 slab, for particles to rest on.
    var slab: SignedDistanceField {
        field { point in
            let q = abs(point) - SIMD3<Float>(0.6, 0.05, 0.6)
            return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
        }
    }

    /// Particles dropped onto a slab at `start`, then the slab placed each frame by `transform(frame)`, as a host
    /// following a scene-graph node would. Returns the particles' final positions.
    func ride(from start: SIMD3<Float>, frames: Int = 90, transform: (Int) -> simd_float4x4) throws -> [SIMD3<Float>] {
        let runner = try Runner()
        var emitter = ParticleEmitter()
        emitter.shape = .point
        emitter.position = start
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = [0, -9.8, 0]
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        emitter.restitution = 0
        emitter.friction = 1
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 4, emitter: emitter)
        let collider = Collider.signedDistanceField(slab)
        runtime.burst(4)
        for frame in 0..<frames {
            try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0, colliders: [collider.placed(by: transform(frame))]))
        }
        let pointer = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
        return (0..<4).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
    }

    /// Still for half a second while the particles land, then sliding in x at 0.6 m/s: the particles go with it.
    @Test func aMovingFieldCarriesParticles() throws {
        let landed = try ride(from: [0, 0.5, 0]) { frame in
            let x = Float(max(frame - 30, 0)) / 60 * 0.6
            return simd_float4x4(translation: [x, 0, 0])
        }
        #expect(landed.allSatisfy { abs($0.x - 0.6) < 0.05 && abs($0.y - 0.05) < cell })
    }

    /// Spinning fast about y after the particles land 0.4 from the axis: they are flung off the edge and fall.
    @Test func aSpinningFieldFlingsParticles() throws {
        let landed = try ride(from: [0.4, 0.5, 0]) { frame in
            let angle = Float(max(frame - 30, 0)) / 60 * 4 * .pi
            return simd_float4x4(simd_quatf(angle: angle, axis: [0, 1, 0]))
        }
        #expect(landed.allSatisfy { $0.y < -0.5 })
        // Not spinning, they stay put: the throw comes from the spin.
        let still = try ride(from: [0.4, 0.5, 0]) { _ in matrix_identity_float4x4 }
        #expect(still.allSatisfy { abs($0.y - 0.05) < cell })
    }

    /// A long frame (the app coming back from the background) must not fling particles off a spinning collider. The
    /// player's clock, which turns spun colliders, has to step the same capped time as the simulation; it used to step
    /// the whole frame, so the collider jumped ahead and its spin over the capped step looked many times faster. The
    /// clock check catches that; this gentle spin alone does not throw the sand far enough to see.
    @Test func aLongFrameKeepsSpunCollidersInStep() throws {
        var sand = ParticleEmitter()
        sand.shape = .point
        sand.position = [0.4, 0.3, 0]
        sand.velocity = .zero
        sand.velocitySpread = 0
        sand.gravity = [0, -9.8, 0]
        sand.lifetime = 100...100
        sand.birthRate = 0
        sand.restitution = 0
        sand.friction = 1
        var system = ParticleSystem("Turntable", layers: [EmitterDescription("Sand", settings: sand, capacity: 4)], colliders: [.signedDistanceField(slab)])
        system.colliderSpins = [ColliderSpin(collider: 0, axis: [0, 1, 0], speed: 0.5)]
        let size = CGSize(width: 64, height: 64)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        player.runtime.burst(4)
        for _ in 0..<60 {
            _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        _ = try renderer.render(try player.frame(deltaTime: 0.5, size: size))
        // The colliders' clock and the simulation's agree after the long frame.
        #expect(abs(player.time - player.runtime.emitters[0].spawner.time) < 1e-4)
        for _ in 0..<30 {
            _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        let pointer = player.runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
        let positions = (0..<4).map { SIMD3(pointer[$0].position.x, pointer[$0].position.y, pointer[$0].position.z) }
        // Still on the slab, riding round at 0.4 from the axis.
        #expect(positions.allSatisfy { abs($0.y - 0.05) < cell && abs(simd_length(SIMD2($0.x, $0.z)) - 0.4) < 0.05 })
    }

    /// Uneven frames (a short one after a long one, as after the app comes back from the background) must not make a
    /// spun collider seem faster. The player used to place colliders before moving its clock, so each step got the
    /// previous frame's motion divided by this frame's deltaTime: 0.03 s of turn over 0.004 s is 7.5 times the spin.
    /// Sand riding a slab at 0.5 rad/s, 0.4 from the axis, moves at 0.2 m/s; with the bug it reached about 1.5.
    @Test func unevenFramesDoNotSpeedUpSpunColliders() throws {
        var sand = ParticleEmitter()
        sand.shape = .point
        sand.position = [0.4, 0.3, 0]
        sand.velocity = .zero
        sand.velocitySpread = 0
        sand.gravity = [0, -9.8, 0]
        sand.lifetime = 100...100
        sand.birthRate = 0
        sand.restitution = 0
        sand.friction = 1
        var system = ParticleSystem("Turntable", layers: [EmitterDescription("Sand", settings: sand, capacity: 4)], colliders: [.signedDistanceField(slab)])
        system.colliderSpins = [ColliderSpin(collider: 0, axis: [0, 1, 0], speed: 0.5)]
        let size = CGSize(width: 64, height: 64)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        player.runtime.burst(4)
        for _ in 0..<60 {
            _ = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        var fastest: Float = 0
        for frame in 0..<60 {
            _ = try renderer.render(try player.frame(deltaTime: frame.isMultiple(of: 2) ? 0.03 : 0.004, size: size))
            let pointer = player.runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 4)
            for index in 0..<4 {
                fastest = max(fastest, simd_length(SIMD2(pointer[index].velocity.x, pointer[index].velocity.z)))
            }
        }
        #expect(fastest < 0.3)
    }

    /// A node's world matrix gives the center and rotation; scale is dropped, since baked distances do not scale.
    @Test func placedByTakesTranslationAndRotation() {
        let rotation = simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3]))
        let transform = simd_float4x4(translation: [1, 2, 3]) * simd_float4x4(rotation) * simd_float4x4(scale: [2, 2, 2])
        guard case let .signedDistanceField(_, center, placedRotation) = Collider.signedDistanceField(slab).placed(by: transform).shape else {
            Issue.record("Not a distance field")
            return
        }
        #expect(simd_distance(center, [1, 2, 3]) < 1e-5)
        #expect(abs(abs(simd_dot(placedRotation.vector, rotation.vector)) - 1) < 1e-5)
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
        let resources = EffectResources()
        let decoded = try resources.decoder().decode(Collider.self, from: resources.encoder().encode(collider))
        #expect(decoded == collider)
    }

    /// What SignedDistanceField's initializer traps on, and sizes a hostile file could ask for, are decoding errors.
    @Test func badFieldsDoNotLoad() throws {
        // The values are a file next to the JSON (#169); here, in memory.
        func decode(resolution: [Int], byteCount: Int) throws -> Collider {
            let object: [String: Any] = [
                "kind": "signedDistanceField",
                "field": ["origin": [0, 0, 0], "spacing": [1, 1, 1], "resolution": resolution, "values": "values.bin"],
            ]
            let resources = EffectResources(files: ["values.bin": Data(count: byteCount)])
            return try resources.decoder().decode(Collider.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(throws: DecodingError.self) { try decode(resolution: [2, 2, 2], byteCount: 4 * 7) }
        #expect(throws: DecodingError.self) { try decode(resolution: [1, 2, 2], byteCount: 4 * 4) }
        #expect(throws: DecodingError.self) { try decode(resolution: [1_000, 1_000, 1_000], byteCount: 4) }
        #expect(throws: DecodingError.self) { try decode(resolution: [Int.max, 2, 2], byteCount: 4) }
        #expect(try decode(resolution: [2, 2, 2], byteCount: 4 * 8).categoryBitMask == .max)
    }

    @Test func runtimeUploadsEachGridOnceAndReusesIt() throws {
        let runner = try Runner()
        let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 4, modules: .standard)
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

    /// Sand falling fast onto a thin part (a fin two cells wide) rests on its top: it must not be pushed out a side,
    /// slide off, or end inside (#157). A step moves it several cells, so it ends deep in the fin, where the nearest
    /// surface is a side.
    @Test func fastParticlesRestOnTopOfThinParts() throws {
        let fin = field { point in
            let q = abs(point - [0, 0.2, 0]) - SIMD3<Float>(0.05, 0.2, 0.5)
            return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
        }
        for x: Float in [-0.03, 0, 0.02] {
            let landed = try land(on: [.signedDistanceField(fin)], from: [x, 0.95, 0], velocity: [0, -9, 0])
            #expect(landed.allSatisfy { abs($0.y - 0.4) < cell && abs($0.x - x) < cell }, "x = \(x): \(landed[0])")
        }
    }

    /// A particle sliding down a slope keeps its speed: a distance field slab and an analytic box tilted the same way
    /// carry it about as far. The entry-point response (#157) put sliding particles back where their step entered,
    /// throwing away their motion along the surface, so Marble Run's marbles crawled.
    @Test func particlesSlideDownSlopesAtFullSpeed() throws {
        let tilt = simd_quatf(angle: 0.4, axis: [0, 0, 1])
        let slab = field { point in
            let q = abs(point) - SIMD3<Float>(0.9, 0.08, 0.5)
            return simd_length(simd_max(q, .zero)) + min(max(q.x, max(q.y, q.z)), 0)
        }
        func slide(on collider: Collider) throws -> Float {
            let runner = try Runner()
            var emitter = ParticleEmitter()
            emitter.shape = .point
            // Just above the slab's top near its high end (the slope falls toward -x).
            emitter.position = tilt.act([0.6, 0.1, 0])
            emitter.velocity = .zero
            emitter.velocitySpread = 0
            emitter.gravity = [0, -9.8, 0]
            emitter.lifetime = 10...10
            emitter.birthRate = 0
            emitter.restitution = 0
            emitter.friction = 0
            let runtime = try ParticleSystemRuntime(device: runner.device, capacity: 1, emitter: emitter)
            runtime.colliders = [collider]
            runtime.burst(1)
            for _ in 0..<20 {
                try runner.run(try runtime.simulate(deltaTime: 1.0 / 60.0))
            }
            let particle = runtime.buffer.contents().bindMemory(to: Particle.self, capacity: 1)[0]
            return 0.6 * cos(0.4) - particle.position.x
        }
        let box = try slide(on: .box(center: .zero, halfExtents: [0.9, 0.08, 0.5], rotation: tilt))
        let distanceField = try slide(on: .signedDistanceField(slab, rotation: tilt))
        #expect(box > 0.1)
        #expect(distanceField > box * 0.8, "distance field \(distanceField), box \(box)")
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
