import Metal
import MetalSprocketsParticlesShaders
import simd
import SwiftMesh

public extension Collider {
    /// A distance field collider baked from `mesh` on the CPU, once. `resolution` is the number of samples along the
    /// mesh's longest side; the other sides get the same spacing, so cells are cubes. `padding` (in cells) grows the
    /// grid past the mesh on every side so the field is positive at its edge. The mesh is in the collider's local
    /// space, placed by `center` and `rotation`. Nil when the mesh has no triangles.
    ///
    /// Baking runs on all cores and takes a moment for detailed meshes at high resolutions; bake once and keep the
    /// collider, rather than baking per frame.
    static func signedDistanceField(
        mesh: Mesh,
        resolution: Int = 64,
        padding: Int = 2,
        center: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        categoryBitMask: UInt32 = .max
    ) -> Self? {
        guard let bounds = mesh.bounds else {
            return nil
        }
        let size = bounds.max - bounds.min
        let longest = max(size.max(), 1e-6)
        let padding = max(padding, 0)
        let cell = longest / Float(max(max(resolution, 2) - 1 - 2 * padding, 1))
        let paddingDistance = cell * Float(padding)
        // Samples per axis to cover each side plus padding at about this cell size (SwiftMesh spreads the grid over the
        // padded bounds exactly, so cells are cubes to within rounding); the longest side gets `resolution`.
        let perAxis = SIMD3<Int>(((size + 2 * paddingDistance) / cell).rounded(.up)) &+ 1
        guard let field = mesh.signedDistanceField(resolution: simd_max(perAxis, SIMD3(repeating: 2)), padding: paddingDistance) else {
            return nil
        }
        return .signedDistanceField(field, center: center, rotation: rotation, categoryBitMask: categoryBitMask)
    }
}

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
