import CoreGraphics
import Metal
import MetalSprockets
@testable import MetalSprocketsParticles
import simd
import Testing

struct DebugWireframeTests {
    func lines(_ field: ForceField) -> [(SIMD3<Float>, SIMD3<Float>)] {
        var builder = WireframeBuilder()
        field.addWireframe(to: &builder)
        return stride(from: 0, to: builder.vertices.count, by: 2).map {
            (builder.vertices[$0].xyz, builder.vertices[$0 + 1].xyz)
        }
    }

    func bounds(_ shape: EmitterShape, center: SIMD3<Float> = .zero) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var builder = WireframeBuilder()
        shape.addWireframe(to: &builder, center: center)
        let points = builder.vertices.map(\.xyz)
        return (points.reduce(points[0], simd_min), points.reduce(points[0], simd_max))
    }

    /// A path draws its smoothed curve, closes the loop when closed, and has arrows pointing the way particles flow.
    @Test func pathFieldsDrawTheCurveAndItsDirection() {
        let points: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        let open = lines(.path(points: points, speed: 1))
        let closed = lines(.path(points: points, speed: 1, closed: true))
        let polyline = ForceField.path(points: points, speed: 1).pathPolyline
        #expect(open.contains { $0.0 == polyline[0] && $0.1 == polyline[1] })
        #expect(!open.contains { $0.0 == polyline.last && $0.1 == polyline.first })
        let closedPolyline = ForceField.path(points: points, speed: 1, closed: true).pathPolyline
        #expect(closed.contains { $0.0 == closedPolyline.last && $0.1 == closedPolyline.first })

        // Arrows start on the curve and are 0.25 long; along +x here, and reversed for negative speed.
        func arrowDirections(_ lines: [(SIMD3<Float>, SIMD3<Float>)]) -> [Float] {
            lines.filter { abs(simd_distance($0.0, $0.1) - 0.25) < 1e-4 }.map { $0.1.x - $0.0.x }
        }
        let forward = arrowDirections(open)
        let backward = arrowDirections(lines(.path(points: points, speed: -1)))
        #expect(!forward.isEmpty && forward.allSatisfy { $0 > 0 })
        #expect(!backward.isEmpty && backward.allSatisfy { $0 < 0 })
    }

    @Test func boxAndPlaneShapesOutlineTheirSize() {
        let box = bounds(.box(size: [2, 4, 6]), center: [1, 0, 0])
        #expect(box.min == [0, -2, -3] && box.max == [2, 2, 3])
        let plane = bounds(.plane(size: [2, 4]))
        #expect(plane.min == [-1, 0, -2] && plane.max == [1, 0, 2])
    }

    /// Tracked objects draw in green, and only when asked for.
    @Test(.requiresMetal4) func trackedObjectsDrawWhenAskedFor() throws {
        let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
        let system = try ParticleSystemRuntime(device: renderer.device, capacity: 1, modules: .standard)
        system.trackedObjects = ["ball": .zero]
        let view = simd_float4x4(lookingFrom: [0, 0, 1], at: .zero).inverse
        let projection = simd_float4x4.perspective(fovY: .pi / 4, aspect: 1, near: 0.1, far: 10)
        func greenPixels(_ options: WireframeOptions) throws -> Int {
            let image = try renderer.render(RenderPass {
                try system.renderWireframes(projection: projection, view: view, options: options)
            }).cgImage
            return try image.rgbaPixels().filter { $0.y > 200 && $0.x < 150 }.count
        }
        #expect(try greenPixels(.trackedObjects) > 20)
        #expect(try greenPixels(.colliders) == 0)
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
