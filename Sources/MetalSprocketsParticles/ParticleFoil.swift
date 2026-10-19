/// Shades particles like metallic foil: each piece flashes when it turns to catch a light toward the camera, shifts
/// color with the viewing angle, and darkens edge-on. For confetti, tinsel, and glitter. Lights are the scene's lights
/// and particle lights; with none, a fixed light from above and in front. Use it with pieces that turn: sprites with
/// `ParticleOrientation.tumbling`, or mesh particles. A billboard always faces the camera, so its glint stays put.
public struct ParticleFoil: Sendable, Equatable, Codable {
    /// How bright the glint is, added on top of the color. 0 turns it off.
    public var glint: Float
    /// How tight the glint is: higher flashes over a narrower range of angles.
    public var shininess: Float
    /// How much the color shifts with angle (thin-film rainbow). 0 keeps the particle's own color.
    public var iridescence: Float

    public init(glint: Float = 3, shininess: Float = 48, iridescence: Float = 0.5) {
        self.glint = glint
        self.shininess = shininess
        self.iridescence = iridescence
    }
}
