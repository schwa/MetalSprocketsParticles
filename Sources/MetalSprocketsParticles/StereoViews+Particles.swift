import Metal
import MetalSprockets
import MetalSprocketsParticlesShaders
import simd

// Billboard axes, sorting, culling distance, and soft-particle depth use `centerViewMatrix`, so both eyes see the
// same quads.
extension StereoViews {
    /// One view, drawn without amplification into the pass's own viewport.
    init(projection: simd_float4x4, view: simd_float4x4) {
        self.init(viewMatrices: [view], projectionMatrices: [projection], viewports: [MTLViewport()])
    }

    /// The shaders' fixed-size per-view array: the second entry repeats the first for one view.
    var viewProjectionPair: (simd_float4x4, simd_float4x4) {
        let values = viewProjections
        return (values[0], values.count > 1 ? values[1] : values[0])
    }
}

extension WireframeUniforms {
    init(viewProjection: simd_float4x4, color: SIMD4<Float>) {
        self.init(viewProjections: (viewProjection, viewProjection), color: color)
    }
}
