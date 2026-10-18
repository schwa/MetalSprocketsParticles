import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

struct PresetLookupTests {
    @Test func namesAreUnique() {
        #expect(Set(ParticlePreset.all.map(\.name)).count == ParticlePreset.all.count)
    }

    @Test func lookupIgnoresCaseSpacesAndHyphens() {
        #expect(ParticlePreset.named("magic trail")?.name == "Magic Trail")
        #expect(ParticlePreset.named("MAGIC-TRAIL")?.name == "Magic Trail")
        #expect(ParticlePreset.named("nope") == nil)
    }

    @Test func animatedCollidersMoveOnlyWhenAsked() {
        let still = ParticlePreset("Still", layers: [], colliders: [.sphere(center: .zero, radius: 1)])
        var moving = still
        moving.animatesColliders = true
        #expect(still.colliders(at: 2) == still.colliders)
        #expect(moving.colliders(at: 2) != moving.colliders)
    }
}

struct SpriteAndMotionTests {
    @Test func everySpriteExceptSoftDotBuilds() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        for sprite in ParticleSprite.allCases {
            #expect((sprite.makeTexture(device: device) == nil) == (sprite == .softDot))
        }
        let sheet = try #require(ParticleSprite.colorSheet.makeTexture(device: device))
        #expect(sheet.width == 128 && sheet.height == 128)
    }

    @Test func stillMotionIsIdentityPlusOffset() {
        let motion = EmitterMotion(offset: [1, 2, 3])
        #expect(motion.transform(time: 5).columns.3 == [1, 2, 3, 1])
    }

    @Test func circleStaysOnRadius() {
        let translation = EmitterMotion(kind: .circle, radius: 2, speed: 1).transform(time: 0.7).columns.3
        #expect(abs(simd_length(SIMD2(translation.x, translation.z)) - 2) < 1e-5)
    }

    @Test func yawTurnsAroundY() {
        let transform = EmitterMotion(yaw: .pi / 2).transform(time: 0)
        let turned = transform * SIMD4<Float>(1, 0, 0, 0)
        #expect(simd_distance(SIMD3(turned.x, turned.y, turned.z), [0, 0, -1]) < 1e-5)
    }

    @Test func colliderAnimationLeavesPlanes() {
        let plane = Collider.plane(normal: [0, 1, 0], distance: 0)
        let sphere = Collider.sphere(center: .zero, radius: 1)
        #expect(plane.animated(time: 1, index: 0) == plane)
        #expect(sphere.animated(time: 1, index: 0) != sphere)
    }
}

@Suite(.serialized)
struct PresetRenderTests {
    @Test func loadReplacesEverything() throws {
        let system = try ParticleSystem(emitters: [ParticleEmitter()], capacity: 10)
        system.colliders = [.sphere(center: .zero, radius: 3)]
        try system.load(.campfire)
        #expect(system.emitters.map(\.capacity) == ParticlePreset.campfire.layers.map(\.capacity))
        #expect(system.colliders == ParticlePreset.campfire.colliders)
        #expect(system.forceFields == ParticlePreset.campfire.forceFields)
        #expect(system.emitters[0].texture != nil)
    }

    /// Each preset is a showcase; a golden per preset catches regressions in how they look.
    @Test(arguments: ParticlePreset.all.map(\.name))
    func presetLooksTheSame(name: String) throws {
        let preset = try #require(ParticlePreset.named(name))
        let size = CGSize(width: 480, height: 270)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, emitters: [], capacity: 1, seed: 0)
        try system.load(preset)
        let view = simd_float4x4(lookingFrom: preset.cameraEye, at: preset.cameraTarget).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        var rendering: OffscreenRenderer.Rendering?
        for frame in 0..<180 {
            let time = Float(frame) / 60
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: 1.0 / 60.0, colliders: preset.colliders(at: time), transforms: preset.transforms(at: time), view: view)
                try RenderPass { try system.render(projection: projection, view: view) }
            })
        }
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        #expect(try #require(rendering).cgImage.matchesGolden(named: "preset-\(slug)"))
    }

    /// Wireframes only (no particles): colliders, every force-field kind, the goal trigger volume, and emitter shapes
    /// from Bumper, plus a cone, cylinder, and torus emitter.
    @Test func debugWireframesLookTheSame() throws {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystem(device: renderer.device, emitters: [], capacity: 1, seed: 0)
        try system.load(.bumper)
        system.forceFields = [
            .wind(velocity: [1, 0, 0], strength: 1),
            .attractor(center: [1.8, 1, 0], strength: 1, radius: 0.5),
            .vortex(center: [0, 0.5, 0], strength: 1, radius: 1.5),
            .turbulence(strength: 1, scale: 1, speed: 1),
        ]
        var shapes = [ParticleEmitter(), ParticleEmitter(), ParticleEmitter()]
        shapes[0].shape = .cone(radius: 0.3, height: 0.6)
        shapes[0].position = [1.8, 2.5, 0]
        shapes[1].shape = .cylinder(radius: 0.3, height: 0.6)
        shapes[1].position = [-1.8, 2.5, 0]
        shapes[2].shape = .torus(radius: 0.5, tubeRadius: 0.1)
        shapes[2].position = [0, 3.2, 0]
        try system.setEmitters(system.emitters.map { ($0.settings, 10) } + shapes.map { ($0, 10) })
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        let rendering = try renderer.render(RenderPass {
            try system.renderWireframes(projection: projection, view: view)
        })
        #expect(try rendering.cgImage.matchesGolden(named: "debug-wireframes"))
    }
}
