extension ParticleSystemRuntime {
    /// Records one frame's counts, keeping the last `particleRateWindow` frames.
    func recordParticleCounts(seconds: Float) {
        recentParticleCounts.append((seconds, bornParticleCount, diedParticleCount))
        if recentParticleCounts.count > Self.particleRateWindow {
            recentParticleCounts.removeFirst(recentParticleCounts.count - Self.particleRateWindow)
        }
    }

    var particleRates: (births: Double, deaths: Double) {
        let seconds = Double(recentParticleCounts.reduce(0) { $0 + $1.seconds })
        guard seconds > 0 else {
            return (0, 0)
        }
        let born = Double(recentParticleCounts.reduce(0) { $0 + $1.born })
        let died = Double(recentParticleCounts.reduce(0) { $0 + $1.died })
        return (born / seconds, died / seconds)
    }
}
