import AVFoundation
import Foundation
@testable import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
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
        try await ParticleSystem.fireworks.exportVideo(to: url, size: CGSize(width: 160, height: 90), frameRate: 30, duration: 1) { fraction in
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

    @Test func finiteEffectsCanEndTheMovie() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Flare's emission ends at 5 s and its longest-lived particles (smoke) last 3 s more.
        let written = try await ParticleSystem.flare.exportVideo(to: url, size: CGSize(width: 160, height: 90), duration: 20, stopWhenFinished: true)
        #expect(written > 7.5 && written < 8.5)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - written) < 0.05)
    }

    @Test func stoppingEarlyKeepsWhatWasWritten() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await ParticleSystem.rain.exportVideo(to: url, size: CGSize(width: 160, height: 90), frameRate: 30, duration: 2) { fraction in
            fraction < 0.25
        }
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(duration > 0.4 && duration < 0.7)
    }
}
