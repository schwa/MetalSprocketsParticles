import Foundation
import ImageIO
import Metal
import MetalKit
import MetalSprocketsParticles
import ModelIO
import simd
import SwiftMesh

/// What particles are drawn as: a sprite or one of the built-in meshes. `custom` is a triangle mesh from a saved effect;
/// it can be kept or replaced but not made here.
enum ParticleDrawing: String, CaseIterable, Identifiable {
    case sprite = "Sprite"
    case cube = "Cube"
    case tetrahedron = "Tetrahedron"
    case coin = "Coin"
    case custom = "Custom Mesh"

    var id: Self { self }
}

extension ParticleEmitter {
    var drawing: ParticleDrawing {
        get {
            switch particleMesh {
            case nil: .sprite
            case .cube: .cube
            case .tetrahedron: .tetrahedron
            case .coin: .coin
            case .triangles: .custom
            }
        }
        set {
            switch newValue {
            case .sprite: particleMesh = nil
            case .cube: particleMesh = .cube
            case .tetrahedron: particleMesh = .tetrahedron
            case .coin: particleMesh = .coin
            case .custom: break // Only kept, never made here.
            }
        }
    }
}

/// Meshes to emit from (`EmitterShape.mesh`), from SwiftMesh, about two units across.
enum DemoMesh: String, CaseIterable, Identifiable {
    case teapot = "Teapot"
    case sphere = "Sphere"
    case torus = "Torus"
    case cube = "Cube"
    case cylinder = "Cylinder"

    var id: Self { self }

    var mesh: Mesh {
        switch self {
        case .teapot: .teapot(diameter: 2)
        case .sphere: .icoSphere(extents: [2, 2, 2], subdivisions: 3)
        case .torus: .torus(majorRadius: 0.7, minorRadius: 0.3)
        case .cube: .box(extents: [1.5, 1.5, 1.5])
        case .cylinder: .cylinder(height: 2, radius: 0.6)
        }
    }
}

/// What a distance field collider is baked from in the demo.
enum DistanceFieldSource: Equatable, Sendable {
    case builtIn(DemoMesh)
    case text(String)
    case file(Mesh)

    static let teapot = Self.builtIn(.teapot)

    var mesh: Mesh {
        switch self {
        case let .builtIn(choice): choice.mesh
        case let .text(string): Self.centeredFlat(.extrudedText(string.isEmpty ? " " : string, fontName: "Helvetica-Bold", size: 1.2, depth: 0.3))
        case let .file(mesh): mesh
        }
    }

    /// Extruded text centered, lying flat with its depth up, like Sand on Letters.
    private static func centeredFlat(_ mesh: Mesh) -> Mesh {
        guard let bounds = mesh.bounds else {
            return mesh
        }
        var mesh = mesh
        let middle = (bounds.min + bounds.max) / 2
        let flat = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        mesh.positions = mesh.positions.map { flat.act(SIMD3($0.x - middle.x, $0.y - middle.y, $0.z - bounds.min.z)) }
        return mesh
    }

    /// The baked collider shape, or nil for a mesh with no triangles. `insideOut` negates the field, so the mesh's
    /// inside is a container.
    func shape(resolution: Int, padding: Int, insideOut: Bool, center: SIMD3<Float>, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) -> Collider.Shape? {
        guard let baked = Collider.signedDistanceField(mesh: mesh, resolution: resolution, padding: padding),
              case var .signedDistanceField(field, _, _) = baked.shape else {
            return nil
        }
        if insideOut {
            field.values = field.values.map { -$0 }
        }
        return .signedDistanceField(field, center: center, rotation: rotation)
    }
}

enum ShapeSourceError: LocalizedError {
    case noMesh
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .noMesh: "The file has no mesh that Model I/O can read."
        case .notAnImage: "The file is not an image."
        }
    }
}

extension Mesh {
    /// The first mesh in a model file Model I/O can read (OBJ, USD, and others).
    static func loadingFirstMesh(from url: URL, device: MTLDevice) throws -> Mesh {
        // SwiftMesh goes through MetalKit, which needs the asset's buffers made by a MetalKit allocator.
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: MTKMeshBufferAllocator(device: device))
        let meshes = asset.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        guard let first = meshes.first else {
            throw ShapeSourceError.noMesh
        }
        return try Mesh(mdlMesh: first, device: device)
    }
}

extension EmitterImage {
    /// A new emitter image from `data`, keeping `existing`'s settings when there is one.
    static func choosing(data: Data, replacing existing: EmitterImage?) throws -> EmitterImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ShapeSourceError.notAnImage
        }
        guard var existing else {
            return EmitterImage(data: data)
        }
        existing.data = data
        return existing
    }

    /// `pointCount` as a slider value, at least 1.
    var editablePointCount: Float {
        get { Float(pointCount) }
        set { pointCount = max(Int(newValue.rounded()), 1) }
    }
}

extension EmitterDescription {
    /// The emitter image's settings, or defaults when there is none; edits then do nothing.
    var editableImage: EmitterImage {
        get { image ?? EmitterImage(data: Data()) }
        set {
            if image != nil {
                image = newValue
            }
        }
    }

    var hasWaveDeformation: Bool {
        get { meshDeformation != .none }
        set { meshDeformation = newValue ? (meshDeformation == .none ? .wave(amplitude: 0.1, wavelength: 1, speed: 1) : meshDeformation) : .none }
    }

    var waveAmplitude: Float {
        get {
            if case let .wave(amplitude, _, _) = meshDeformation {
                return amplitude
            }
            return 0.1
        }
        set {
            if case let .wave(_, wavelength, speed) = meshDeformation {
                meshDeformation = .wave(amplitude: newValue, wavelength: wavelength, speed: speed)
            }
        }
    }

    var waveLength: Float {
        get {
            if case let .wave(_, wavelength, _) = meshDeformation {
                return wavelength
            }
            return 1
        }
        set {
            if case let .wave(amplitude, _, speed) = meshDeformation {
                meshDeformation = .wave(amplitude: amplitude, wavelength: newValue, speed: speed)
            }
        }
    }

    var waveSpeed: Float {
        get {
            if case let .wave(_, _, speed) = meshDeformation {
                return speed
            }
            return 1
        }
        set {
            if case let .wave(amplitude, wavelength, _) = meshDeformation {
                meshDeformation = .wave(amplitude: amplitude, wavelength: wavelength, speed: newValue)
            }
        }
    }
}
