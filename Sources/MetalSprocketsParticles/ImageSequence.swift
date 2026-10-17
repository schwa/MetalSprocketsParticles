import MetalSprocketsParticlesShaders

/// A sprite sheet laid out left to right, top to bottom.
public struct ImageSequence: Sendable, Equatable {
    public var rows = 1
    public var columns = 1
    /// Frames used, counted from the top-left cell. Defaults to every cell.
    public var frameCount: Int
    public var frameRate: Float = 0
    public var frameRateVariation: Float = 0
    public var initialFrame: Float = 0
    public var initialFrameVariation: Float = 0
    public var mode: ParticleImageSequenceMode = .repeat

    public init(rows: Int = 1, columns: Int = 1, frameCount: Int? = nil, frameRate: Float = 0, mode: ParticleImageSequenceMode = .repeat) {
        self.rows = rows
        self.columns = columns
        self.frameCount = frameCount ?? rows * columns
        self.frameRate = frameRate
        self.mode = mode
    }
}
