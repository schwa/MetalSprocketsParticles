import MetalSprocketsParticles
import MetalSprocketsParticlesUI
import SwiftUI

/// Particles over ordinary SwiftUI content: a ParticleView with the overlay camera, where one world unit is one point
/// and y grows down the screen. The button fires confetti that bounces off it and lands on the window's bottom edge;
/// clicking anywhere else bursts sparkles there.
public struct OverlayDemoView: View {
    @State private var runtime: ParticleSystemRuntime?
    @State private var system = OverlayEffects.system
    @State private var viewSize: CGSize = .zero
    @State private var buttonFrame: CGRect = .zero

    /// The id of the demo app's window for this view.
    public static let windowID = "overlay"

    public init() {}

    public var body: some View {
        // The whole view is a surface you click anywhere, not a button.
        // swiftlint:disable:next accessibility_trait_for_button
        VStack(spacing: 20) {
            Text("2D Overlay")
                .font(.largeTitle.bold())
            Text("Click anywhere for sparkles.")
                .foregroundStyle(.secondary)
            Button("Celebrate", systemImage: "party.popper", action: celebrate)
                .controlSize(.extraLarge)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: { frame in
                    buttonFrame = frame
                    updateColliders()
                })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .accessibilityAddTraits(.allowsDirectInteraction)
        .onTapGesture(coordinateSpace: .named(Self.space)) { location in
            runtime?.emitters[OverlayEffects.sparkles].burst(40, at: [Float(location.x), Float(location.y), 0])
        }
        .overlay {
            if let runtime {
                ParticleView(runtime: runtime, system: system)
                    .camera(.overlay)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            viewSize = size
            updateColliders()
        }
        .task {
            let runtime = try? ParticleSystemRuntime(emitters: [], capacity: 1)
            try? runtime?.load(system)
            self.runtime = runtime
        }
    }

    // Read from a Sendable geometry closure, so not tied to the main actor.
    nonisolated private static let space = "overlay"

    private func celebrate() {
        // Just above the button, so the confetti starts outside its collider.
        runtime?.emitters[OverlayEffects.confetti].burst(300, at: [Float(buttonFrame.midX), Float(buttonFrame.minY) - 8, 0])
    }

    /// The window's edges keep particles on screen; the button is solid.
    private func updateColliders() {
        system.colliders = Collider.edges(of: viewSize) + (buttonFrame.isEmpty ? [] : [.box(frame: buttonFrame)])
    }
}

/// The overlay demo's effects, in points: y grows down the screen, so gravity is +y. Spread and speed variation are
/// speeds too (points per second), not fractions of the velocity, so they are in the hundreds here.
enum OverlayEffects {
    static let confetti = 0
    static let sparkles = 1

    static var system: ParticleSystem {
        var confetti = ParticleEmitter()
        confetti.shape = .point
        confetti.birthRate = 0
        confetti.velocity = [0, -900, 0]
        confetti.velocitySpread = 600
        confetti.speedVariation = 300
        confetti.gravity = [0, 1_400, 0]
        confetti.drag = 1.2
        confetti.lifetime = 3...4
        confetti.sizeOverLife = .constant(7)
        confetti.angleVariation = .pi
        confetti.angularSpeedVariation = 10
        confetti.colorOverLife = .constant([1, 0.3, 0.4, 1])
        confetti.colorVariation = [0.5, 0.2, 0, 0]
        confetti.restitution = 0.3
        confetti.friction = 0.6
        confetti.constrainsToPlane = true

        var sparkles = ParticleEmitter()
        sparkles.shape = .point
        sparkles.birthRate = 0
        sparkles.velocity = [0, -260, 0]
        sparkles.velocitySpread = 220
        sparkles.speedVariation = 120
        sparkles.gravity = [0, 250, 0]
        sparkles.drag = 2
        sparkles.lifetime = 0.4...0.9
        sparkles.sizeOverLife = .linear(from: 9, to: 0)
        sparkles.colorOverLife = .linear(from: [1, 0.95, 0.6, 1], to: [1, 0.5, 0.2, 1])
        sparkles.blendMode = .additive
        sparkles.constrainsToPlane = true

        return ParticleSystem("2D Overlay", layers: [
            ParticleSystem.Layer("Confetti", settings: confetti, sprite: .triangle, capacity: 3_000),
            ParticleSystem.Layer("Sparkles", settings: sparkles, sprite: .star, capacity: 2_000),
        ])
    }
}
