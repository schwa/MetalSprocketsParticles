import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

/// The hand-written tolerant decoders (missing keys keep defaults) must read every key their types write. A forgotten
/// `container.update` line would otherwise drop a setting from effect files without any error.
@Suite(.requiresMetal4)
struct DecodingCoverageTests {
    /// Every key `value` encodes, each replaced in turn by a value of the wrong type, must make decoding fail; if decoding
    /// still succeeds, the decoder never read that key. Returns the keys it ignored.
    func ignoredKeys<T: Codable>(_ value: T) throws -> [String] {
        let data = try JSONEncoder().encode(value)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try object.keys.sorted().filter { key in
            var broken = object
            // A number where a string belongs, a string anywhere else.
            broken[key] = object[key] is String ? 12_345 as Any : "not a valid value for any setting" as Any
            let brokenData = try JSONSerialization.data(withJSONObject: broken)
            return (try? JSONDecoder().decode(T.self, from: brokenData)) != nil
        }
    }

    @Test func emitterDecoderReadsEverySetting() throws {
        // Optional settings are only written when set, so set them all.
        var emitter = ParticleEmitter()
        let function = ParticleFunction(source: "", name: "f")
        emitter.updateFunction = function
        emitter.spawnFunction = function
        emitter.collisionFunction = function
        emitter.deathFunction = function
        emitter.emissionDuration = 1
        emitter.imageSequence = ImageSequence(rows: 2, columns: 2)
        #expect(try ignoredKeys(emitter).isEmpty)
    }

    @Test func systemDecoderReadsEveryField() throws {
        #expect(try ignoredKeys(ParticleSystem.dunk).isEmpty)
    }

    @Test func subEmitterDecoderReadsEveryField() throws {
        #expect(try ignoredKeys(SubEmitter.transition(on: .onDeath, into: ParticleEmitter(), sprite: .star, continuesLife: true)).isEmpty)
    }
}
