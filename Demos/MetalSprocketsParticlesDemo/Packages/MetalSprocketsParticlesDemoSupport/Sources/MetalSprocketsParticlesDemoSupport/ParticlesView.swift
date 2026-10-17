import Interaction3D
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsUI
import simd
import SwiftUI

public struct ParticlesView: View {
    @State private var system: ParticleSystem? = {
        var emitter = ParticleEmitter()
        emitter.position = [0, 0.5, 0]
        emitter.velocity = [0, 5, 0]
        emitter.colliders = [
            .plane(normal: [0, 1, 0], distance: 0),
            .sphere(center: [0, 2.5, 0], radius: 0.6),
            .box(center: [1.2, 0.5, 0], halfExtents: [0.3, 0.5, 0.3]),
            .box(center: [-1.2, 0.25, 0.4], halfExtents: [0.4, 0.25, 0.4]),
        ]
        return try? ParticleSystem(capacity: 200_000, emitter: emitter)
    }()

    @State private var cameraMatrix = simd_float4x4(lookingFrom: [0, 3, 6], at: [0, 1.5, 0])
    @State private var frameTiming: FrameTimingStatistics?

    public init() {}

    public var body: some View {
        if let system {
            RenderView { context, size in
                let time = context.frameUniforms.time
                let aspect = Float(size.width / max(size.height, 1))
                let view = cameraMatrix.inverse
                let projection = perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
                try system.simulate(time: time, deltaTime: context.frameUniforms.deltaTime)
                try RenderPass {
                    try system.render(projection: projection, view: view)
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

extension simd_float4x4 {
    // Camera-to-world matrix.
    init(lookingFrom eye: SIMD3<Float>, at target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        self.init(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(eye, 1)))
    }
}

func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let y = 1 / tan(fovY / 2)
    let x = y / aspect
    let z = far / (near - far)
    return simd_float4x4(columns: (
        [x, 0, 0, 0],
        [0, y, 0, 0],
        [0, 0, z, -1],
        [0, 0, z * near, 0]
    ))
}
