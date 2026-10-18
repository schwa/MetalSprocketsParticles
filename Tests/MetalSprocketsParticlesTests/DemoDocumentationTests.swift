import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import Testing

/// Documentation/Demos has a clip, a poster, and a README section for every built-in preset, and nothing else.
/// Scripts/make-demos.sh regenerates them.
struct DemoDocumentationTests {
    let demos = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Documentation/Demos")

    func files(in folder: String, extension fileExtension: String) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: demos.appending(path: folder).path)
        return Set(names.filter { $0.hasSuffix(".\(fileExtension)") }.map { String($0.dropLast(fileExtension.count + 1)) })
    }

    @Test func everyPresetHasAClipAPosterAndASection() throws {
        let slugs = Set(ParticleSystem.sampleSlugs)
        #expect(try files(in: "videos", extension: "mp4") == slugs)
        #expect(try files(in: "posters", extension: "jpg") == slugs)
        let readme = try String(contentsOf: demos.appending(path: "README.md"), encoding: .utf8)
        for preset in ParticleSystem.all {
            #expect(readme.contains("\n## \(preset.name)\n"), "No README section for \(preset.name)")
        }
        let sections = readme.components(separatedBy: "\n## ").count - 1
        // One section per preset, plus Contents.
        #expect(sections == slugs.count + 1)
    }
}
