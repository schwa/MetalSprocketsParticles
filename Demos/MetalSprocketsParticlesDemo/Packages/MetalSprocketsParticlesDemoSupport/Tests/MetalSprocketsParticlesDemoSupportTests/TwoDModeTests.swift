import AppKit
import MetalSprocketsParticles
@testable import MetalSprocketsParticlesDemoSupport
import SwiftUI
import Testing

@Suite(.requiresMetal4)
struct TwoDModeTests {
    /// 2D saves with the scene (#141). The view is in the scene's own units (#154), so new emitters are the same in
    /// both modes, not the points-based 2D defaults.
    @MainActor
    @Test func twoDModeSavesAndAddsSceneEmitters() {
        let model = ParticlesDemoModel()
        model.is2D = true
        model.addEmitter()
        let flatEmitter = model.emitters.last?.settings
        #expect(flatEmitter != ParticleEmitter.default2D)
        #expect(model.currentEffect.is2D)
        model.is2D = false
        model.addEmitter()
        #expect(model.emitters.last?.settings == flatEmitter)
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
