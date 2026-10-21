import Foundation
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesShaders
import simd
import Testing

@Suite(.serialized, .requiresMetal4)
struct PointCacheTests {
    let runner: Runner

    init() throws {
        runner = try Runner()
    }

    let points: [EmitterPoint] = [
        EmitterPoint([1, 0, 0], normal: [0, 2, 0], color: [1, 0, 0, 1]),
        EmitterPoint([0, 3, 0]),
        EmitterPoint([0, 0, -2], normal: [0, 0, -1], color: [0, 0, 1, 0.5]),
    ]

    func spawn(_ points: [EmitterPoint], direction: ParticleBirthDirection = .velocity) throws -> [Particle] {
        var emitter = ParticleEmitter()
        emitter.shape = .points
        emitter.birthDirection = direction
        emitter.velocity = direction == .normal ? [0, 1, 0] : .zero
        emitter.velocitySpread = 0
        emitter.speedVariation = 0
        emitter.gravity = .zero
        emitter.lifetime = 10...10
        emitter.birthRate = 0
        var description = EmitterDescription("Points", settings: emitter, capacity: 256)
        description.points = points
        let system = try ParticleSystemRuntime(device: runner.device, capacity: 1, modules: .standard)
        try system.apply([description])
        system.burst(256)
        try runner.run(try system.simulate(deltaTime: 0))
        let pointer = system.buffer.contents().bindMemory(to: Particle.self, capacity: system.capacity)
        return (0..<system.capacity).map { pointer[$0] }
    }

    @Test func particlesAreBornOnTheCachedPoints() throws {
        let positions = Set(try spawn(points).map { SIMD3($0.position.x, $0.position.y, $0.position.z) })
        #expect(positions == Set(points.map(\.position)))
    }

    @Test func normalBirthDirectionUsesPointNormals() throws {
        for particle in try spawn(points, direction: .normal) {
            let position = SIMD3(particle.position.x, particle.position.y, particle.position.z)
            let velocity = SIMD3(particle.velocity.x, particle.velocity.y, particle.velocity.z)
            if position == [1, 0, 0] {
                #expect(simd_distance(velocity, [0, 1, 0]) < 1e-5)
            } else if position == [0, 0, -2] {
                #expect(simd_distance(velocity, [0, 0, -1]) < 1e-5)
            } else {
                // No normal: a random unit direction at the emitter's speed.
                #expect(abs(simd_length(velocity) - 1) < 1e-4)
            }
        }
    }

    @Test func pointColorsBecomeParticleTints() throws {
        for particle in try spawn(points) {
            let tint = particle.properties.w.bitPattern
            switch particle.position.x == 1 ? 0 : particle.position.z == -2 ? 2 : 1 {
            case 0: #expect(tint == 0xFF00_00FF) // RGBA8, red in the low byte.
            case 2: #expect(tint == 0x80FF_0000)
            default: #expect(tint == 0)
            }
        }
    }

    @Test func tintedParticlesRenderInTheirPointColor() throws {
        var emitter = ParticleEmitter()
        emitter.shape = .points
        emitter.colorOverLife = .constant([1, 1, 1, 1])
        emitter.sizeOverLife = .constant(2)
        emitter.velocity = .zero
        emitter.velocitySpread = 0
        emitter.gravity = .zero
        emitter.birthRate = 0
        emitter.lifetime = 10...10
        emitter.blendMode = .opaque
        var description = EmitterDescription("Points", settings: emitter, capacity: 16)
        description.points = [EmitterPoint([0, 0, 0], color: [0, 1, 0, 1])]
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, modules: .standard)
        try system.apply([description])
        system.burst(16)
        let view = simd_float4x4(lookingFrom: [0, 0, 4], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        let image = try renderer.render(Group {
            try system.simulate(deltaTime: 0)
            try RenderPass { try system.render(projection: projection, view: view) }
        }).cgImage
        let center = try image.rgbaPixels()[32 * 64 + 32]
        #expect(center.y > 230 && center.x < 20 && center.z < 20)
    }

    /// Points are saved as a PLY file (#177), exactly, including points without a normal or color.
    @Test func pointsRoundTripThroughEffectFiles() throws {
        var description = EmitterDescription("Points", settings: ParticleEmitter())
        description.points = points + [EmitterPoint([0.1, 0.2, 0.3], color: [0.25, 0.5, 0.75, 1])]
        let resources = EffectResources()
        let json = try resources.encoder().encode(description)
        let name = try #require(resources.files.keys.first)
        #expect(name.hasPrefix("points-") && name.hasSuffix(".ply"))
        #expect(String(bytes: json, encoding: .utf8)?.contains("\"\(name)\"") == true)
        let decoded = try EffectResources(files: resources.files).decoder().decode(EmitterDescription.self, from: json)
        #expect(decoded.points == description.points)
    }

    @Test func pointsWithoutNormalsOrColorsWriteOnlyPositions() throws {
        let data = try PointCacheFile.plyData(of: [EmitterPoint([1, 2, 3])])
        let end = try #require(data.range(of: Data("end_header".utf8)))
        let header = try #require(String(bytes: data[..<end.lowerBound], encoding: .ascii))
        #expect(!header.contains("nx") && !header.contains("red"))
        #expect(try PointCacheFile.points(from: data) == [EmitterPoint([1, 2, 3])])
    }

    /// Point clouds from other tools: ASCII, uchar colors (0 to 255), no alpha, extra properties.
    @Test func pointsFromOtherToolsLoad() throws {
        let text = """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property float intensity
        property uchar red
        property uchar green
        property uchar blue
        end_header
        1 2 3 0.5 255 0 51
        4 5 6 0.5 0 255 0

        """
        let points = try PointCacheFile.points(from: Data(text.utf8))
        #expect(points == [EmitterPoint([1, 2, 3], color: [1, 0, 0.2, 1]), EmitterPoint([4, 5, 6], color: [0, 1, 0, 1])])
    }

    @Test func plyWithoutPositionsIsAnError() throws {
        let text = "ply\nformat ascii 1.0\nelement vertex 1\nproperty float a\nend_header\n1\n"
        #expect(throws: PointCacheFileError.self) { try PointCacheFile.points(from: Data(text.utf8)) }
    }

    /// Inline points (the old format) are not read, per #169's decision for inline data.
    @Test func inlinePointsAreAnError() throws {
        var description = EmitterDescription("Points", settings: ParticleEmitter())
        description.points = points
        var json = try #require(try JSONSerialization.jsonObject(with: EffectResources().encoder().encode(description)) as? [String: Any])
        json["points"] = [["position": [0, 0, 0]]]
        #expect(throws: DecodingError.self) {
            try EffectResources().decoder().decode(EmitterDescription.self, from: JSONSerialization.data(withJSONObject: json))
        }
    }
}
