import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// `ParticleSystem.is2D`: one switch for the overlay camera and emitters on their plane (#141).
struct TwoDModeTests {
    func system(is2D: Bool) -> ParticleSystem {
        var emitter = ParticleEmitter()
        emitter.constrainsToPlane = false
        var system = ParticleSystem("2D", layers: [EmitterDescription("Dots", settings: emitter)])
        system.is2D = is2D
        return system
    }

    @Test func systemCameraBecomesTheOverlayIn2D() {
        let size = CGSize(width: 800, height: 600)
        let flat = system(is2D: true)
        let camera = ParticleCamera.system.matrices(for: flat, size: size)
        let overlay = ParticleCamera.overlay.matrices(for: flat, size: size)
        #expect(camera.projection == overlay.projection)
        #expect(camera.cameraToWorld == overlay.cameraToWorld)
        // In 3D the system's own perspective camera stays.
        let deep = ParticleCamera.system.matrices(for: system(is2D: false), size: size)
        #expect(deep.projection != overlay.projection)
    }

    @Test func emittersRunOnTheirPlaneButKeepTheirOwnSetting() throws {
        let flat = system(is2D: true)
        let runtime = try ParticleSystemRuntime(capacity: 1, emitter: ParticleEmitter())
        try runtime.load(flat)
        // swiftlint:disable:next prefer_key_path
        #expect(runtime.emitters.allSatisfy { $0.settings.constrainsToPlane })
        // The stored layer is untouched, so turning 2D off restores it.
        #expect(flat.layers.allSatisfy { !$0.settings.constrainsToPlane })
        try runtime.apply(system(is2D: false))
        #expect(runtime.emitters.allSatisfy { !$0.settings.constrainsToPlane })
    }

    @Test func twoDDefaultsAreInPoints() {
        let emitter = ParticleEmitter.default2D
        let speed = simd_length(emitter.velocity)
        #expect(speed >= 100)
        // Spread and speed variation are speeds too (#140).
        #expect(emitter.velocitySpread > speed * 0.3)
        #expect(emitter.speedVariation > speed * 0.2)
        #expect(emitter.gravity.y > 0) // Down the screen.
        #expect(emitter.constrainsToPlane)
    }

    @Test func is2DRoundTripsAndOldFilesAre3D() throws {
        let flat = system(is2D: true)
        let decoded = try JSONDecoder().decode(ParticleSystem.self, from: JSONEncoder().encode(flat))
        #expect(decoded.is2D)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(flat)) as? [String: Any])
        object["is2D"] = nil
        let old = try JSONDecoder().decode(ParticleSystem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!old.is2D)
    }
}
