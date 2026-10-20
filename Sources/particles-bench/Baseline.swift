import ArgumentParser
import Foundation

// Baselines for the module refactor (#184): save results once, then compare each step against them.
struct BenchRow: Codable {
    var name: String
    /// Medians in milliseconds.
    var metrics: [String: Double]
}

struct BenchReport: Codable {
    var mode: String
    var rows: [BenchRow]
}

extension BenchCommand {
    func finish(_ report: BenchReport) throws {
        if let saveBaseline {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: saveBaseline))
            print("Saved baseline to \(saveBaseline)")
        }
        if let compare {
            let baseline = try JSONDecoder().decode(BenchReport.self, from: Data(contentsOf: URL(fileURLWithPath: compare)))
            guard baseline.mode == report.mode else {
                throw ValidationError("Baseline is for \(baseline.mode), these results are for \(report.mode).")
            }
            if !compareWithBaseline(report, baseline) {
                throw ExitCode.failure
            }
        }
    }

    /// Prints each metric against the baseline. Returns false when any metric is slower beyond tolerance and noise.
    private func compareWithBaseline(_ report: BenchReport, _ baseline: BenchReport) -> Bool {
        let baselineRows = Dictionary(baseline.rows.map { ($0.name, $0) }) { first, _ in first }
        var regressions: [String] = []
        print("")
        print("Compared with baseline (tolerance \(tolerance)%, noise floor \(noiseFloor) ms):")
        for row in report.rows {
            guard let old = baselineRows[row.name] else {
                print("  \(row.name): not in baseline")
                continue
            }
            var parts: [String] = []
            for key in row.metrics.keys.sorted() {
                guard let new = row.metrics[key], let previous = old.metrics[key], previous.isFinite, new.isFinite else {
                    continue
                }
                let change = previous > 0 ? (new - previous) / previous * 100 : 0
                let regressed = new - previous > noiseFloor && change > tolerance
                if regressed {
                    regressions.append("\(row.name) \(key)")
                }
                parts.append(String(format: "%@ %.3f→%.3f (%+.1f%%)%@", key, previous, new, change, regressed ? " SLOWER" : ""))
            }
            print("  \(row.name): \(parts.joined(separator: ", "))")
        }
        if regressions.isEmpty {
            print("No regressions.")
            return true
        }
        print("Regressions: \(regressions.joined(separator: "; "))")
        return false
    }
}
