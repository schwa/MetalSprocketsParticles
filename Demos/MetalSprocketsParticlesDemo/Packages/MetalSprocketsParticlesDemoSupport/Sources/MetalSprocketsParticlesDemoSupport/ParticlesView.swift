import Interaction3D
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

public struct ParticlesView: View {
    @State private var system: ParticleSystem? = try? ParticleSystem(capacity: 200_000, emitter: .fountain)
    @State private var cameraMatrix = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0])
    @State private var frameTiming: FrameTimingStatistics?

    public init() {}

    public var body: some View {
        if let system {
            RenderView { context, size in
                let aspect = Float(size.width / max(size.height, 1))
                let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                try system.simulate(
                    deltaTime: context.frameUniforms.deltaTime,
                    colliders: ParticleEmitter.fountainColliders(time: context.frameUniforms.time)
                )
                try RenderPass {
                    try system.renderColliders(projection: projection, view: cameraMatrix.inverse)
                    try system.render(projection: projection, view: cameraMatrix.inverse)
                }
                .gpuTimed("Render")
            }
            .background(.black)
            .onFrameTimingChange { frameTiming = $0 }
            .interactiveCamera(cameraMatrix: $cameraMatrix, target: [0, 1.5, 0])
            .overlay(alignment: .topLeading) {
                if let frameTiming {
                    FrameTimingView(statistics: frameTiming, options: .all)
                        .padding()
                }
            }
        } else {
            Text("Failed to create particle system")
        }
    }
}
