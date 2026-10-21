import simd

/// Distance LOD and view culling, using the camera from the last `render` call (one frame behind, which is fine for
/// both). Before the first render nothing is culled or scaled.
struct CullingCamera {
    var position: SIMD3<Float>
    var viewProjection: simd_float4x4
}

extension ParticleSystemRuntime.Emitter {
    /// The birth rate multiplier for distance LOD; 1 when off or without a camera.
    func lodRateScale(camera: CullingCamera?) -> Float {
        let lod = resolved.levelOfDetail
        let near = lod.near
        let far = lod.far
        guard let camera, far > near else {
            return 1
        }
        let fraction = simd_clamp((simd_distance(worldCenter, camera.position) - near) / (far - near), 0, 1)
        return simd_mix(1, max(lod.farRateScale, 0), fraction)
    }

    /// Whether the emitter's culling sphere is entirely outside the view.
    func isOutsideView(camera: CullingCamera?) -> Bool {
        let radius = resolved.levelOfDetail.cullingRadius
        guard let camera, radius > 0 else {
            return false
        }
        return !Self.sphereIntersectsFrustum(center: worldCenter, radius: radius, viewProjection: camera.viewProjection)
    }

    /// Tests against the six planes of the clip volume (Metal depth 0...1), taken from the rows of the matrix.
    static func sphereIntersectsFrustum(center: SIMD3<Float>, radius: Float, viewProjection matrix: simd_float4x4) -> Bool {
        let transposed = matrix.transpose
        let row0 = transposed.columns.0
        let row1 = transposed.columns.1
        let row2 = transposed.columns.2
        let row3 = transposed.columns.3
        let planes = [row3 + row0, row3 - row0, row3 + row1, row3 - row1, row2, row3 - row2]
        let point = SIMD4(center, 1)
        for plane in planes {
            let normalLength = simd_length(SIMD3(plane.x, plane.y, plane.z))
            guard normalLength > 0 else {
                continue
            }
            if simd_dot(plane, point) / normalLength < -radius {
                return false
            }
        }
        return true
    }
}
