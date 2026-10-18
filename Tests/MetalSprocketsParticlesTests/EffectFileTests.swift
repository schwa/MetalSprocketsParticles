import Foundation
@testable import MetalSprocketsParticles
import simd
import Testing

struct EffectFileTests {
    /// Every built-in preset survives JSON, except meshes, which are not saved.
    @Test(arguments: ParticlePreset.all.map(\.name))
    func presetRoundTrips(name: String) throws {
        let preset = try #require(ParticlePreset.named(name))
        let decoded = try JSONDecoder().decode(ParticlePreset.self, from: try preset.jsonData())
        #expect(decoded.name == preset.name)
        #expect(decoded.colliders == preset.colliders)
        #expect(decoded.forceFields == preset.forceFields)
        #expect(decoded.animatesColliders == preset.animatesColliders)
        #expect(decoded.cameraEye == preset.cameraEye && decoded.cameraTarget == preset.cameraTarget)
        #expect(decoded.layers.count == preset.layers.count)
        for (saved, original) in zip(decoded.layers, preset.layers) {
            var expected = original
            expected.mesh = nil
            #expect(saved == expected)
        }
    }

    @Test func colliderRotationRoundTrips() throws {
        let box = Collider.box(center: [1, 2, 3], halfExtents: [1, 1, 1], rotation: simd_quatf(angle: 0.3, axis: [0, 0, 1]))
        let decoded = try JSONDecoder().decode(Collider.self, from: try JSONEncoder().encode(box))
        #expect(decoded == box)
    }

    @Test func emitterSettingsMissingFromAFileKeepTheirDefaults() throws {
        let json = Data(#"{ "birthRate": 42, "gravity": [0, -1, 0] }"#.utf8)
        let emitter = try JSONDecoder().decode(ParticleEmitter.self, from: json)
        var expected = ParticleEmitter()
        expected.birthRate = 42
        expected.gravity = [0, -1, 0]
        #expect(emitter == expected)
    }

    @Test func unknownColliderKindIsAnError() {
        let json = Data(#"{ "kind": "torus" }"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Collider.self, from: json)
        }
    }

    @Test func writeAndReadAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("effect-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ParticlePreset.fireworks.write(to: url)
        let loaded = try ParticlePreset(contentsOf: url)
        #expect(loaded.layers.map(\.settings) == ParticlePreset.fireworks.layers.map(\.settings))
    }
}
