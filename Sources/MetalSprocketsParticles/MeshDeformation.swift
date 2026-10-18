import Metal
import simd

/// Built-in animation for an emitter mesh, applied each frame by the system with `EmitterMesh.setDeformedPositions`.
/// Apps with their own animated meshes (morph targets, skinning) call `setDeformedPositions` themselves instead.
public enum MeshDeformation: Sendable, Equatable, Codable {
    case none
    /// A flag wave along emitter-space X: points move along Z by `amplitude` at the free end (largest X), not at all at
    /// the fixed end (smallest X), in waves `wavelength` long that travel at `speed` units per second.
    case wave(amplitude: Float, wavelength: Float, speed: Float)

    /// `positions` (the rest pose) deformed at `time` seconds.
    public func deform(_ positions: [SIMD3<Float>], time: Float) -> [SIMD3<Float>] {
        switch self {
        case .none:
            return positions
        case let .wave(amplitude, wavelength, speed):
            guard let minX = positions.map(\.x).min(), let maxX = positions.map(\.x).max(), maxX > minX else {
                return positions
            }
            let k = 2 * Float.pi / max(wavelength, 0.0001)
            return positions.map { position in
                let along = (position.x - minX) / (maxX - minX)
                // A second, smaller wave along Y keeps the cloth from moving as one rigid sheet.
                let phase = k * (position.x - minX) - k * speed * time + 0.6 * sin(position.y * k * 0.5)
                return position + [0, 0, amplitude * along * sin(phase)]
            }
        }
    }
}

extension EmitterMesh {
    /// Deforms the rest pose and emits from the result. Cycles through a few buffers so a frame still on the GPU keeps
    /// reading its own positions.
    func applyDeformation(_ deformation: MeshDeformation, time: Float) throws {
        guard deformation != .none else {
            setDeformedPositions(nil)
            return
        }
        let positions = deformation.deform(restPositions, time: time)
        let length = max(positions.count, 1) * MemoryLayout<Float>.stride * 3
        if deformationBuffers.count < Self.deformationBufferCount {
            guard let buffer = triangles.device.makeBuffer(length: length, options: .storageModeShared) else {
                throw CocoaError(.featureUnsupported)
            }
            buffer.label = "Emitter mesh deformed positions"
            deformationBuffers.append(buffer)
        }
        let buffer = deformationBuffers[nextDeformationBuffer]
        nextDeformationBuffer = (nextDeformationBuffer + 1) % Self.deformationBufferCount
        let floats = buffer.contents().bindMemory(to: Float.self, capacity: positions.count * 3)
        for (index, position) in positions.enumerated() {
            floats[index * 3] = position.x
            floats[index * 3 + 1] = position.y
            floats[index * 3 + 2] = position.z
        }
        setDeformedPositions(buffer)
    }
}
