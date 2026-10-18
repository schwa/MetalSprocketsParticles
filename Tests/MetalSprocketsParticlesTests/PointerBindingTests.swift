import CoreGraphics
import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import Testing

/// Colliders, force fields, and emitters that follow the pointer, and turning a mouse location into a world position.
struct PointerBindingTests {
    let cameraToWorld = simd_float4x4(lookingFrom: [0, 2, 6], at: [0, 1, 0])
    let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 16.0 / 9.0, near: 0.1, far: 100)
    let size = CGSize(width: 1_600, height: 900)

    @Test func viewCenterProjectsToTheTarget() throws {
        let point = try #require(PointerProjection.worldPosition(
            of: CGPoint(x: 800, y: 450), in: size, projection: projection, cameraToWorld: cameraToWorld, planePoint: [0, 1, 0]
        ))
        #expect(simd_distance(point, [0, 1, 0]) < 1e-3)
    }

    @Test func offCenterPointsLieOnTheFacingPlaneOnTheRightSide() throws {
        let right = try #require(PointerProjection.worldPosition(
            of: CGPoint(x: 1_200, y: 450), in: size, projection: projection, cameraToWorld: cameraToWorld, planePoint: [0, 1, 0]
        ))
        let up = try #require(PointerProjection.worldPosition(
            of: CGPoint(x: 800, y: 100), in: size, projection: projection, cameraToWorld: cameraToWorld, planePoint: [0, 1, 0]
        ))
        let viewDirection = -cameraToWorld.columns.2.xyz
        #expect(abs(simd_dot(right - [0, 1, 0], viewDirection)) < 1e-3)
        #expect(right.x > 0.5)
        #expect(up.y > 1.5)
    }

    @Test func bindingsMoveOnlyWhatTheyName() {
        var preset = ParticlePreset("Pointer", layers: [
            ParticlePreset.Layer("A", settings: ParticleEmitter()),
            ParticlePreset.Layer("B", settings: ParticleEmitter()),
        ])
        preset.colliders = [.plane(normal: [0, 1, 0], distance: 0), .sphere(center: .zero, radius: 0.5), .capsule(start: [-1, 0, 0], end: [1, 0, 0], radius: 0.1)]
        preset.forceFields = [.attractor(center: .zero, strength: 3), .wind(velocity: [1, 0, 0], strength: 1), .vortex(center: .zero, strength: 2)]
        preset.pointerBindings = [.collider(1), .collider(2), .forceField(0), .forceField(1), .forceField(2), .emitter(1), .collider(99)]
        let pointer: SIMD3<Float> = [2, 3, 4]

        let colliders = preset.colliders(at: 0, pointer: pointer)
        #expect(colliders[0] == preset.colliders[0])
        #expect(colliders[1] == .sphere(center: pointer, radius: 0.5))
        #expect(colliders[2] == .capsule(start: [1, 3, 4], end: [3, 3, 4], radius: 0.1))

        let fields = preset.forceFields(at: 0, pointer: pointer)
        #expect(fields[0] == .attractor(center: pointer, strength: 3))
        #expect(fields[1] == preset.forceFields[1])
        #expect(fields[2] == .vortex(center: pointer, strength: 2))

        let transforms = preset.transforms(at: 0, pointer: pointer)
        #expect(transforms[0] == matrix_identity_float4x4)
        #expect(transforms[1].columns.3 == SIMD4(pointer, 1))
    }

    @Test func withoutLiveInputThePointerFollowsItsMotion() throws {
        var preset = ParticlePreset("Pointer", layers: [])
        preset.forceFields = [.attractor(center: .zero, strength: 3)]
        preset.pointerBindings = [.forceField(0)]
        preset.pointerMotion = EmitterMotion(kind: .circle, radius: 2, offset: [0, 1, 0])
        let start = preset.forceFields(at: 0)
        let later = preset.forceFields(at: 1)
        #expect(start != later)
        let decoded = try JSONDecoder().decode(ParticlePreset.self, from: try JSONEncoder().encode(preset))
        #expect(decoded.pointerBindings == preset.pointerBindings)
        #expect(decoded.forceFields(at: 1) == later)
    }
}
