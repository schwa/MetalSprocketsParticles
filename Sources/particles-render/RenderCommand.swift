import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
import MetalSprockets
import MetalSprocketsParticles
import simd
import UniformTypeIdentifiers

@main
struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "particles-render",
        abstract: "Simulate a particle preset offscreen and write the last frame as a PNG."
    )

    @Option(help: "Preset to render. See --list-presets.")
    var preset = "Fountain"

    @Flag(help: "List the preset names and exit.")
    var listPresets = false

    @Flag(help: "Draw collider wireframes.")
    var wireframes = false

    @Option(name: .shortAndLong, help: "Output PNG path.")
    var output = "particles.png"

    @Option(help: "Number of simulation steps to run before capturing.")
    var frames = 120

    @Option(help: "Seconds per simulation step.")
    var deltaTime: Float = 1.0 / 60.0

    @Option(help: "Random seed. The same seed and settings always produce the same image.")
    var seed: UInt32 = 0

    @Option(help: "Image width in pixels.")
    var width = 1280

    @Option(help: "Image height in pixels.")
    var height = 720

    @Option(help: "Camera position as x,y,z. Defaults to the preset's camera.")
    var eye: String?

    @Option(help: "Camera target as x,y,z. Defaults to the preset's camera.")
    var target: String?

    func run() throws {
        if listPresets {
            ParticlePreset.all.forEach { print($0.name) }
            return
        }
        guard let preset = ParticlePreset.named(self.preset) else {
            throw ValidationError("Unknown preset '\(self.preset)'. Presets: \(ParticlePreset.all.map(\.name).joined(separator: ", "))")
        }
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height))
        let system = try ParticleSystem(device: renderer.device, emitters: [], capacity: 1, seed: seed)
        try system.load(preset)
        let eye = try self.eye.map(parseVector) ?? preset.cameraEye
        let target = try self.target.map(parseVector) ?? preset.cameraTarget
        let camera = simd_float4x4(lookingFrom: eye, at: target)
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(width) / Float(height), near: 0.1, far: 100)

        var rendering: OffscreenRenderer.Rendering?
        for frame in 0..<max(frames, 1) {
            let time = Float(frame) * deltaTime
            rendering = try renderer.render(Group {
                try system.simulate(deltaTime: deltaTime, colliders: preset.colliders(at: time), transforms: preset.transforms(at: time))
                try RenderPass {
                    if wireframes {
                        try system.renderColliders(projection: projection, view: camera.inverse)
                    }
                    try system.render(projection: projection, view: camera.inverse)
                }
            })
        }
        guard let rendering else { return }
        try writePNG(try rendering.cgImage, to: URL(fileURLWithPath: output))
        print("Wrote \(output): \(preset.name) after \(frames) frames (last frame GPU \(rendering.gpuTime.map { String(format: "%.2f ms", $0 * 1000) } ?? "n/a"))")
    }

    private func parseVector(_ string: String) throws -> SIMD3<Float> {
        let parts = string.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3 else { throw ValidationError("Expected x,y,z but got '\(string)'") }
        return SIMD3(parts[0], parts[1], parts[2])
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
