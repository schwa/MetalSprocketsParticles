import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

/// `ParticleSystem.is2D`: one switch for the overlay camera and emitters on their plane (#141).
@Suite(.requiresMetal4)
struct TwoDModeTests {
    func system(is2D: Bool) -> ParticleSystem {
        var emitter = ParticleEmitter()
        emitter.constrainsToPlane = false
        var system = ParticleSystem("2D", layers: [EmitterDescription("Dots", settings: emitter)])
        system.is2D = is2D
        return system
    }

    /// In 2D the scene cameras show the scene flat, in its own units, framed like the 3D view at the target; they used to
    /// switch to the overlay camera in points, which left a normal scene as a speck in the corner (#154).
    @Test func sceneCamerasShowAFlatFrontViewIn2D() {
        let size = CGSize(width: 800, height: 600)
        var flat = system(is2D: true)
        flat.cameraEye = [1, 2, 6]
        flat.cameraTarget = [1, 2, 0]
        let camera = ParticleCamera.system.matrices(for: flat, size: size)
        func project(_ point: SIMD3<Float>) -> SIMD2<Float> {
            let clip = camera.projection * camera.cameraToWorld.inverse * SIMD4(point, 1)
            return SIMD2(clip.x, clip.y) / clip.w
        }
        // The target is centered; y is up; one unit at the target matches the perspective view's scale there.
        #expect(simd_length(project(flat.cameraTarget)) < 1e-5)
        #expect(project([1, 3, 0]).y > 0)
        let halfHeight = 6 * tan(Float.pi / 8)
        #expect(abs(project([1, 2 + halfHeight, 0]).y - 1) < 1e-4)
        // Orthographic: depth does not move points across the screen.
        #expect(simd_distance(project([1.5, 2.5, 0]), project([1.5, 2.5, -3])) < 1e-5)
        // .lookAt follows the same rule; .overlay stays in points.
        let lookAt = ParticleCamera.lookAt(eye: flat.cameraEye, target: flat.cameraTarget).matrices(for: flat, size: size)
        #expect(lookAt.projection == camera.projection)
        let overlay = ParticleCamera.overlay.matrices(for: flat, size: size)
        #expect(overlay.projection != camera.projection)
        // In 3D the system's own perspective camera stays.
        let deep = ParticleCamera.system.matrices(for: system(is2D: false), size: size)
        #expect(deep.projection != camera.projection)
    }

    @Test func emittersRunOnTheirPlaneButKeepTheirOwnSetting() throws {
        let flat = system(is2D: true)
        let runtime = try ParticleSystemRuntime(capacity: 1, modules: .standard)
        try runtime.load(flat)
        // swiftlint:disable:next prefer_key_path
        #expect(runtime.emitters.allSatisfy { $0.forcesPlane })
        // The stored layer is untouched, so turning 2D off restores it.
        #expect(flat.layers.allSatisfy { !$0.settings.constrainsToPlane })
        try runtime.apply(system(is2D: false))
        #expect(runtime.emitters.allSatisfy { !$0.forcesPlane })
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
