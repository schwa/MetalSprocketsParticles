import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import SwiftMesh
import Testing

@Suite(.requiresMetal4)
struct EffectFileTests {
    /// Every built-in preset survives saving, files and all. Meshes come back triangulated, so they are compared by
    /// geometry.
    @Test(arguments: ParticleSystem.all.map(\.name))
    func presetRoundTrips(name: String) throws {
        let preset = try #require(ParticleSystem.named(name))
        let (json, files) = try preset.encoded()
        let decoded = try ParticleSystem(json: json, resources: EffectResources(files: files))
        #expect(decoded.name == preset.name)
        #expect(decoded.colliders == preset.colliders)
        #expect(decoded.forceFields == preset.forceFields)
        #expect(decoded.animatesColliders == preset.animatesColliders)
        #expect(decoded.cameraEye == preset.cameraEye && decoded.cameraTarget == preset.cameraTarget)
        #expect(decoded.layers.count == preset.layers.count)
        for (saved, original) in zip(decoded.layers, preset.layers) {
            var expected = original
            expected.mesh = nil
            var savedWithoutMesh = saved
            savedWithoutMesh.mesh = nil
            #expect(savedWithoutMesh == expected)
            #expect(saved.mesh?.positions == original.mesh?.positions)
            #expect(saved.mesh.map(triangles) == original.mesh.map(triangles))
        }
    }

    // MARK: Files next to the JSON (#169)

    /// A small effect with an emitter image, a color image, and a distance field: everything kept in files.
    func effectWithFiles() throws -> ParticleSystem {
        let image = try #require(ParticleSystem.named("Butterfly Dust")?.layers.first?.image)
        var settings = ParticleEmitter()
        settings.colorImage = ParticleColorImage(data: image.data, center: .zero, size: 2)
        var layer = EmitterDescription("Dust", settings: settings)
        layer.image = image
        let field = SignedDistanceField(origin: .zero, spacing: [1, 1, 1], resolution: [2, 2, 2], values: (0..<8).map(Float.init))
        return ParticleSystem("Files", layers: [layer], colliders: [.signedDistanceField(field)])
    }

    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "effect-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func dataIsSavedAsFilesNotInline() throws {
        let (json, files) = try effectWithFiles().encoded()
        let text = try #require(String(bytes: json, encoding: .utf8))
        // Two images (the same data, so one file) and one field.
        #expect(Set(files.keys.map { $0.components(separatedBy: "-").first ?? "" }) == ["emitter", "color", "field"])
        for name in files.keys {
            #expect(text.contains("\"\(name)\""), "\(name) is named in the JSON")
        }
        // No inline data: no long strings left in the JSON.
        // Odd pieces are inside quotes; even ones are JSON structure and indentation.
        let pieces = text.components(separatedBy: "\"")
        let longestString = stride(from: 1, to: pieces.count, by: 2).map { pieces[$0] }.max { $0.count < $1.count } ?? ""
        #expect(longestString.count < 200, "longest string \(longestString.prefix(300))")
        // Stable names: the same data saves under the same name.
        #expect(try Set(effectWithFiles().encoded().files.keys) == Set(files.keys))
    }

    @Test func packagesRoundTripOnDisk() throws {
        let effect = try effectWithFiles()
        let package = try temporaryFolder().appending(path: "Files.particles")
        try effect.write(to: package)
        let names = try FileManager.default.contentsOfDirectory(atPath: package.path)
        #expect(names.contains(ParticleSystem.packageJSONName))
        #expect(names.count == 1 + (try effect.encoded().files.count))
        let loaded = try ParticleSystem(contentsOf: package)
        #expect(loaded.layers.first?.image == effect.layers.first?.image)
        #expect(loaded.layers.first?.settings.colorImage == effect.layers.first?.settings.colorImage)
        #expect(loaded.colliders == effect.colliders)
        // A package file wrapper (for documents) reads back the same.
        #expect(try ParticleSystem(packageFileWrapper: effect.packageFileWrapper()).colliders == effect.colliders)
    }

    /// A plain JSON file keeps its files next to it, as the bundled presets do.
    @Test func jsonFilesKeepTheirFilesNextToThem() throws {
        let effect = try effectWithFiles()
        let url = try temporaryFolder().appending(path: "files.json")
        try effect.write(to: url)
        #expect(try ParticleSystem(contentsOf: url).colliders == effect.colliders)
    }

    /// Inline base64 (the old format), paths out of the folder, and missing files are errors, not crashes.
    @Test func badReferencesAreErrors() throws {
        let (json, files) = try effectWithFiles().encoded()
        let fieldName = try #require(files.keys.first { $0.hasPrefix("field") })
        func load(replacing name: String, with reference: String, files: [String: Data] = files) throws -> ParticleSystem {
            let text = try #require(String(bytes: json, encoding: .utf8)).replacingOccurrences(of: "\"\(name)\"", with: "\"\(reference)\"")
            return try ParticleSystem(json: Data(text.utf8), resources: EffectResources(files: files))
        }
        #expect(throws: EffectResourceError.self) { try load(replacing: fieldName, with: "AAAAAAAAgD8AAABA") }
        #expect(throws: EffectResourceError.self) { try load(replacing: fieldName, with: "../../secret.bin") }
        #expect(throws: EffectResourceError.self) { try load(replacing: fieldName, with: "gone.bin") }
        // No store at all.
        #expect(throws: EffectResourceError.self) { try JSONDecoder().decode(ParticleSystem.self, from: json) }
        #expect(throws: EffectResourceError.self) { try JSONEncoder().encode(effectWithFiles()) }
    }

    /// Absolute file URLs work too.
    @Test func fileURLReferencesLoad() throws {
        let (json, files) = try effectWithFiles().encoded()
        let folder = try temporaryFolder()
        for (name, data) in files {
            try data.write(to: folder.appending(path: name))
        }
        var text = try #require(String(bytes: json, encoding: .utf8))
        for name in files.keys {
            text = text.replacingOccurrences(of: "\"\(name)\"", with: "\"\(folder.appending(path: name).absoluteString)\"")
        }
        let loaded = try ParticleSystem(json: Data(text.utf8), resources: EffectResources())
        #expect(loaded.colliders == (try effectWithFiles()).colliders)
    }

    func triangles(_ mesh: Mesh) -> [[Int]] {
        mesh.triangulate().map { [Int($0.0.raw), Int($0.1.raw), Int($0.2.raw)] }
    }

    // MARK: Mesh files (#170)

    /// A layer's JSON with its mesh replaced by `obj`, decoded.
    func layer(withMesh obj: String, named name: String = "mesh.obj") throws -> EmitterDescription {
        let resources = EffectResources()
        var json = try #require(try JSONSerialization.jsonObject(with: resources.encoder().encode(ParticleSystem.teapot.layers[0])) as? [String: Any])
        json["mesh"] = name
        let store = EffectResources(files: [name: Data(obj.utf8)])
        return try store.decoder().decode(EmitterDescription.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func meshesAreSavedAsOBJFilesAndComeBackExactly() throws {
        let layer = ParticleSystem.teapot.layers[0]
        let resources = EffectResources()
        let json = try resources.encoder().encode(layer)
        let name = try #require(resources.files.keys.first)
        #expect(name.hasPrefix("mesh-") && name.hasSuffix(".obj"))
        let text = try #require(String(bytes: json, encoding: .utf8))
        #expect(!text.contains("meshPositions") && text.contains(name))
        let decoded = try resources.decoder().decode(EmitterDescription.self, from: json)
        #expect(decoded.mesh?.positions == layer.mesh?.positions)
        #expect(decoded.mesh.map(triangles) == layer.mesh.map(triangles))
    }

    @Test func outOfRangeMeshIndicesAreAnError() throws {
        #expect(throws: MeshFileError.self) { try layer(withMesh: "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 999999\n") }
        #expect(throws: MeshFileError.self) { try layer(withMesh: "v 0 0 0\n") }
    }

    /// Faces as polygons, with `v/vt/vn` forms and negative (from the end) indices, as other tools write them.
    @Test func objFilesFromOtherToolsLoad() throws {
        let obj = """
        # a quad and a triangle
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vt 0 0
        vn 0 0 1
        f 1/1/1 2/1/1 3/1/1 4/1/1
        f -4 -3 -1
        """
        let mesh = try #require(try layer(withMesh: obj).mesh)
        #expect(mesh.positions.count == 4)
        #expect(mesh.triangulate().count == 3)
    }

    /// Other formats Model I/O reads, such as PLY, load through it.
    @Test func plyFilesLoad() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0
        1 0 0
        0 1 0
        3 0 1 2

        """
        let mesh = try #require(try layer(withMesh: ply, named: "triangle.ply").mesh)
        #expect(mesh.triangulate().count == 1)
    }

    /// Inline meshes (the old format) are not read, per #169's decision for inline data.
    @Test func inlineMeshesAreAnError() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: EffectResources().encoder().encode(ParticleSystem.teapot.layers[0])) as? [String: Any])
        json["mesh"] = nil
        json["meshPositions"] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        json["meshTriangles"] = [[0, 1, 2]]
        #expect(throws: DecodingError.self) {
            try EffectResources().decoder().decode(EmitterDescription.self, from: JSONSerialization.data(withJSONObject: json))
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
        try ParticleSystem.fireworks.write(to: url)
        let loaded = try ParticleSystem(contentsOf: url)
        #expect(loaded.layers.map(\.settings) == ParticleSystem.fireworks.layers.map(\.settings))
    }
}
