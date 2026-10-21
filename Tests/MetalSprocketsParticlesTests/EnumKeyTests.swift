import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

/// Effect files name enum values ("index", "count", "name") instead of Swift's default "_0" (#153), and still read "_0"
/// from files saved before.
@Suite(.requiresMetal4)
struct EnumKeyTests {
    func json<T: Encodable>(_ value: T) throws -> String {
        // A store, for presets with images and distance fields.
        let encoder = EffectResources().encoder()
        encoder.outputFormatting = .sortedKeys
        return try #require(String(bytes: encoder.encode(value), encoding: .utf8))
    }

    @Test func valuesAreNamed() throws {
        #expect(try json(PointerBinding.collider(2)) == #"{"collider":{"index":2}}"#)
        #expect(try json(PointerBinding.forceField(1)) == #"{"forceField":{"index":1}}"#)
        #expect(try json(PointerBinding.emitter(0)) == #"{"emitter":{"index":0}}"#)
        #expect(try json(EmissionTrigger.Action.burst(150)) == #"{"burst":{"count":150}}"#)
        #expect(try json(EmissionTrigger.Condition.event("boom")) == #"{"event":{"name":"boom"}}"#)
    }

    @Test func everyCaseRoundTrips() throws {
        let volume = TriggerVolume.sphere(center: [1, 2, 3], radius: 0.5)
        let conditions: [EmissionTrigger.Condition] = [
            .event("boom"), .after(seconds: 2), .every(seconds: 0.5), .objectEnters(name: "ball", volume: volume),
            .particlesEnter(volume: volume, count: 3), .colliderHit(index: 1, count: 2),
        ]
        let actions: [EmissionTrigger.Action] = [.burst(5), .start, .stop, .restart]
        let bindings: [PointerBinding] = [.collider(0), .forceField(1), .emitter(2)]
        for condition in conditions {
            #expect(try JSONDecoder().decode(EmissionTrigger.Condition.self, from: JSONEncoder().encode(condition)) == condition)
        }
        for action in actions {
            #expect(try JSONDecoder().decode(EmissionTrigger.Action.self, from: JSONEncoder().encode(action)) == action)
        }
        for binding in bindings {
            #expect(try JSONDecoder().decode(PointerBinding.self, from: JSONEncoder().encode(binding)) == binding)
        }
    }

    @Test func samplePresetsHaveNoUnderscoreKeys() throws {
        for system in ParticleSystem.all {
            #expect(try !json(system).contains("\"_0\""), "\(system.name)")
        }
        let files = try FileManager.default.contentsOfDirectory(at: ParticleSystem.presetsFolder, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            #expect(try !String(contentsOf: file, encoding: .utf8).contains("\"_0\""), "\(file.lastPathComponent)")
        }
    }
}
