import ArgumentParser
import CoreGraphics
import Foundation
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples

/// Whole-frame timings for each sample preset, played as the demo plays them (ParticlePlayer, scene depth and solid
/// colliders included). Run a release build for numbers that mean anything.
extension BenchCommand {
    struct PresetResult {
        var name: String
        /// Building the frame's element tree on the CPU: planning, uploads, collider meshes.
        var build: Double
        /// GPU time of the frame's command buffer.
        var gpu: Double
        /// Build plus encode, submit, and wait: what a frame costs end to end here.
        var frame: Double
        var worstFrame: Double
        var alive: Int
    }

    func runPresets() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: width, height: height))
        let systems = ParticleSystem.all.filter { preset.map($0.name.localizedCaseInsensitiveContains) ?? true }
        print("Preset               |   build ms |     GPU ms |   frame ms |   worst ms |  alive | budget \(String(format: "%.2f", budget)) ms")
        print("---------------------|------------|------------|------------|------------|--------|-------")
        var overBudget: [String] = []
        var rows: [BenchRow] = []
        for system in systems {
            let result = try measure(system, renderer: renderer)
            rows.append(BenchRow(name: system.name, metrics: ["build": result.build, "gpu": result.gpu, "frame": result.frame]))
            let status = result.frame <= budget ? "ok" : "OVER"
            if status == "OVER" {
                overBudget.append(system.name)
            }
            let name = system.name.padding(toLength: 20, withPad: " ", startingAt: 0)
            let columns = [result.build, result.gpu, result.frame, result.worstFrame].map { String(format: "%10.2f", $0) }
            print("\(name) | \(columns.joined(separator: " | ")) | \(String(format: "%6d", result.alive)) | \(status)")
        }
        try finish(BenchReport(mode: "presets", rows: rows))
        if !overBudget.isEmpty {
            print("Over budget: \(overBudget.joined(separator: ", "))")
            if check {
                throw ExitCode.failure
            }
        }
    }

    private func measure(_ system: ParticleSystem, renderer: OffscreenRenderer) throws -> PresetResult {
        let size = CGSize(width: width, height: height)
        let player = try ParticlePlayer(system: system, device: renderer.device)
        var build: [Double] = []
        var gpu: [Double] = []
        var frame: [Double] = []
        for index in 0..<(warmupFrames + frames) {
            let start = ContinuousClock.now
            let element = try player.frame(deltaTime: 1.0 / 60.0, size: size)
            let built = ContinuousClock.now
            let rendering = try renderer.render(element)
            let end = ContinuousClock.now
            guard index >= warmupFrames else {
                continue
            }
            build.append(Self.milliseconds(built - start))
            gpu.append((rendering.gpuTime ?? .nan) * 1_000)
            frame.append(Self.milliseconds(end - start))
        }
        return PresetResult(
            name: system.name,
            build: Self.median(build),
            gpu: Self.median(gpu),
            frame: Self.median(frame),
            worstFrame: frame.max() ?? .nan,
            alive: player.runtime.aliveParticleCount
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }
}
