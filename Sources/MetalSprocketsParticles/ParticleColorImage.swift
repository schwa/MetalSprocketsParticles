import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

/// An image laid over the world that particles take their color from as they move (`ColorImageModule`): each
/// frame, a particle's color is multiplied by the image's color under its position. The image covers the rectangle
/// from `origin` (its bottom-left corner) along `width` and `height` (edge vectors, world space); particles off the
/// image take the nearest edge color. Saved in effect files as image data.
public struct ParticleColorImage: Sendable, Equatable, Codable {
    /// PNG (or any ImageIO format) data.
    public var data: Data
    public var origin: SIMD3<Float>
    public var width: SIMD3<Float>
    public var height: SIMD3<Float>

    private enum CodingKeys: String, CodingKey {
        case data, origin, width, height
    }

    /// The image is a file next to the effect's JSON (see `EffectResources`).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeResource(forKey: .data, decoder: decoder)
        origin = try container.decode(SIMD3<Float>.self, forKey: .origin)
        width = try container.decode(SIMD3<Float>.self, forKey: .width)
        height = try container.decode(SIMD3<Float>.self, forKey: .height)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeResource(data, forKey: .data, encoder: encoder, prefix: "color-image", fileExtension: data.imageFileExtension)
        try container.encode(origin, forKey: .origin)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    public init(data: Data, origin: SIMD3<Float>, width: SIMD3<Float>, height: SIMD3<Float>) {
        self.data = data
        self.origin = origin
        self.width = width
        self.height = height
    }

    /// An upright image centered on `center` in the XY plane, `size` units wide and as tall as its aspect ratio makes it.
    public init(data: Data, center: SIMD3<Float>, size: Float) {
        let aspect = Self.aspectRatio(of: data) ?? 1
        let width = SIMD3<Float>(size, 0, 0)
        let height = SIMD3<Float>(0, size / aspect, 0)
        self.init(data: data, origin: center - width / 2 - height / 2, width: width, height: height)
    }

    /// Width over height, or nil when the data is not an image.
    static func aspectRatio(of data: Data) -> Float? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.height > 0 else {
            return nil
        }
        return Float(image.width) / Float(image.height)
    }

    /// The image as an RGBA texture, colors as stored (not premultiplied); nil when the data is not an image.
    func makeTexture(device: MTLDevice) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        // Undo the premultiplication, so transparent edges do not darken colors.
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] > 0 && bytes[index + 3] < 255 {
            let alpha = Float(bytes[index + 3]) / 255
            for channel in 0..<3 {
                bytes[index + channel] = UInt8(min(Float(bytes[index + channel]) / alpha, 255))
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        texture.label = "Particle color image"
        return texture
    }
}

extension ParticleSystemRuntime {
    /// The texture for `image`, made once per image data.
    func colorImageTexture(for image: ParticleColorImage) -> MTLTexture? {
        if let cached = colorImageTextures[image.data] {
            return cached
        }
        let texture = image.makeTexture(device: device)
        colorImageTextures[image.data] = texture
        return texture
    }
}
