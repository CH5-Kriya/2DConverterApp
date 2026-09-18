import CoreVideo
import XCTest
@testable import ReliefCore

/// The two hand-written pieces of `AppleDepthBackend`: the picture that goes
/// into Core ML and the buffer that comes back out.
///
/// The prediction itself needs the 50 MB package, which is not a test fixture,
/// so the end-to-end case runs only when `TACTURA_SMALL_MODEL` points at it:
///
///     TACTURA_SMALL_MODEL=Tactura/Resources/DepthAnythingV2SmallF16.mlpackage \
///         swift test --filter AppleDepthTests
final class AppleDepthTests: XCTestCase {

    /// Channel order and row order both survive the trip to CGImage.
    ///
    /// Interleaved RGB into a bitmap is exactly the kind of loop that still
    /// produces a plausible-looking picture when it is transposed or when the
    /// channels are rotated, and the model would not complain either — it would
    /// just return depth for a different image.
    func testImageKeepsChannelAndRowOrder() throws {
        // 2x3, deliberately non-square so a transpose cannot pass.
        let rows = 2, cols = 3
        var values = [Float](repeating: 0, count: rows * cols * 3)
        for i in 0..<(rows * cols) {
            values[i * 3 + 0] = Float(i) / 10        // R climbs across the image
            values[i * 3 + 1] = 0
            values[i * 3 + 2] = 1                    // B pinned high
        }
        let plane = Plane(rows: rows, cols: cols, channels: 3, values: values)
        let image = try XCTUnwrap(AppleDepthBackend.image(from: plane))

        XCTAssertEqual(image.width, cols)
        XCTAssertEqual(image.height, rows)

        // Read it back through the loader the pipeline itself uses.
        let round = try XCTUnwrap(ReliefImage.plane(from: image))
        XCTAssertEqual(round.rows, rows)
        XCTAssertEqual(round.cols, cols)
        for i in 0..<(rows * cols) {
            XCTAssertEqual(round.values[i * 3 + 0], Float(i) / 10, accuracy: 1.0 / 255)
            XCTAssertEqual(round.values[i * 3 + 1], 0, accuracy: 1.0 / 255)
            XCTAssertEqual(round.values[i * 3 + 2], 1, accuracy: 1.0 / 255)
        }
    }

    /// The output reader honours `bytesPerRow`.
    ///
    /// Core ML pads pixel-buffer rows, and reading the base address as a flat
    /// array shifts every row progressively. The result has the right element
    /// count and the right range, so nothing downstream notices — it is simply
    /// a sheared depth map. A width that is not a multiple of 64 is what makes
    /// a padded buffer, so this asserts on one.
    func testPlaneReadsPaddedRows() throws {
        let w = 518, h = 4
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                           kCVPixelFormatType_OneComponent16Half,
                                           nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)

        CVPixelBufferLockBaseAddress(pixels, [])
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float16.self)
            // One distinct value per row, so a stride slip is unmissable.
            for x in 0..<w { row[x] = Float16(y * 10 + (x == 0 ? 1 : 0)) }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])

        let plane = try AppleDepthBackend.plane(from: pixels)
        XCTAssertEqual(plane.rows, h)
        XCTAssertEqual(plane.cols, w)
        for y in 0..<h {
            XCTAssertEqual(plane.values[y * w + 0], Float(y * 10 + 1))
            XCTAssertEqual(plane.values[y * w + w - 1], Float(y * 10))
        }
    }

    /// End to end, when the package is on hand.
    ///
    /// The input is the app's own hero artwork rather than a synthetic ramp.
    /// A ramp turned out to be a *degenerate* picture for a depth model — it
    /// came back near-constant, which `normalize01` then stretched into noise,
    /// so the test could not tell a working prediction from a dead one. A real
    /// picture has real structure, and that structure is what has to survive
    /// the trip out through a padded float16 buffer and back up to working
    /// resolution.
    ///
    /// Reached through `#filePath` because it is committed a fixed two levels
    /// above the package, and copying it into `Fixtures/` would be a second
    /// copy of a file the repository already carries.
    func testPredictsAgainstTheRealModel() throws {
        guard let path = ProcessInfo.processInfo.environment["TACTURA_SMALL_MODEL"] else {
            throw XCTSkip("set TACTURA_SMALL_MODEL to the .mlpackage to run this")
        }
        let repo = URL(fileURLWithPath: #filePath)      // Tests/ReliefCoreTests/…
            .deletingLastPathComponent()                // ReliefCoreTests
            .deletingLastPathComponent()                // Tests
            .deletingLastPathComponent()                // ReliefKit
            .deletingLastPathComponent()                // repo root
        let artwork = repo.appending(path:
            "Tactura/Assets.xcassets/HeroArtwork.imageset/hero-artwork.png")
        let data = try Data(contentsOf: artwork)
        let rgb = try XCTUnwrap(ReliefImage.load(data: data, maxEdge: 700))

        let backend = AppleDepthBackend(modelURL: URL(fileURLWithPath: path))
        let result = try backend.predict(rgb: rgb, lab: rgb)

        XCTAssertEqual(result.backend, "dav2-small")
        XCTAssertEqual(result.depth.rows, rgb.rows)
        XCTAssertEqual(result.depth.cols, rgb.cols)
        XCTAssertEqual(try XCTUnwrap(result.depth.values.min()), 0, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(result.depth.values.max()), 1, accuracy: 1e-5)
        XCTAssertTrue(result.depth.values.allSatisfy { $0.isFinite })

        // Structure in both axes. A prediction that never happened, or one read
        // back through a shorn buffer, flattens these towards nothing; measured
        // 0.26 down and 0.55 across on this picture.
        let h = result.depth.rows, w = result.depth.cols
        let v = result.depth.values
        func mean(_ s: [Float]) -> Float { s.reduce(0, +) / Float(s.count) }
        let rows = (0..<h).map { y in mean(Array(v[(y * w)..<((y + 1) * w)])) }
        let cols = (0..<w).map { x in mean((0..<h).map { v[$0 * w + x] }) }
        XCTAssertGreaterThan(try XCTUnwrap(rows.max()) - (try XCTUnwrap(rows.min())), 0.05,
                             "no vertical structure — the model probably did not run")
        XCTAssertGreaterThan(try XCTUnwrap(cols.max()) - (try XCTUnwrap(cols.min())), 0.05,
                             "no horizontal structure — the model probably did not run")

        backend.unload()
    }
}
