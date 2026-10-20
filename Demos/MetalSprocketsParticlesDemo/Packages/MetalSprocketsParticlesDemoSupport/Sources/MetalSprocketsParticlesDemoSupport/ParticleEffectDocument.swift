import MetalSprocketsParticles
import SwiftUI
import UniformTypeIdentifiers

/// A saved effect as a file document: a package (a folder holding effect.json and the files it names). Plain JSON
/// effects open too, when they name no files.
struct ParticleEffectDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.particleEffect, .json]
    static let writableContentTypes: [UTType] = [.particleEffect]

    var effect: ParticleSystem

    init(effect: ParticleSystem) {
        self.effect = effect
    }

    init(configuration: ReadConfiguration) throws {
        let wrapper = configuration.file
        if wrapper.isDirectory {
            effect = try ParticleSystem(packageFileWrapper: wrapper)
        } else {
            guard let json = wrapper.regularFileContents else {
                throw CocoaError(.fileReadCorruptFile)
            }
            effect = try ParticleSystem(json: json, resources: EffectResources())
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try effect.packageFileWrapper()
    }
}
