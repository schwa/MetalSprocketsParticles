import Metal
import MetalSprocketsParticlesShaders
import simd

/// The views to draw at once, e.g. the eyes of a visionOS immersive space: per view a view matrix, projection and
/// viewport. With two views, every particle draw is amplified into one vertex stream per view, each routed to its
/// viewport and render target array slice (a layered target), so a frame draws its particles once for both eyes.
///
/// Billboard axes, sorting, culling distance, and soft-particle depth use the center view (between the eyes, facing
/// the first eye's way), so both eyes see the same quads.
public struct ParticleStereoViews: Sendable {
    public var viewMatrices: [simd_float4x4]
    public var projectionMatrices: [simd_float4x4]
    public var viewports: [MTLViewport]

    /// One or two views, with equal counts of matrices and viewports.
    public init(viewMatrices: [simd_float4x4], projectionMatrices: [simd_float4x4], viewports: [MTLViewport]) {
        precondition((1 ... Int(PARTICLE_MAX_VIEW_COUNT)).contains(viewMatrices.count), "One or two views")
        precondition(projectionMatrices.count == viewMatrices.count && viewports.count == viewMatrices.count, "One projection and viewport per view")
        self.viewMatrices = viewMatrices
        self.projectionMatrices = projectionMatrices
        self.viewports = viewports
    }

    /// One view, drawn without amplification into the pass's own viewport.
    init(projection: simd_float4x4, view: simd_float4x4) {
        viewMatrices = [view]
        projectionMatrices = [projection]
        viewports = []
    }

    public var count: Int { viewMatrices.count }

    var isStereo: Bool { count > 1 }

    /// The view between the eyes: the first view's orientation at the average camera position. Pass it to
    /// `ParticleSystemRuntime.simulate(view:)` to sort for stereo.
    public var centerView: simd_float4x4 {
        guard isStereo else {
            return viewMatrices[0]
        }
        var cameraToWorld = viewMatrices[0].inverse
        let positions = viewMatrices.map(\.inverse.columns.3.xyz)
        cameraToWorld.columns.3 = SIMD4(positions.reduce(.zero, +) / Float(positions.count), 1)
        return cameraToWorld.inverse
    }

    var viewProjections: [simd_float4x4] {
        zip(projectionMatrices, viewMatrices).map { $0 * $1 }
    }

    /// The shaders' fixed-size per-view array: the second entry repeats the first for one view.
    var viewProjectionPair: (simd_float4x4, simd_float4x4) {
        let values = viewProjections
        return (values[0], values.count > 1 ? values[1] : values[0])
    }

    /// Amplifies the following draw into one stream per view, each to its own viewport and array slice. Draws reset
    /// amplification, so every draw calls this. Does nothing for one view.
    func configure(_ encoder: any MTL4RenderCommandEncoder) {
        guard isStereo else {
            return
        }
        let mappings = (0 ..< count).map { MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0)) }
        encoder.setVertexAmplificationCount(mappings)
        encoder.setViewports(viewports)
    }
}

extension WireframeUniforms {
    init(viewProjection: simd_float4x4, color: SIMD4<Float>) {
        self.init(viewProjections: (viewProjection, viewProjection), color: color)
    }
}
