import AVFoundation
import CoreGraphics
import Foundation
import Metal
import MetalSprockets
import simd

public extension ParticleSystem {
    /// Simulates the effect from the start and writes it to a movie file, frame by frame, at `frameRate`. The camera
    /// defaults to the system's. Results are deterministic for a given `seed`. `progress` is called after each frame
    /// with the fraction done; return false from it to stop early and keep what was written. With `stopWhenFinished`,
    /// a finite effect (see `ParticleSystemRuntime.isFinished`) ends the movie early; `duration` is then the longest it runs.
    /// Returns the length written, in seconds.
    @discardableResult
    func exportVideo(
        to url: URL,
        size: CGSize = CGSize(width: 1_920, height: 1_080),
        frameRate: Double = 30,
        duration: TimeInterval = 5,
        seed: UInt32 = 0,
        eye: SIMD3<Float>? = nil,
        target: SIMD3<Float>? = nil,
        wireframes: Bool = false,
        codec: AVVideoCodecType = .h264,
        stopWhenFinished: Bool = false,
        debugView: ParticleDebugView = .none,
        progress: (Double) -> Bool = { _ in true }
    ) async throws -> TimeInterval {
        try? FileManager.default.removeItem(at: url)
        let renderer = try OffscreenVideoRenderer(
            size: size,
            frameRate: frameRate,
            outputURL: url,
            pixelFormat: ParticleSystemRuntime.colorPixelFormat,
            videoCodec: codec
        )
        // The renderer runs on the system default device; the particle system must use the same one.
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CocoaError(.featureUnsupported)
        }
        let player = try ParticlePlayer(system: self, device: device, seed: seed)
        player.camera = .lookAt(eye: eye ?? cameraEye, target: target ?? cameraTarget)
        player.runtime.debugView = debugView
        let deltaTime = Float(1 / frameRate)
        let frameCount = max(Int((duration * frameRate).rounded()), 1)
        var framesWritten = 0
        for frame in 0..<frameCount {
            try await renderer.render(try player.frame(deltaTime: deltaTime, size: size, wireframes: wireframes))
            framesWritten += 1
            if !progress(Double(frame + 1) / Double(frameCount)) || stopWhenFinished && player.runtime.isFinished {
                break
            }
        }
        try await renderer.finalize()
        return Double(framesWritten) / frameRate
    }
}
