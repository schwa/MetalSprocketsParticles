import simd

public extension ParticleEmitter {
    /// The demo scene: a fountain falling onto a ground plane, a sphere, and two boxes.
    static var fountain: ParticleEmitter {
        var emitter = ParticleEmitter()
        emitter.position = [0, 0.5, 0]
        emitter.velocity = [0, 5, 0]
        emitter.birthRate = 20_000
        emitter.colliders = fountainColliders(time: 0)
        return emitter
    }

    /// The fountain's colliders animated over time: the sphere bobs through the jet and the boxes slide.
    static func fountainColliders(time: Float) -> [Collider] {
        [
            .plane(normal: [0, 1, 0], distance: 0),
            .sphere(center: [0, 2.5 + 0.6 * sin(time * 1.3), 0], radius: 0.6),
            .box(center: [1.2 + 0.5 * sin(time * 0.9), 0.5, 0], halfExtents: [0.3, 0.5, 0.3]),
            .box(center: [-1.2, 0.25, 0.4 + 0.6 * sin(time * 0.7)], halfExtents: [0.4, 0.25, 0.4]),
        ]
    }
}

public extension simd_float4x4 {
    /// Camera-to-world matrix.
    init(lookingFrom eye: SIMD3<Float>, at target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        self.init(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(eye, 1)))
    }

    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
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
}
