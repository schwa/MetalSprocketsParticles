import Foundation

// Built-in presets are JSON effect files in Resources/Presets, the same format as saved effects. index.json lists them
// in display order. Edit a preset by changing its file, or by building it in the demo and saving it over the file.

public extension ParticlePreset {
    /// Every built-in preset, in display order, loaded once from the package's resources.
    static let all: [ParticlePreset] = {
        do {
            return try builtInSlugs.map { slug in
                guard let url = Bundle.module.url(forResource: slug, withExtension: "json", subdirectory: "Presets") else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Presets/\(slug).json"])
                }
                return try ParticlePreset(contentsOf: url)
            }
        } catch {
            preconditionFailure("Built-in presets failed to load: \(error)")
        }
    }()

    /// The built-in presets' file names, in display order, from Presets/index.json.
    internal static let builtInSlugs: [String] = {
        guard let index = Bundle.module.url(forResource: "index", withExtension: "json", subdirectory: "Presets"),
              let slugs = try? JSONDecoder().decode([String].self, from: Data(contentsOf: index)) else {
            preconditionFailure("Presets/index.json is missing or unreadable in the MetalSprocketsParticles bundle.")
        }
        return slugs
    }()

    /// A built-in preset by name.
    private static func builtIn(_ name: String) -> ParticlePreset {
        guard let preset = named(name) else {
            preconditionFailure("No built-in preset named \(name).")
        }
        return preset
    }

    static var fountain: ParticlePreset { builtIn("Fountain") }
    static var campfire: ParticlePreset { builtIn("Campfire") }
    static var fireworks: ParticlePreset { builtIn("Fireworks") }
    static var sparks: ParticlePreset { builtIn("Sparks") }
    static var snow: ParticlePreset { builtIn("Snow") }
    static var rain: ParticlePreset { builtIn("Rain") }
    static var magicTrail: ParticlePreset { builtIn("Magic Trail") }
    static var comet: ParticlePreset { builtIn("Comet") }
    static var galaxy: ParticlePreset { builtIn("Galaxy") }
    static var waterfall: ParticlePreset { builtIn("Waterfall") }
    static var confetti: ParticlePreset { builtIn("Confetti") }
    static var portal: ParticlePreset { builtIn("Portal") }
    static var hearts: ParticlePreset { builtIn("Hearts") }
    static var moonPhases: ParticlePreset { builtIn("Moon Phases") }
    static var colorSmoke: ParticlePreset { builtIn("Color Smoke") }
    static var fog: ParticlePreset { builtIn("Fog") }
    static var pond: ParticlePreset { builtIn("Pond") }
    static var ringOfFire: ParticlePreset { builtIn("Ring of Fire") }
    static var swarms: ParticlePreset { builtIn("Swarms") }
    static var geyser: ParticlePreset { builtIn("Geyser") }
    static var bumper: ParticlePreset { builtIn("Bumper") }
    static var paddleWheel: ParticlePreset { builtIn("Paddle Wheel") }
    static var teapot: ParticlePreset { builtIn("Teapot") }
    static var flag: ParticlePreset { builtIn("Flag") }
    static var strangeAttractor: ParticlePreset { builtIn("Strange Attractor") }
    static var pointerStir: ParticlePreset { builtIn("Pointer Stir") }
    static var awning: ParticlePreset { builtIn("Awning") }
    static var lantern: ParticlePreset { builtIn("Lantern") }
    static var dunk: ParticlePreset { builtIn("Dunk") }
    static var flare: ParticlePreset { builtIn("Flare") }
}
