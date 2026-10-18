import AVFoundation
import CoreGraphics
import Foundation
import Metal
import MetalSprockets
import simd

public extension ParticlePreset {
    /// Simulates the effect from the start and writes it to a movie file, frame by frame, at `frameRate`. The camera
    /// defaults to the preset's. Results are deterministic for a given `seed`. `progress` is called after each frame
    /// with the fraction done; return false from it to stop early and keep what was written. With `stopWhenFinished`,
    /// a finite effect (see `ParticleSystem.isFinished`) ends the movie early; `duration` is then the longest it runs.
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
        progress: (Double) -> Bool = { _ in true }
    ) async throws -> TimeInterval {
        try? FileManager.default.removeItem(at: url)
        let renderer = try OffscreenVideoRenderer(
            size: size,
            frameRate: frameRate,
            outputURL: url,
            pixelFormat: ParticleSystem.colorPixelFormat,
            videoCodec: codec
        )
        // The renderer runs on the system default device; the particle system must use the same one.
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CocoaError(.featureUnsupported)
        }
        let system = try ParticleSystem(device: device, emitters: [], capacity: 1, seed: seed)
        try system.load(self)
        let camera = simd_float4x4(lookingFrom: eye ?? cameraEye, at: target ?? cameraTarget)
        let view = camera.inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: Float(size.width / max(size.height, 1)), near: 0.1, far: 100)
        let sceneDepth = drawsColliders ? try SceneDepth(device: device, width: Int(size.width), height: Int(size.height)) : nil
        let deltaTime = Float(1 / frameRate)
        let frameCount = max(Int((duration * frameRate).rounded()), 1)
        var framesWritten = 0
        for frame in 0..<frameCount {
            let time = Float(frame) * deltaTime
            try await renderer.render(Group {
                try system.simulate(
                    deltaTime: deltaTime,
                    colliders: colliders(at: time),
                    transforms: transforms(at: time),
                    trackedObjects: trackedObjectPositions(at: time),
                    view: view
                )
                try system.renderScene(projection: projection, view: view, sceneDepth: sceneDepth, wireframes: wireframes)
            })
            framesWritten += 1
            if !progress(Double(frame + 1) / Double(frameCount)) || stopWhenFinished && system.isFinished {
                break
            }
        }
        try await renderer.finalize()
        return Double(framesWritten) / frameRate
    }
}
