import AppKit
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import SwiftUI
import Testing

@Suite(.requiresMetal4)
struct TwoDModeTests {
    /// In 2D, new emitters start from the 2D defaults (points), and the scene saves as 2D (#141).
    @MainActor
    @Test func twoDModeAddsTwoDEmittersAndSaves() {
        let model = ParticlesDemoModel()
        model.is2D = true
        model.addEmitter()
        #expect(model.emitters.last?.settings == ParticleEmitter.default2D)
        #expect(model.currentEffect.is2D)
        model.is2D = false
        model.addEmitter()
        #expect(model.emitters.last?.settings != ParticleEmitter.default2D)
        #expect(!model.currentEffect.is2D)
    }

    /// The count overlay is centered, so its width must not follow the numbers, or the panel jumps around (#147).
    @MainActor
    @Test func particleCountOverlayKeepsItsWidth() {
        func width(alive: Int, births: Double, deaths: Double, finished: Bool = false) -> CGFloat {
            let view = ParticleCountView(alive: alive, capacity: 100_000, birthsPerSecond: births, deathsPerSecond: deaths, isFinished: finished)
            return NSHostingView(rootView: view).fittingSize.width
        }
        let reference = width(alive: 0, births: 0, deaths: 0)
        #expect(width(alive: 9_980, births: 3, deaths: 17) == reference)
        #expect(width(alive: 100_000, births: 12_345, deaths: 99_999) == reference)
        #expect(width(alive: 100_000, births: 0, deaths: 0, finished: true) == reference)
    }
}
