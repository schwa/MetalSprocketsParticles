/// Draws an emitter's live particles as one ribbon, joined in birth order, instead of separate sprites
/// (`ParticleEmitter.ribbon`): a stream behind a moving emitter, a sword arc, a lightning bolt. Width is each particle's
/// size and color its color, so size and opacity over life shape the ribbon along its length. Works best with a fixed
/// lifetime, so particles die oldest first; a particle that dies early breaks the ribbon.
public struct ParticleRibbon: Sendable, Equatable, Codable {
    /// Narrows to a point at the oldest end.
    public var tapers: Bool

    public init(tapers: Bool = true) {
        self.tapers = tapers
    }
}
