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

    /// Matches OffscreenRenderer, so golden images and particles-render show what the app shows.
    static let colorPixelFormat = ParticleSystem.colorPixelFormat

    public init() {}

    public var body: some View {
        if let system = model.system {
            RenderView(colorPixelFormat: Self.colorPixelFormat) { context, size in
                let aspect = Float(size.width / max(size.height, 1))
                let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                try system.simulate(
                    deltaTime: context.frameUniforms.deltaTime,
                    colliders: model.frameColliders(time: context.frameUniforms.time),
                    transforms: model.frameTransforms(time: context.frameUniforms.time),
                    view: cameraMatrix.inverse
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
            .interactiveCamera(cameraMatrix: $cameraMatrix, target: model.cameraTarget)
            .onChange(of: model.presetName) {
                cameraMatrix = simd_float4x4(lookingFrom: model.cameraEye, at: model.cameraTarget)
            }
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
