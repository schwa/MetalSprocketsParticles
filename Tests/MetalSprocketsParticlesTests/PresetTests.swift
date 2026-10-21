import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.requiresMetal4)
struct PresetLookupTests {
    @Test func namesAreUnique() {
        #expect(Set(ParticleSystem.all.map(\.name)).count == ParticleSystem.all.count)
    }

    @Test func lookupIgnoresCaseSpacesAndHyphens() {
        #expect(ParticleSystem.named("magic trail")?.name == "Magic Trail")
        #expect(ParticleSystem.named("MAGIC-TRAIL")?.name == "Magic Trail")
        #expect(ParticleSystem.named("nope") == nil)
    }

    @Test func animatedCollidersMoveOnlyWhenAsked() {
        let still = ParticleSystem("Still", layers: [], colliders: [.sphere(center: .zero, radius: 1)])
        var moving = still
        moving.animatesColliders = true
        #expect(still.colliders(at: 2) == still.colliders)
        #expect(moving.colliders(at: 2) != moving.colliders)
    }
}

@Suite(.requiresMetal4)
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

@Suite(.serialized, .requiresMetal4)
struct PresetRenderTests {
    @Test func loadReplacesEverything() throws {
        let system = try ParticleSystemRuntime(modules: [.standard], capacity: 10)
        system.colliders = [.sphere(center: .zero, radius: 3)]
        try system.load(.campfire)
        #expect(system.emitters.map(\.capacity) == ParticleSystem.campfire.layers.map(\.capacity))
        #expect(system.colliders == ParticleSystem.campfire.colliders)
        #expect(system.forceFields == ParticleSystem.campfire.forceFields)
        #expect(system.emitters[0].texture != nil)
    }

    /// Each preset is a showcase; a golden per preset catches regressions in how they look.
    @Test(arguments: ParticleSystem.all.map(\.name))
    func presetLooksTheSame(name: String) throws {
        let preset = try #require(ParticleSystem.named(name))
        let size = CGSize(width: 480, height: 270)
        let renderer = try OffscreenRenderer(size: size)
        let player = try ParticlePlayer(system: preset, device: renderer.device)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<180 {
            rendering = try renderer.render(try player.frame(deltaTime: 1.0 / 60.0, size: size))
        }
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        #expect(try #require(rendering).cgImage.matchesGolden(named: "preset-\(slug)"))
    }

    /// Wireframes only (no particles): colliders, every force-field kind, the goal trigger volume, and emitter shapes
    /// from Bumper, plus a cone, cylinder, and torus emitter.
    @Test func debugWireframesLookTheSame() throws {
        let size = CGSize(width: 640, height: 360)
        let renderer = try OffscreenRenderer(size: size)
        let system = try ParticleSystemRuntime(device: renderer.device, modules: [], capacity: 1, seed: 0)
        try system.load(.bumper)
        system.forceFields = [
            .wind(velocity: [1, 0, 0], strength: 1),
            .attractor(center: [1.8, 1, 0], strength: 1, radius: 0.5),
            .vortex(center: [0, 0.5, 0], strength: 1, radius: 1.5),
            .turbulence(strength: 1, scale: 1, speed: 1),
        ]
        let shapes = [
            EmitterModules.standard(position: [1.8, 2.5, 0], shape: .cone(radius: 0.3, height: 0.6)),
            EmitterModules.standard(position: [-1.8, 2.5, 0], shape: .cylinder(radius: 0.3, height: 0.6)),
            EmitterModules.standard(position: [0, 3.2, 0], shape: .torus(radius: 0.5, tubeRadius: 0.1)),
        ]
        try system.setEmitters(system.emitters.map { (modules: $0.modules, capacity: 10) } + shapes.map { (modules: $0, capacity: 10) })
        let view = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0]).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / size.height), near: 0.1, far: 100)
        let rendering = try renderer.render(RenderPass {
            try system.renderWireframes(projection: projection, view: view)
        })
        #expect(try rendering.cgImage.matchesGolden(named: "debug-wireframes"))
    }
}
