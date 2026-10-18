import Foundation

public extension ParticlePreset {
    /// Loads every effect file in `folder`. If the folder has an `index.json` (an array of file names without the
    /// `.json` extension), presets come in that order and only those files load; otherwise every `.json` file loads,
    /// sorted by file name.
    static func presets(in folder: URL) throws -> [ParticlePreset] {
        let index = folder.appending(path: "index.json")
        let names: [String]
        if FileManager.default.fileExists(atPath: index.path) {
            names = try JSONDecoder().decode([String].self, from: Data(contentsOf: index))
        } else {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasSuffix(".json") }
                .map { String($0.dropLast(5)) }
                .sorted()
        }
        return try names.map { try ParticlePreset(contentsOf: folder.appending(path: "\($0).json")) }
    }
}
