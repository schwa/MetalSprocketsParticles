import AVFoundation
import Foundation
@testable import MetalSprocketsParticles
import Testing

@Suite(.serialized)
struct VideoExportTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("particles-\(UUID()).mov")
    }

    @Test func writesAMovieOfTheRequestedLengthAndSize() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var reported: [Double] = []
        try await ParticlePreset.fireworks.exportVideo(to: url, size: CGSize(width: 160, height: 90), frameRate: 30, duration: 1) { fraction in
            reported.append(fraction)
            return true
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 160, height: 90))
        #expect(abs(try await track.load(.nominalFrameRate) - 30) < 0.5)
        #expect(reported.count == 30 && reported.last == 1)
    }

    @Test func stoppingEarlyKeepsWhatWasWritten() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await ParticlePreset.rain.exportVideo(to: url, size: CGSize(width: 160, height: 90), frameRate: 30, duration: 2) { fraction in
            fraction < 0.25
        }
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(duration > 0.4 && duration < 0.7)
    }
}
