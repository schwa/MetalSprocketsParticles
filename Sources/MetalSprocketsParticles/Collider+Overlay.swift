import CoreGraphics
import simd

// Colliders from view geometry, for 2D overlays. Coordinates are the overlay camera's: points, origin at the view's
// top left, y down, particles at z = 0.

public extension Collider {
    /// A box covering `frame` (for example a button's frame in the overlay's coordinate space), `depth` points thick
    /// around z = 0.
    static func box(frame: CGRect, depth: Float = 100, categoryBitMask: UInt32 = .max) -> Self {
        .box(
            center: [Float(frame.midX), Float(frame.midY), 0],
            halfExtents: [Float(frame.width) / 2, Float(frame.height) / 2, depth / 2],
            categoryBitMask: categoryBitMask
        )
    }

    /// Four planes along the edges of a view of `size`, facing in, so particles stay inside it.
    static func edges(of size: CGSize, categoryBitMask: UInt32 = .max) -> [Self] {
        let width = Float(size.width)
        let height = Float(size.height)
        return [
            .plane(normal: [1, 0, 0], distance: 0, categoryBitMask: categoryBitMask),
            .plane(normal: [-1, 0, 0], distance: -width, categoryBitMask: categoryBitMask),
            .plane(normal: [0, 1, 0], distance: 0, categoryBitMask: categoryBitMask),
            .plane(normal: [0, -1, 0], distance: -height, categoryBitMask: categoryBitMask),
        ]
    }

    /// The bottom edge of a view of `size` as a floor that particles land on (y grows down the screen).
    static func floor(of size: CGSize, categoryBitMask: UInt32 = .max) -> Self {
        .plane(normal: [0, -1, 0], distance: -Float(size.height), categoryBitMask: categoryBitMask)
    }
}
