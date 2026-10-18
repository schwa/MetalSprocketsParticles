import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

/// Colliders and force fields apply to an emitter only when its mask shares a bit with their category.
@Suite(.serialized)
struct CategoryMaskTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    /// Two emitters dropping still particles from y = 1; returns each emitter's particles after `steps` steps.
    func drop(_ configure: (inout ParticleEmitter, Int) -> Void, colliders: [Collider] = [], fields: [ForceField] = [], steps: Int = 90) throws -> [[Particle]] {
        let emitters: [ParticleEmitter] = (0..<2).map { index in
            var emitter = ParticleEmitter()
            emitter.position = [0, 1, 0]
            emitter.radius = 0
            emitter.velocity = .zero
            emitter.velocitySpread = 0
            emitter.drag = 0
            emitter.restitution = 0
            emitter.lifetime = 100...100
            emitter.birthRate = 0
            configure(&emitter, index)
            return emitter
        }
        let system = try ParticleSystemRuntime(device: runner.device, emitters: emitters, capacity: 8, seed: 3)
        system.colliders = colliders
        system.forceFields = fields
        system.emitters.forEach { $0.burst(8) }
        for _ in 0..<steps {
            try runner.run(try system.simulate(deltaTime: 1.0 / 60.0))
        }
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return system.emitters.map { emitter in emitter.range.map { pointer[$0] } }
    }

    @Test func collidersSkipEmittersOutsideTheirCategory() throws {
        let floor = Collider.plane(normal: [0, 1, 0], distance: 0, categoryBitMask: 0b01)
        let result = try drop({ emitter, index in
            emitter.collisionMask = index == 0 ? 0b01 : 0b10
        }, colliders: [floor])
        #expect(result[0].allSatisfy { $0.position.y > -0.01 })
        #expect(result[1].allSatisfy { $0.position.y < -1 })
    }

    @Test func fieldsSkipEmittersOutsideTheirCategory() throws {
        let wind = ForceField.wind(velocity: [5, 0, 0], strength: 2, categoryBitMask: 0b10)
        let result = try drop({ emitter, index in
            emitter.gravity = .zero
            emitter.fieldMask = index == 0 ? 0b01 : 0b10
        }, fields: [wind], steps: 30)
        #expect(result[0].allSatisfy { $0.position.x == 0 })
        #expect(result[1].allSatisfy { $0.position.x > 0.5 })
    }

    @Test func defaultMasksMatchEverything() throws {
        let result = try drop({ _, _ in }, colliders: [.plane(normal: [0, 1, 0], distance: 0)])
        #expect(result.joined().allSatisfy { $0.position.y > -0.01 })
    }

    @Test func masksSaveAndDefaultsStayOutOfFiles() throws {
        let masked = Collider.sphere(center: .zero, radius: 1, categoryBitMask: 0b100)
        #expect(try JSONDecoder().decode(Collider.self, from: try JSONEncoder().encode(masked)) == masked)
        let plain = try JSONEncoder().encode(Collider.sphere(center: .zero, radius: 1))
        #expect(String(bytes: plain, encoding: .utf8)?.contains("categoryBitMask") == false)
        // Files saved before categories existed still load, with all bits set.
        let old = Data(#"{ "kind": "sphere", "center": [0, 0, 0], "radius": 1 }"#.utf8)
        #expect(try JSONDecoder().decode(Collider.self, from: old).categoryBitMask == .max)

        let field = ForceField.vortex(center: .zero, strength: 1, categoryBitMask: 0b11)
        #expect(try JSONDecoder().decode(ForceField.self, from: try JSONEncoder().encode(field)) == field)
        let oldField = Data(#"{ "turbulence": { "strength": 2, "scale": 1, "speed": 0 } }"#.utf8)
        #expect(try JSONDecoder().decode(ForceField.self, from: oldField) == .turbulence(strength: 2))
        var emitter = ParticleEmitter()
        emitter.collisionMask = 0b1
        emitter.fieldMask = 0b10
        #expect(try JSONDecoder().decode(ParticleEmitter.self, from: try JSONEncoder().encode(emitter)) == emitter)
    }
}
