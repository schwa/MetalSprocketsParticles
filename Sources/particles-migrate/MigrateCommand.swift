import ArgumentParser
import Foundation
import MetalSprocketsParticles

/// Rewrites effect files in the current format (#194): flat emitter settings become module stacks.
@main
struct MigrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "particles-migrate",
        abstract: "Rewrite effect files (.json or .particles packages) in the current format."
    )

    @Argument(help: "Effect files or packages. Folders that are not packages are searched for .json files.")
    var paths: [String]

    @Flag(help: "Only report which files would change.")
    var dryRun = false

    func run() throws {
        var changed = 0
        for url in try paths.flatMap(effects) {
            let system = try ParticleSystem(contentsOf: url)
            let json = url.pathExtension == ParticleSystem.packageExtension ? url.appending(path: ParticleSystem.packageJSONName) : url
            let before = try Data(contentsOf: json)
            guard try system.encoded().json != before else {
                continue
            }
            changed += 1
            print("\(dryRun ? "would migrate" : "migrated"): \(url.path)")
            if !dryRun {
                try system.write(to: url)
            }
        }
        print("\(changed) file(s) \(dryRun ? "need migrating" : "migrated").")
    }

    /// Effect files at `path`: the file or package itself, or effect JSON files in a folder.
    private func effects(_ path: String) throws -> [URL] {
        let url = URL(fileURLWithPath: path)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory, url.pathExtension != ParticleSystem.packageExtension else {
            return [url]
        }
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return contents.filter { $0.pathExtension == ParticleSystem.packageExtension || isEffectJSON($0) }.sorted { $0.path < $1.path }
    }

    private func isEffectJSON(_ url: URL) -> Bool {
        guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["layers"] != nil
    }
}
