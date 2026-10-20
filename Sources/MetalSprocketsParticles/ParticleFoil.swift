/// Shades particles like reflective metal foil (`ShadingModel.foil`, #175). Foil has no matte color of its own: it
/// reflects its surroundings (a sky band, a dark floor, a few soft bright patches, and the scene and particle lights) in
/// the particle's color, so a piece is dark when it reflects nothing and bright and saturated when it does. Sprites
/// shade per pixel with crinkled facets, so a card breaks into brighter and darker patches as it turns; mesh particles
/// shade per vertex unless `ShadingModule.perPixel` is on. For confetti, tinsel, and glitter. Use it with pieces that
/// turn: sprites with `ParticleOrientation.tumbling`, or mesh particles. A billboard always faces the camera, so it keeps
/// one brightness.
public struct ParticleFoil: Sendable, Equatable, Codable {
    /// How bright the reflected patches and lights are. 0 leaves only the sky and floor.
    public var glint: Float
    /// How tight the reflected lights are: higher flashes over a narrower range of angles.
    public var shininess: Float
    /// How much the color shifts with angle (thin-film rainbow). 0 keeps the particle's own color.
    public var iridescence: Float

    public init(glint: Float = 3, shininess: Float = 48, iridescence: Float = 0.5) {
        self.glint = glint
        self.shininess = shininess
        self.iridescence = iridescence
    }
}
