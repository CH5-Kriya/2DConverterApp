import XCTest
import simd
@testable import ReliefCore

/// The preview renders the exported solid rather than a lookalike, so these
/// assert the two stay the same object: same face count as `Mesh.build`, still
/// watertight, and oriented the way the camera rig assumes.
final class PreviewMeshTests: XCTestCase {

    /// A dome, a ripple and a fine grain: curvature in both axes plus detail
    /// small enough that a resample would visibly eat it.
    private func syntheticHeight(rows: Int = 96, cols: Int = 128) -> Plane {
        var values = [Float](repeating: 0, count: rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                let u = Float(c) / Float(cols - 1) - 0.5
                let v = Float(r) / Float(rows - 1) - 0.5
                values[r * cols + c] = max(0, 0.25 - (u * u + v * v)) * 3
                    + 0.08 * sin(18 * u) * cos(14 * v)
                    + 0.02 * sin(140 * u) * sin(120 * v)
            }
        }
        return Plane(rows: rows, cols: cols, values: values)
    }

    private func config(grid: Int = 128) -> MeshConfig {
        var config = MeshConfig()
        config.plateWidthMm = 200
        config.reliefMm = 30
        config.baseMm = 3
        config.maxGrid = grid
        return config
    }

    private func build(rows: Int = 96, cols: Int = 128,
                       grid: Int = 128) -> ReliefPreviewMesh {
        ReliefPreviewMeshBuilder.build(height: syntheticHeight(rows: rows, cols: cols),
                                       config: config(grid: grid))
    }

    /// The whole point of the rewrite: the preview is the export's geometry,
    /// not a second triangulation that merely resembles it.
    func testPreviewIsTheExportedGeometry() {
        var undecimated = config()
        undecimated.decimate = false
        let solid = Mesh.build(height: syntheticHeight(), config: undecimated)
        let preview = build()

        XCTAssertEqual(preview.triangleCount, solid.faceCount)
        XCTAssertEqual(preview.positions.count, solid.vertexCount)
        XCTAssertEqual(preview.widthMm, solid.widthMm)
        XCTAssertEqual(preview.thicknessMm, solid.thicknessMm)
        XCTAssertTrue(solid.isWatertight,
                      "the solid the preview renders has to be printable too")
    }

    func testBuffersAreConsistent() {
        let mesh = build()

        XCTAssertEqual(mesh.positions.count, mesh.normals.count)
        XCTAssertFalse(mesh.indices.isEmpty)
        XCTAssertEqual(mesh.indices.count % 3, 0)

        let limit = UInt32(mesh.positions.count)
        XCTAssertTrue(mesh.indices.allSatisfy { $0 < limit },
                      "an index points past the end of the vertex buffer")

        for normal in mesh.normals {
            XCTAssertEqual(simd_length(normal), 1, accuracy: 1e-4)
        }
    }

    /// The camera rig is a constant, which only holds if the mesh always
    /// arrives centred on the origin at a known size.
    func testMeshIsNormalisedAndCentred() {
        let mesh = build()

        var low = mesh.positions[0], high = mesh.positions[0]
        for p in mesh.positions {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }

        XCTAssertEqual((high - low).max(), ReliefPreviewMeshBuilder.sceneSize,
                       accuracy: 1e-5)
        XCTAssertEqual(simd_length((high + low) / 2), 0, accuracy: 1e-5)
    }

    /// Front faces have to point at the viewer, or the relief renders as its
    /// own cavity. `relief_solidify` puts the picture in XY with the depth
    /// rising along +Z, which is what the camera rig assumes.
    func testReliefSurfaceFacesTheViewer() {
        let mesh = build()
        let front = mesh.normals.filter { $0.z > 0.5 }
        XCTAssertGreaterThan(front.count, mesh.normals.count / 2,
                             "most of the mesh should be the relief surface")
    }

    /// Row 0 of the height field is the top of the picture. Flip it and every
    /// relief comes out mirrored, which is invisible on a symmetric test shape
    /// and obvious on a face.
    func testTopOfTheImageIsTopOfTheModel() {
        let rows = 64, cols = 64
        var values = [Float](repeating: 0, count: rows * cols)
        for r in 0..<(rows / 4) {
            for c in 0..<cols { values[r * cols + c] = 1 }
        }
        let mesh = ReliefPreviewMeshBuilder.build(
            height: Plane(rows: rows, cols: cols, values: values),
            config: config(grid: cols))

        // The raised band came from the first rows, so its vertices must sit in
        // the upper half of the model.
        let raised = mesh.positions.filter { $0.z > 0 }
        XCTAssertFalse(raised.isEmpty)
        let averageY = raised.reduce(0) { $0 + $1.y } / Float(raised.count)
        XCTAssertGreaterThan(averageY, 0, "the relief is upside down")
    }

    /// Detail survives at the export grid. The old builder capped at 220
    /// samples and box-averaged on the way down, which is what made the preview
    /// look smoother than the thing it was previewing.
    func testHonoursTheConfiguredGrid() {
        let coarse = build(rows: 512, cols: 512, grid: 128)
        let fine = build(rows: 512, cols: 512, grid: 512)
        XCTAssertGreaterThan(fine.triangleCount, coarse.triangleCount * 8)
    }
}
