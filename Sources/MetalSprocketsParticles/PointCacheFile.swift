import Foundation
import SwiftPLY

/// Point caches in PLY files (#177): one `vertex` element with float `x y z`, and `nx ny nz` and
/// `red green blue alpha` when any point has a normal or a color. Floats keep values exact. A point without a normal or
/// color, among points that have one, is written as NaN and read back as nil.
enum PointCacheFile {
    static func plyData(of points: [EmitterPoint]) throws -> Data {
        let hasNormals = points.contains { $0.normal != nil }
        let hasColors = points.contains { $0.color != nil }
        var names = ["x", "y", "z"]
        if hasNormals { names += ["nx", "ny", "nz"] }
        if hasColors { names += ["red", "green", "blue", "alpha"] }
        let element = PLYReader.Element(
            name: "vertex", count: points.count,
            properties: names.map { PLYReader.Property(name: $0, kind: .scalar(.float)) }
        )
        var writer = PLYWriter(header: PLYHeader(format: .binaryLittleEndian, elements: [element]))
        for point in points {
            var values = [point.position.x, point.position.y, point.position.z]
            if hasNormals {
                let normal = point.normal ?? SIMD3(repeating: .nan)
                values += [normal.x, normal.y, normal.z]
            }
            if hasColors {
                let color = point.color ?? SIMD4(repeating: .nan)
                values += [color.x, color.y, color.z, color.w]
            }
            try writer.write(values.map { .float($0) })
        }
        return try writer.finish()
    }

    /// Points from the first `vertex` element. Only `x y z` are required; other properties are ignored.
    static func points(from data: Data) throws -> [EmitterPoint] {
        let reader = try PLYReader(data: data)
        guard let element = reader.elements.first(where: { $0.name == "vertex" }) else {
            throw PointCacheFileError.noVertices
        }
        let names = element.properties.map(\.name)
        func indices(_ wanted: [String]) -> [Int]? { // swiftlint:disable:this discouraged_optional_collection
            let found = wanted.compactMap { names.firstIndex(of: $0) }
            return found.count == wanted.count ? found : nil
        }
        guard let position = indices(["x", "y", "z"]) else {
            throw PointCacheFileError.noPositions
        }
        let normal = indices(["nx", "ny", "nz"])
        let color = indices(["red", "green", "blue", "alpha"]) ?? indices(["red", "green", "blue"])
        // Other tools usually write colors as uchar, 0 to 255.
        var colorDivisor: Float = 1
        if let first = color?.first, case .scalar(.uchar) = element.properties[first].kind {
            colorDivisor = 255
        }
        var points: [EmitterPoint] = []
        points.reserveCapacity(element.count)
        try reader.readFloatValues(element: element) { values in
            func value(_ index: Int) throws -> Float {
                guard let value = values[index] else {
                    throw PointCacheFileError.unreadable
                }
                return value
            }
            var point = try EmitterPoint([value(position[0]), value(position[1]), value(position[2])])
            if let normal {
                let vector = try SIMD3(value(normal[0]), value(normal[1]), value(normal[2]))
                point.normal = vector.x.isNaN ? nil : vector
            }
            if let color {
                let alpha = try color.count == 4 ? value(color[3]) : colorDivisor
                let vector = try SIMD4(value(color[0]), value(color[1]), value(color[2]), alpha) / colorDivisor
                point.color = vector.x.isNaN ? nil : vector
            }
            points.append(point)
        }
        return points
    }
}

enum PointCacheFileError: Error, LocalizedError {
    case noVertices
    case noPositions
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noVertices: "The point cache PLY file has no vertex element."
        case .noPositions: "The point cache PLY file's vertices have no x, y, and z."
        case .unreadable: "The point cache PLY file has a value that cannot be read."
        }
    }
}
