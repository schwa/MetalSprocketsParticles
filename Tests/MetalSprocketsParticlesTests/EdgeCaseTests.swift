import CoreGraphics
import Foundation
import ImageIO
import Metal
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import Testing
import UniformTypeIdentifiers

/// Error messages, file formats, and other small paths that the larger suites do not reach (#180).
struct EdgeCaseTests {
    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "edge-cases-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func errorsDescribeWhatWentWrong() {
        let messages: [(any LocalizedError, String)] = [
            (ParticleSystemRuntimeError.tooManyParticles, "capacities"),
            (ParticleSystemRuntimeError.signedDistanceFieldTooLarge(resolution: [1, 2, 3]), "1×2×3"),
            (EffectResourceError.invalidReference("a/b"), "'a/b'"),
            (EffectResourceError.missing("x.png"), "'x.png'"),
            (EffectResourceError.noStore, "EffectResources"),
            (MeshFileError.unreadable, "could not be read"),
            (MeshFileError.indexOutOfRange, "out of range"),
            (MeshFileError.noMesh, "no faces"),
            (MeshFileError.unsupportedFormat("xyz"), "'xyz'"),
            (PointCacheFileError.noVertices, "vertex"),
            (PointCacheFileError.noPositions, "x, y, and z"),
            (PointCacheFileError.unreadable, "cannot be read"),
        ]
        for (error, expected) in messages {
            #expect(error.errorDescription?.contains(expected) == true, "\(error)")
        }
    }

    @Test func imageDataGetsAFileExtensionFromItsBytes() {
        #expect(Data([0x89, 0x50, 0x4E, 0x47]).imageFileExtension == "png")
        #expect(Data([0xFF, 0xD8, 0xFF, 0xE0]).imageFileExtension == "jpg")
        #expect(Data("GIF89a".utf8).imageFileExtension == "gif")
        #expect(Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]).imageFileExtension == "heic")
        #expect(Data([1, 2, 3]).imageFileExtension == "image")
    }

    @Test func aMissingFileInTheFolderIsAnError() throws {
        let resources = EffectResources(folder: try temporaryFolder())
        #expect(throws: EffectResourceError.self) { try resources.data(for: "nothing.png") }
    }

    @Test func badOBJFilesAreErrors() {
        #expect(throws: MeshFileError.unreadable) { try MeshFile.objMesh(from: Data([0xFF, 0xFE, 0xFD])) }
        #expect(throws: MeshFileError.unreadable) { try MeshFile.objMesh(from: Data("v 1 two 3\n".utf8)) }
        #expect(throws: MeshFileError.unreadable) { try MeshFile.objMesh(from: Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 x\n".utf8)) }
        #expect(throws: MeshFileError.unsupportedFormat("xyz")) { try MeshFile.mesh(from: Data(), fileExtension: "xyz") }
    }

    /// Blank lines are skipped.
    @Test func objBlankLinesAreIgnored() throws {
        let mesh = try MeshFile.objMesh(from: Data("v 0 0 0\n   \nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8))
        #expect(mesh.positions.count == 3)
    }

    @Test func plyWithoutVerticesIsAnError() {
        let text = "ply\nformat ascii 1.0\nelement face 0\nproperty list uchar int vertex_indices\nend_header\n"
        #expect(throws: PointCacheFileError.noVertices) { try PointCacheFile.points(from: Data(text.utf8)) }
    }

    @Test func plyWithAnUnreadableValueIsAnError() {
        let text = "ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1 two 3\n"
        #expect(throws: (any Error).self) { try PointCacheFile.points(from: Data(text.utf8)) }
    }

    /// Without index.json, every JSON file in the folder loads, sorted by file name.
    @Test func foldersWithoutAnIndexLoadEveryEffectByName() throws {
        let folder = try temporaryFolder()
        var second = ParticleSystem.sparks
        second.name = "Second"
        var first = ParticleSystem.fountain
        first.name = "First"
        try second.write(to: folder.appending(path: "b.json"))
        try first.write(to: folder.appending(path: "a.json"))
        try Data("not an effect".utf8).write(to: folder.appending(path: "notes.txt"))
        #expect(try ParticleSystem.systems(in: folder).map(\.name) == ["First", "Second"])
    }

    /// Each named accessor returns the preset it is named for.
    @Test func samplePresetAccessorsMatchTheirNames() {
        let accessors: [(ParticleSystem, String)] = [
            (.fountain, "Fountain"), (.campfire, "Campfire"), (.fireworks, "Fireworks"), (.sparks, "Sparks"), (.snow, "Snow"),
            (.rain, "Rain"), (.magicTrail, "Magic Trail"), (.comet, "Comet"), (.galaxy, "Galaxy"), (.waterfall, "Waterfall"),
            (.confetti, "Confetti"), (.portal, "Portal"), (.hearts, "Hearts"), (.moonPhases, "Moon Phases"),
            (.colorSmoke, "Color Smoke"), (.fog, "Fog"), (.pond, "Pond"), (.ringOfFire, "Ring of Fire"), (.swarms, "Swarms"),
            (.geyser, "Geyser"), (.bumper, "Bumper"), (.paddleWheel, "Paddle Wheel"), (.teapot, "Teapot"), (.flag, "Flag"),
            (.strangeAttractor, "Strange Attractor"), (.pointerStir, "Pointer Stir"), (.embersToAsh, "Embers to Ash"),
            (.awning, "Awning"), (.lantern, "Lantern"), (.dunk, "Dunk"), (.flare, "Flare"),
        ]
        for (preset, name) in accessors {
            #expect(preset.name == name)
        }
        #expect(ParticleSystem.sampleSlugs.count == ParticleSystem.all.count)
    }

    @Test func debugViewsHaveDistinctNames() {
        let names = ParticleDebugView.allCases.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// Sprite sheets play every cell once a second; single sprites have no sequence.
    @Test func spriteSheetsHaveADefaultImageSequence() throws {
        let moon = try #require(ParticleSprite.moonPhases.defaultImageSequence)
        #expect(moon.rows == 2 && moon.columns == 4 && moon.frameRate == 8)
        #expect(ParticleSprite.softDot.defaultImageSequence == nil)
        #expect(ParticleSprite.softDot.id == .softDot)
    }

    @Test func eventBurstsKeepTheirSettings() throws {
        let burst = EventBurst(sourceLayer: 1, occasion: .death, targetLayer: 2, count: 30)
        #expect(burst.sourceLayer == 1 && burst.occasion == .death && burst.targetLayer == 2 && burst.count == 30)
        #expect(try JSONDecoder().decode(EventBurst.self, from: JSONEncoder().encode(burst)) == burst)
    }

    /// A centered plane passes through the point and keeps its normal.
    @Test func planesCenterOnThePointer() {
        let plane = Collider.plane(normal: [0, 2, 0], distance: 0).centered(at: [5, 3, 1])
        guard case let .plane(normal, distance) = plane.shape else {
            Issue.record("Expected a plane")
            return
        }
        #expect(normal == [0, 2, 0] && distance == 3)
    }

    @Test func pointerBindingsWithAnUnknownKindAreAnError() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PointerBinding.self, from: Data(#"{"light": {"index": 0}}"#.utf8))
        }
    }

    @Test func pointerProjectionNeedsAViewAndAHit() {
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        let camera = simd_float4x4(lookingFrom: [0, 0, 5], at: .zero)
        let empty = PointerProjection.worldPosition(of: .zero, in: .zero, projection: projection, cameraToWorld: camera, planePoint: .zero)
        #expect(empty == nil)
        // The plane is behind the camera.
        let behind = PointerProjection.worldPosition(
            of: CGPoint(x: 50, y: 50), in: CGSize(width: 100, height: 100), projection: projection, cameraToWorld: camera, planePoint: [0, 0, 10]
        )
        #expect(behind == nil)
    }

    /// Translucent pixels come out of the texture with their colors not premultiplied; data that is not an image has
    /// no texture or aspect ratio.
    @Test(.requiresMetal4) func colorImagesUndoPremultipliedAlpha() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let context = try #require(CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))

        let image = ParticleColorImage(data: data as Data, center: .zero, size: 1)
        let texture = try #require(image.makeTexture(device: device))
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        #expect(pixel[0] > 250 && pixel[1] < 5 && (120...135).contains(pixel[3]))

        #expect(ParticleColorImage(data: Data([1, 2, 3]), center: .zero, size: 1).makeTexture(device: device) == nil)
        #expect(ParticleColorImage.aspectRatio(of: Data([1, 2, 3])) == nil)
    }
}
