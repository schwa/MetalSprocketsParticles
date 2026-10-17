import Interaction3D
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

public struct ParticlesView: View {
    @State private var model = ParticlesDemoModel()
    @State private var cameraMatrix = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0])
    @State private var frameTiming: FrameTimingStatistics?
    @State private var isInspectorPresented = true

    public init() {}

    public var body: some View {
        if let system = model.system {
            RenderView { context, size in
                let aspect = Float(size.width / max(size.height, 1))
                let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                try system.simulate(
                    deltaTime: context.frameUniforms.deltaTime,
                    colliders: model.animateColliders ? ParticleEmitter.fountainColliders(time: context.frameUniforms.time) : nil
                )
                try RenderPass {
                    if model.showColliders {
                        try system.renderColliders(projection: projection, view: cameraMatrix.inverse)
                    }
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
            .inspector(isPresented: $isInspectorPresented) {
                EmitterInspectorView(model: model)
                    .inspectorColumnWidth(min: 300, ideal: 340)
            }
            .toolbar {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    isInspectorPresented.toggle()
                }
            }
        } else {
            ContentUnavailableView("Failed to create particle system", systemImage: "exclamationmark.triangle")
        }
    }
}
