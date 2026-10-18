import ArgumentParser
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import simd
import UniformTypeIdentifiers

@main
struct RenderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "particles-render",
        abstract: "Simulate a particle preset offscreen and write the last frame as a PNG, or the whole run as a movie."
    )

    @Option(help: "Write a movie (.mov or .mp4) of the effect from the start instead of a PNG. Uses --duration and --fps.")
    var video: String?

    @Option(help: "Movie length in seconds (the longest, with --until-finished).")
    var duration: Double = 5

    @Flag(help: "End the movie when a finite effect has finished (emission over, every particle dead).")
    var untilFinished = false

    @Option(help: "Movie frames per second; each frame is one simulation step.")
    var fps: Double = 30

    @Option(help: "Preset to render, from --presets. See --list-presets.")
    var preset = "Fountain"

    @Option(help: "Folder of effect files to choose --preset from, instead of the sample presets.")
    var presets: String?

    @Option(help: "Render a saved effect (JSON) instead of a preset.")
    var effect: String?

    @Option(help: "Write the effect as JSON to this path and exit.")
    var saveEffect: String?

    @Flag(help: "List the preset names and exit.")
    var listPresets = false

    @Flag(help: "Draw wireframes for colliders, force fields, trigger volumes, and emitter shapes.")
    var wireframes = false

    @Flag(help: "Turn off back-to-front sorting, to compare against the sorted render.")
    var noSort = false

    @Option(name: .shortAndLong, help: "Output PNG path.")
    var output = "particles.png"

    @Option(help: "Number of simulation steps to run before capturing.")
    var frames = 120

    @Option(help: "Seconds per simulation step.")
    var deltaTime: Float = 1.0 / 60.0

    @Option(help: "Random seed. The same seed and settings always produce the same image.")
    var seed: UInt32 = 0

    @Option(help: "Image width in pixels.")
    var width = 1_280

    @Option(help: "Image height in pixels.")
    var height = 720

    @Option(help: "Camera position as x,y,z. Defaults to the preset's camera.")
    var eye: String?

    @Option(help: "Camera target as x,y,z. Defaults to the preset's camera.")
    var target: String?

    func run() async throws {
        let available = try presets.map { try ParticleSystem.systems(in: URL(fileURLWithPath: $0)) } ?? ParticleSystem.all
        if listPresets {
            available.forEach { print($0.name) }
            return
        }
        var preset: ParticleSystem
        if let effect {
            preset = try ParticleSystem(contentsOf: URL(fileURLWithPath: effect))
        } else if let found = available.named(self.preset) {
            preset = found
        } else {
            throw ValidationError("Unknown preset '\(self.preset)'. Presets: \(available.map(\.name).joined(separator: ", "))")
        }
        if noSort {
            for index in preset.layers.indices {
                preset.layers[index].settings.sortMode = .none
            }
        }
        if let saveEffect {
            try preset.write(to: URL(fileURLWithPath: saveEffect))
            print("Wrote \(saveEffect): \(preset.name)")
            return
        }
        let eye = try self.eye.map(parseVector) ?? preset.cameraEye
        let target = try self.target.map(parseVector) ?? preset.cameraTarget
        if let video {
            let url = URL(fileURLWithPath: video)
            let codec: AVVideoCodecType = .h264
            var lastReported = -1
            let written = try await preset.exportVideo(
                to: url,
                size: CGSize(width: width, height: height),
                frameRate: fps,
                duration: duration,
                seed: seed,
                eye: eye,
                target: target,
                wireframes: wireframes,
                codec: codec,
                stopWhenFinished: untilFinished
            ) { fraction in
                let percent = Int(fraction * 100)
                if percent / 10 != lastReported / 10 {
                    lastReported = percent
                    print("\(percent)%")
                }
                return true
            }
            print("Wrote \(video): \(preset.name), \(String(format: "%.2f", written)) s at \(fps) fps, \(width)×\(height)")
            return
        }
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height))
        let player = try ParticlePlayer(system: preset, device: renderer.device, seed: seed)
        player.camera = .lookAt(eye: eye, target: target)
        let size = CGSize(width: width, height: height)
        var rendering: OffscreenRenderer.Rendering?
        for _ in 0..<max(frames, 1) {
            rendering = try renderer.render(try player.frame(deltaTime: deltaTime, size: size, wireframes: wireframes))
        }
        guard let rendering else { return }
        try writePNG(try rendering.cgImage, to: URL(fileURLWithPath: output))
        print("Wrote \(output): \(preset.name) after \(frames) frames (last frame GPU \(rendering.gpuTime.map { String(format: "%.2f ms", $0 * 1_000) } ?? "n/a"))")
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
