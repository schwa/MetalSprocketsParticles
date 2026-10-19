import simd

/// Bursts one layer where another layer's particles hit a collider or die, through `ParticleSystemRuntime.recentEvents`.
/// Unlike sub-emitters it goes through the app, so the result can come from any layer and land anywhere; it is also
/// an example of reacting to events in app code. The source layer needs `reportsCollisions` or `reportsDeaths`.
public struct EventBurst: Sendable, Equatable, Codable {
    public enum Occasion: String, Sendable, Codable, CaseIterable {
        case collision
        case death
    }

    /// Index in `ParticleSystem.layers` whose events count.
    public var sourceLayer: Int
    public var occasion: Occasion
    /// Index in `ParticleSystem.layers` to burst.
    public var targetLayer: Int
    public var count: Int

    public init(sourceLayer: Int, occasion: Occasion, targetLayer: Int, count: Int) {
        self.sourceLayer = sourceLayer
        self.occasion = occasion
        self.targetLayer = targetLayer
        self.count = count
    }
}

extension ParticleSystemRuntime {
    /// Bursts for `recentEvents`, queued for the next step.
    func applyEventBursts(_ bursts: [EventBurst]) {
        for event in recentEvents {
            for burst in bursts where burst.sourceLayer == event.emitterIndex && emitters.indices.contains(burst.targetLayer) {
                let matches = switch (burst.occasion, event.kind) {
                case (.collision, .collision), (.death, .death): true
                default: false
                }
                if matches {
                    emitters[burst.targetLayer].burst(burst.count, at: event.position)
                }
            }
        }
    }
}
