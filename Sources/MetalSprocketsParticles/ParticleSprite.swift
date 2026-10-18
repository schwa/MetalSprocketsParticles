import CoreGraphics
import CoreText
import Foundation
import Metal

/// Built-in sprites drawn with Core Graphics, so effects need no image assets.
public enum ParticleSprite: String, CaseIterable, Identifiable, Sendable, Codable {
    case softDot = "Soft Dot"
    case star = "Star"
    case spark = "Spark"
    case smoke = "Smoke Puff"
    case ring = "Ring"
    case triangle = "Triangle"
    case colorSheet = "Color Sheet 2×2"
    case heart = "❤️ Heart"
    case fire = "🔥 Fire"
    case droplet = "💧 Droplet"
    case glowingStar = "🌟 Star"
    case moonPhases = "🌑…🌘 Moon Phases 2×4"
    case clockFaces = "🕐…🕛 Clock Faces 3×4"

    public var id: Self { self }

    /// Rows and columns when the texture is a sprite sheet.
    public var sheetLayout: (rows: Int, columns: Int)? {
        switch self {
        case .colorSheet: (2, 2)
        case .moonPhases: (2, 4)
        case .clockFaces: (3, 4)
        default: nil
        }
    }

    /// An image sequence that plays every cell of a sprite sheet once per second, or `nil` for single sprites.
    public var defaultImageSequence: ImageSequence? {
        sheetLayout.map { ImageSequence(rows: $0.rows, columns: $0.columns, frameRate: Float($0.rows * $0.columns)) }
    }

    /// Emoji glyphs, one per sheet cell; empty for drawn sprites. Emoji are already colored, so tint particles white to
    /// keep them true.
    var emoji: [String] {
        switch self {
        case .heart: ["❤️"]
        case .fire: ["🔥"]
        case .droplet: ["💧"]
        case .glowingStar: ["🌟"]
        case .moonPhases: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
        case .clockFaces: ["🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛"]
        default: []
        }
    }

    /// `nil` for the soft dot, which the shader draws without a texture.
    public func makeTexture(device: MTLDevice) -> MTLTexture? {
        guard self != .softDot else {
            return nil
        }
        let layout = sheetLayout ?? (1, 1)
        let cell = emoji.isEmpty ? 64 : 128
        let width = layout.columns * cell
        let height = layout.rows * cell
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // Flip so cell 0 is top-left, matching the texture.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for index in 0..<(layout.rows * layout.columns) {
            let rect = CGRect(x: (index % layout.columns) * cell, y: (index / layout.columns) * cell, width: cell, height: cell)
            draw(in: context, rect: rect, index: index)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor), let data = context.data else {
            return nil
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)
        texture.label = rawValue
        return texture
    }

    private func draw(in context: CGContext, rect: CGRect, index: Int) {
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.saveGState()
        defer { context.restoreGState() }
        let emoji = self.emoji
        if !emoji.isEmpty {
            drawEmoji(emoji[index % emoji.count], in: context, rect: rect)
            return
        }
        switch self {
        case .softDot, .heart, .fire, .droplet, .glowingStar, .moonPhases, .clockFaces:
            break
        case .star:
            let points = 5
            context.move(to: CGPoint(x: center.x, y: rect.minY + 2))
            for step in 1..<(points * 2) {
                let radius = step.isMultiple(of: 2) ? rect.width / 2 - 2 : rect.width / 5
                let angle = CGFloat(step) * .pi / CGFloat(points) - .pi / 2
                context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
            context.closePath()
            context.setFillColor(white)
            context.fillPath()
        case .spark:
            radialGlow(context, center: center, radius: rect.width / 2, falloff: 2.5)
            context.setFillColor(white)
            context.fill(CGRect(x: center.x - 1, y: rect.minY, width: 2, height: rect.height))
            context.fill(CGRect(x: rect.minX, y: center.y - 1, width: rect.width, height: 2))
        case .smoke:
            // Overlapping soft blobs, positioned by a fixed pattern so the texture is the same every launch.
            let offsets: [CGPoint] = [[-0.15, -0.1], [0.12, -0.05], [0, 0.12], [-0.05, 0.02], [0.1, 0.1]].map { CGPoint(x: $0[0], y: $0[1]) }
            for offset in offsets {
                radialGlow(context, center: CGPoint(x: center.x + offset.x * rect.width, y: center.y + offset.y * rect.height), radius: rect.width * 0.3, falloff: 1, alpha: 0.5)
            }
        case .ring:
            context.setStrokeColor(white)
            context.setLineWidth(rect.width * 0.08)
            context.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12))
        case .triangle:
            context.move(to: CGPoint(x: center.x, y: rect.minY + 4))
            context.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 4))
            context.addLine(to: CGPoint(x: rect.minX + 8, y: rect.maxY - 4))
            context.setFillColor(white)
            context.fillPath()
        case .colorSheet:
            let colors: [CGColor] = [
                CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1),
                CGColor(srgbRed: 0.2, green: 1, blue: 0.3, alpha: 1),
                CGColor(srgbRed: 0.3, green: 0.4, blue: 1, alpha: 1),
                white,
            ]
            context.setFillColor(colors[index % colors.count])
            context.fillEllipse(in: rect.insetBy(dx: 6, dy: 6))
        }
    }

    private func drawEmoji(_ string: String, in context: CGContext, rect: CGRect) {
        let font = CTFontCreateWithName("Apple Color Emoji" as CFString, rect.height * 0.8, nil)
        let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.clip(to: rect)
        // The context is flipped for top-left cells; text needs y up, so flip back around the cell.
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.midX - width / 2, y: rect.midY - (ascent - descent) / 2)
        CTLineDraw(line, context)
    }

    private static let sRGB: CGColorSpace = {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            preconditionFailure("The sRGB color space is unavailable.")
        }
        return space
    }()

    private func radialGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, falloff: CGFloat, alpha: CGFloat = 1) {
        let space = Self.sRGB
        let stops: [CGFloat] = [0, 0.4, 1]
        let colors = stops.map { stop in
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha * pow(1 - stop, falloff))
        }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops) else {
            return
        }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}
