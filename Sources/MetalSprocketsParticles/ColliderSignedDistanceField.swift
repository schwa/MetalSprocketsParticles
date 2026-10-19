import Metal
import MetalSprocketsParticlesShaders
import SwiftMesh

/// A signed distance field collider's grid on the GPU.
struct SignedDistanceFieldTexture {
    var field: SignedDistanceField
    var texture: MTLTexture
}

extension ParticleSystemRuntime {
    /// Makes a 3D texture for each distance field in `colliders` that has none, and drops textures no collider uses.
    /// A grid is uploaded once and reused while colliders keep it, even as they move. Comparing a collider's grid with
    /// a cached one is quick when they share storage, as copies of one grid do.
    func updateSignedDistanceFieldTextures(for colliders: [Collider]) throws {
        let fields = colliders.compactMap { collider -> SignedDistanceField? in
            guard case let .signedDistanceField(field, _, _) = collider.shape else {
                return nil
            }
            return field
        }
        guard !fields.isEmpty || !signedDistanceFieldTextures.isEmpty else {
            return
        }
        var kept: [SignedDistanceFieldTexture] = []
        for field in fields where !kept.contains(where: { $0.field == field }) {
            if let cached = signedDistanceFieldTextures.first(where: { $0.field == field }) {
                kept.append(cached)
            } else {
                kept.append(SignedDistanceFieldTexture(field: field, texture: try makeTexture(for: field)))
            }
        }
        signedDistanceFieldTextures = kept
    }

    /// Where a distance field collider's texture is in the simulation's field textures; out of range (so the kernel
    /// skips it) for other colliders and fields past `PARTICLE_MAX_SIGNED_DISTANCE_FIELDS`.
    func signedDistanceFieldSlot(for collider: Collider) -> UInt32 {
        guard case let .signedDistanceField(field, _, _) = collider.shape,
              let index = signedDistanceFieldTextures.firstIndex(where: { $0.field == field }),
              index < Int(PARTICLE_MAX_SIGNED_DISTANCE_FIELDS) else {
            return .max
        }
        return UInt32(index)
    }

    /// The field textures to bind, one per slot; unused slots get `placeholder`.
    func signedDistanceFieldTextureSlots(placeholder: MTLTexture) -> [MTLTexture] {
        (0..<Int(PARTICLE_MAX_SIGNED_DISTANCE_FIELDS)).map { index in
            index < signedDistanceFieldTextures.count ? signedDistanceFieldTextures[index].texture : placeholder
        }
    }

    /// The texture for `field`, once `updateSignedDistanceFieldTextures(for:)` has seen a collider using it.
    func signedDistanceFieldTexture(for field: SignedDistanceField) -> MTLTexture? {
        signedDistanceFieldTextures.first { $0.field == field }?.texture
    }

    private func makeTexture(for field: SignedDistanceField) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r32Float
        descriptor.width = field.resolution.x
        descriptor.height = field.resolution.y
        descriptor.depth = field.resolution.z
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ParticleSystemRuntimeError.signedDistanceFieldTooLarge(resolution: field.resolution)
        }
        texture.label = "Signed distance field \(field.resolution.x)×\(field.resolution.y)×\(field.resolution.z)"
        // Values are x fastest, then y, then z: the texture's row and slice order.
        let rowBytes = field.resolution.x * MemoryLayout<Float>.size
        field.values.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                texture.replace(
                    region: MTLRegionMake3D(0, 0, 0, field.resolution.x, field.resolution.y, field.resolution.z),
                    mipmapLevel: 0,
                    slice: 0,
                    withBytes: base,
                    bytesPerRow: rowBytes,
                    bytesPerImage: rowBytes * field.resolution.y
                )
            }
        }
        return texture
    }
}
