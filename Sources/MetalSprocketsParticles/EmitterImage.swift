import CoreGraphics
import Foundation
import ImageIO
import simd

/// An image to emit from: particles are born on its pixels, more on heavier ones, and take each pixel's color. Set
/// `EmitterDescription.image` and use `EmitterShape.points`. The image lies in the emitter's XY plane, centered, +Y up.
public struct EmitterImage: Sendable, Equatable, Codable {
    public enum Weighting: String, Sendable, Codable, CaseIterable {
        /// Opaque pixels emit; transparent ones do not. For logos and emoji.
        case alpha
        /// Bright pixels emit more; black ones do not. For photos and glows.
        case brightness
    }

    /// PNG (or any ImageIO format) data. Saved in effect files.
    public var data: Data
    /// Width of the image in world units; height follows the aspect ratio.
    public var width: Float
    /// How many points to sample. Particles are born on these at random.
    public var pointCount: Int
    public var weighting: Weighting
    /// Whether particles take the pixel's color.
    public var usesColors: Bool

    public init(data: Data, width: Float = 2, pointCount: Int = 20_000, weighting: Weighting = .alpha, usesColors: Bool = true) {
        self.data = data
        self.width = width
        self.pointCount = pointCount
        self.weighting = weighting
        self.usesColors = usesColors
    }

    /// The sampled points, the same every time for the same settings. Empty if the data is not an image or no pixel
    /// has weight.
    public func points() -> [EmitterPoint] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              case let pixels = Self.rgbaPixels(image), !pixels.isEmpty else {
            return []
        }
        let columns = image.width
        let rows = image.height
        // Cumulative weights for sampling pixels in proportion to their weight.
        var cumulative: [Float] = []
        cumulative.reserveCapacity(pixels.count)
        var total: Float = 0
        for pixel in pixels {
            total += weight(pixel)
            cumulative.append(total)
        }
        guard total > 0, pointCount > 0 else {
            return []
        }
        let scale = width / Float(columns)
        var random = SplitMix(seed: 0x5EED)
        return (0..<min(pointCount, 1_000_000)).map { _ in
            let target = random.nextFloat() * total
            let index = min(cumulative.partitioningIndex { $0 > target }, pixels.count - 1)
            // A random spot inside the pixel, so points do not line up on a grid.
            let x = (Float(index % columns) + random.nextFloat() - Float(columns) / 2) * scale
            let y = (Float(rows) / 2 - Float(index / columns) - random.nextFloat()) * scale
            let pixel = pixels[index]
            let color = usesColors ? SIMD4(pixel.x, pixel.y, pixel.z, 1) : nil
            return EmitterPoint([x, y, 0], normal: [0, 0, 1], color: color)
        }
    }

    private func weight(_ pixel: SIMD4<Float>) -> Float {
        switch weighting {
        case .alpha:
            pixel.w
        case .brightness:
            simd_dot(SIMD3(pixel.x, pixel.y, pixel.z), [0.2126, 0.7152, 0.0722]) * pixel.w
        }
    }

    /// Straight (not premultiplied) RGBA in 0...1, row by row from the top.
    /// Empty if the image cannot be drawn.
    private static func rgbaPixels(_ image: CGImage) -> [SIMD4<Float>] {
        let columns = image.width
        let rows = image.height
        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else {
            return []
        }
        return (0..<columns * rows).map { index in
            let alpha = Float(bytes[index * 4 + 3]) / 255
            let unpremultiply: Float = alpha > 0 ? 1 / (255 * alpha) : 0
            return SIMD4(
                min(Float(bytes[index * 4]) * unpremultiply, 1),
                min(Float(bytes[index * 4 + 1]) * unpremultiply, 1),
                min(Float(bytes[index * 4 + 2]) * unpremultiply, 1),
                alpha
            )
        }
    }
}

/// A small seeded generator, so sampled points do not change between runs or platforms.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

private extension Array where Element == Float {
    /// The first index whose element satisfies `predicate`, which must be false then true along the array.
    func partitioningIndex(where predicate: (Float) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if predicate(self[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}
