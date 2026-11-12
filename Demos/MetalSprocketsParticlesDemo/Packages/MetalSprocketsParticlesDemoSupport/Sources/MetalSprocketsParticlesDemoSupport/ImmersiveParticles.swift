#if os(visionOS)
import Metal
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsUI
import os
import simd
import SwiftUI

/// The effect shown in the immersive space. The window sets `system`; the render loop plays it, in stereo.
public final class ImmersiveParticlesStage: @unchecked Sendable {
    public static let shared = ImmersiveParticlesStage()

    /// The effect's origin in the space: 1.5 m in front of where the space opened, on the floor.
    let placement = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, -1.5, 1]))

    private struct State {
        var system: ParticleSystem = .fountain
        var generation = 0
        var player: ParticlePlayer?
        var playerGeneration = -1
        var lastTime: TimeInterval?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    public var system: ParticleSystem {
        get { state.withLockUnchecked { $0.system } }
        set {
            state.withLockUnchecked {
                $0.system = newValue
                $0.generation += 1
            }
        }
    }

    /// One frame: simulate once, then draw both eyes in one pass.
    func frame(_ context: ImmersiveContext) throws -> some Element {
        let (player, deltaTime) = try state.withLockUnchecked { state -> (ParticlePlayer, Float) in
            if state.player == nil {
                let player = try ParticlePlayer(system: state.system, device: context.device)
                // The compositor's depth runs from 1 (near) to 0 (far).
                player.runtime.reverseZ = true
                state.player = player
                state.playerGeneration = state.generation
            } else if state.playerGeneration != state.generation {
                try state.player?.update(state.system)
                state.playerGeneration = state.generation
            }
            let deltaTime = state.lastTime.map { Float(context.time - $0) } ?? 0
            state.lastTime = context.time
            // swiftlint:disable:next force_unwrapping
            return (state.player!, deltaTime)
        }
        let placement = placement
        let eyes = 0 ..< context.viewCount
        // Views of the effect's own space, so the effect sits at `placement` without moving its emitters.
        let views = ParticleStereoViews(
            viewMatrices: eyes.map { context.viewMatrix(eye: $0) * placement },
            projectionMatrices: eyes.map { context.projectionMatrix(eye: $0) },
            viewports: context.viewports
        )
        return try Group {
            try player.simulate(deltaTime: deltaTime, view: views.centerView)
            try ImmersiveRenderPass(context: context, label: "Particles") {
                try player.runtime.render(views: views)
            }
        }
    }
}

/// The immersive space's content: the shared stage's effect around the viewer.
public struct ImmersiveParticlesContent: ImmersiveSpaceContent {
    public static let spaceID = "Particles"

    public init() {}

    public var body: some ImmersiveSpaceContent {
        // Particles blend; foveation's coarse periphery shows as blocky edges on them.
        ImmersiveRenderContent(foveation: false) { context in
            try ImmersiveParticlesStage.shared.frame(context)
        }
    }
}

/// Opens or closes the immersive space, showing the current effect.
struct ImmersiveToggle: View {

    let system: ParticleSystem
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isImmersive = false
    @State private var isTransitioning = false

    var body: some View {
        Button(isImmersive ? "Exit Immersive" : "Enter Immersive", systemImage: "visionpro") {
            isTransitioning = true
            Task {
                if isImmersive {
                    await dismissImmersiveSpace()
                    isImmersive = false
                } else {
                    ImmersiveParticlesStage.shared.system = system
                    if case .opened = await openImmersiveSpace(id: ImmersiveParticlesContent.spaceID) {
                        isImmersive = true
                    }
                }
                isTransitioning = false
            }
        }
        .disabled(isTransitioning)
        .onChange(of: system.name) {
            if isImmersive {
                ImmersiveParticlesStage.shared.system = system
            }
        }
    }
}
#endif
