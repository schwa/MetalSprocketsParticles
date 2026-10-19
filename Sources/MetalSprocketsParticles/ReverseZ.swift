import Metal
import simd

public extension ParticleSystemRuntime {
    /// `projection` with depth reversed: near maps to 1 and far to 0, for `reverseZ`. Works for any projection whose
    /// depth runs 0...1 in clip space, perspective or orthographic.
    static func reversingDepth(_ projection: simd_float4x4) -> simd_float4x4 {
        // Clip z becomes w - z, so NDC depth d becomes 1 - d.
        let flip = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, -1, 0], [0, 0, 1, 1]))
        return flip * projection
    }
}

extension ParticleSystemRuntime {
    /// Nearer passes the depth test: smaller depth in forward Z, larger in reverse Z.
    var depthCompareFunction: MTLCompareFunction {
        reverseZ ? .greater : .less
    }

    /// The depth of the far plane, and of empty scene depth: 1 in forward Z, 0 in reverse Z.
    var farDepth: Double {
        reverseZ ? 0 : 1
    }
}
