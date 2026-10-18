import Foundation
import MetalSprocketsParticles

// Sample presets: JSON effect files in Resources/Presets, the same format as saved effects. index.json lists them in
// display order. A separate product from the library, so apps that do not want them do not ship them. Edit a preset by
// changing its file, or by building it in the demo and saving it over the file.

public extension ParticleSystem {
    /// The Presets folder in this target's resources.
    static let presetsFolder: URL = {
        guard let url = Bundle.module.url(forResource: "Presets", withExtension: nil) else {
            preconditionFailure("The Presets folder is missing from the MetalSprocketsParticlesSamples bundle.")
        }
        return url
    }()

    /// Every sample preset, in display order (index.json), loaded once.
    static let all: [ParticleSystem] = {
        do {
            return try systems(in: presetsFolder)
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
    static func named(_ name: String) -> ParticleSystem? {
        all.named(name)
    }

    private static func builtIn(_ name: String) -> ParticleSystem {
        guard let preset = named(name) else {
            preconditionFailure("No sample preset named \(name).")
        }
        return preset
    }

    static var fountain: ParticleSystem { builtIn("Fountain") }
    static var campfire: ParticleSystem { builtIn("Campfire") }
    static var fireworks: ParticleSystem { builtIn("Fireworks") }
    static var sparks: ParticleSystem { builtIn("Sparks") }
    static var snow: ParticleSystem { builtIn("Snow") }
    static var rain: ParticleSystem { builtIn("Rain") }
    static var magicTrail: ParticleSystem { builtIn("Magic Trail") }
    static var comet: ParticleSystem { builtIn("Comet") }
    static var galaxy: ParticleSystem { builtIn("Galaxy") }
    static var waterfall: ParticleSystem { builtIn("Waterfall") }
    static var confetti: ParticleSystem { builtIn("Confetti") }
    static var portal: ParticleSystem { builtIn("Portal") }
    static var hearts: ParticleSystem { builtIn("Hearts") }
    static var moonPhases: ParticleSystem { builtIn("Moon Phases") }
    static var colorSmoke: ParticleSystem { builtIn("Color Smoke") }
    static var fog: ParticleSystem { builtIn("Fog") }
    static var pond: ParticleSystem { builtIn("Pond") }
    static var ringOfFire: ParticleSystem { builtIn("Ring of Fire") }
    static var swarms: ParticleSystem { builtIn("Swarms") }
    static var geyser: ParticleSystem { builtIn("Geyser") }
    static var bumper: ParticleSystem { builtIn("Bumper") }
    static var paddleWheel: ParticleSystem { builtIn("Paddle Wheel") }
    static var teapot: ParticleSystem { builtIn("Teapot") }
    static var flag: ParticleSystem { builtIn("Flag") }
    static var strangeAttractor: ParticleSystem { builtIn("Strange Attractor") }
    static var pointerStir: ParticleSystem { builtIn("Pointer Stir") }
    static var embersToAsh: ParticleSystem { builtIn("Embers to Ash") }
    static var awning: ParticleSystem { builtIn("Awning") }
    static var lantern: ParticleSystem { builtIn("Lantern") }
    static var dunk: ParticleSystem { builtIn("Dunk") }
    static var flare: ParticleSystem { builtIn("Flare") }
}
