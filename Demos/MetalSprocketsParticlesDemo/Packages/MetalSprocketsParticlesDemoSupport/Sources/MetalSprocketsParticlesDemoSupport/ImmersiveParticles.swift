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
        var frameIndex = 0
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
                // The compositor treats pixels with no depth as empty.
                player.runtime.writesDepth = true
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
        // DIAGNOSTIC (#241): remove once immersive drawing works.
        let frameIndex = state.withLockUnchecked { state -> Int in
            state.frameIndex += 1
            return state.frameIndex
        }
        if frameIndex % 90 == 1 {
            let cameraPosition = context.viewMatrix(eye: 0).inverse.columns.3
            let clip = context.projectionMatrix(eye: 0) * context.viewMatrix(eye: 0) * placement * SIMD4<Float>(0, 0.5, 0, 1)
            print("[immersive] effect origin + 0.5 m up, eye 0 NDC: \(clip / clip.w)")
            print("[immersive] frame=\(frameIndex) t=\(context.time) dt=\(deltaTime) views=\(context.viewCount) viewports=\(context.viewports.map { "\($0.originX),\($0.originY) \($0.width)x\($0.height)" }) colorSlices=\(context.drawable.colorTextures[0].arrayLength) colorTextures=\(context.drawable.colorTextures.count) textureType=\(context.drawable.colorTextures[0].textureType.rawValue) alive=\(player.runtime.aliveParticleCount) state=\(player.runtime.state) system=\(player.system.name) camera=\(cameraPosition) color=\(context.drawable.colorTextures[0].pixelFormat.rawValue) depth=\(context.drawable.depthTextures[0].pixelFormat.rawValue)")
        }
        // Views of the effect's own space, so the effect sits at `placement` without moving its emitters.
        let views = StereoViews(
            viewMatrices: eyes.map { context.viewMatrix(eye: $0) * placement },
            projectionMatrices: eyes.map { context.projectionMatrix(eye: $0) },
            viewports: context.viewports
        )
        return try Group {
            try player.simulate(deltaTime: deltaTime, view: views.centerViewMatrix)
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
        // Foveation stays on: without it the compositor may pick its shared layout (both eyes side by side in one
        // texture), and the stereo draws route each eye to its own array slice, which a shared target lacks.
        ImmersiveRenderContent { context in
            do {
                return try ImmersiveParticlesStage.shared.frame(context)
            } catch {
                // DIAGNOSTIC (#241)
                print("[immersive] frame failed: \(error)")
                throw error
            }
        }
    }
}

/// Opens or closes the immersive space, showing the current effect.
struct ImmersiveToggle: View {

    let system: ParticleSystem
    @Binding var isImmersive: Bool
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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
