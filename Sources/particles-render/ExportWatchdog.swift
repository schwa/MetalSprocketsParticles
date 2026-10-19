import Foundation

/// Exits the process when export makes no progress for `stallSeconds`, after writing a `sample` of the stuck process to
/// the temporary directory so the hang can be diagnosed (#102).
final class ExportWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastProgress = Date()
    private let timer: DispatchSourceTimer

    init(stallSeconds: TimeInterval) {
        timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let stalled = lock.withLock { Date().timeIntervalSince(lastProgress) > stallSeconds }
            if stalled {
                Self.sampleAndExit(after: stallSeconds)
            }
        }
        timer.resume()
    }

    func progressed() {
        lock.withLock { lastProgress = Date() }
    }

    func stop() {
        timer.cancel()
    }

    private static func sampleAndExit(after seconds: TimeInterval) -> Never {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("particles-render-hang-\(pid).txt").path
        let sample = Process()
        sample.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        sample.arguments = ["\(pid)", "3", "-file", path]
        try? sample.run()
        sample.waitUntilExit()
        FileHandle.standardError.write(Data("error: video export made no progress for \(Int(seconds)) s; sample written to \(path)\n".utf8))
        exit(2)
    }
}
