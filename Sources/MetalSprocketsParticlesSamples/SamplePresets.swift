import Foundation
import MetalSprocketsParticles

// Sample presets: JSON effect files in Resources/Presets, the same format as saved effects. index.json lists them in
// display order. A separate product from the library, so apps that do not want them do not ship them. Edit a preset by
// changing its file, or by building it in the demo and saving it over the file.

public extension ParticlePreset {
    /// The Presets folder in this target's resources.
    static let presetsFolder: URL = {
        guard let url = Bundle.module.url(forResource: "Presets", withExtension: nil) else {
            preconditionFailure("The Presets folder is missing from the MetalSprocketsParticlesSamples bundle.")
        }
        return url
    }()

    /// Every sample preset, in display order (index.json), loaded once.
    static let all: [ParticlePreset] = {
        do {
            return try presets(in: presetsFolder)
        } catch {
            preconditionFailure("Sample presets failed to load: \(error)")
        }
    }()

    /// The sample presets' file names, in display order.
    static let sampleSlugs: [String] = {
        guard let slugs = try? JSONDecoder().decode([String].self, from: Data(contentsOf: presetsFolder.appending(path: "index.json"))) else {
            preconditionFailure("Presets/index.json is missing or unreadable.")
        }
        return slugs
    }()

    /// A sample preset by name, ignoring case, spaces, and hyphens.
    static func named(_ name: String) -> ParticlePreset? {
        all.named(name)
    }

    private static func builtIn(_ name: String) -> ParticlePreset {
        guard let preset = named(name) else {
            preconditionFailure("No sample preset named \(name).")
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
    static var embersToAsh: ParticlePreset { builtIn("Embers to Ash") }
    static var awning: ParticlePreset { builtIn("Awning") }
    static var lantern: ParticlePreset { builtIn("Lantern") }
    static var dunk: ParticlePreset { builtIn("Dunk") }
    static var flare: ParticlePreset { builtIn("Flare") }
}
