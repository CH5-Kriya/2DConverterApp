import XCTest
@testable import ReliefCore
import ReliefNumerics

/// `rgb2lab` is hand-ported rather than delegated to OpenCV, because
/// `cv::cvtColor(COLOR_RGB2Lab)` uses different constants and scaling than
/// scikit-image and would diverge from the reference. That makes it one of the
/// few genuinely re-implemented pieces, so it gets its own fixture.
final class PreprocessTests: XCTestCase {

    private func loadFixture(_ name: String, count: Int) throws -> [Float] {
        let url = Bundle.module.url(forResource: name, withExtension: "f32",
                                    subdirectory: "Fixtures")
        guard let url else {
            throw XCTSkip("fixture \(name).f32 not bundled")
        }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, count * MemoryLayout<Float>.size)
        return data.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer(
                start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                count: count))
        }
    }

    func testRgb2LabMatchesScikitImage() throws {
        let rows = 64, cols = 64, n = rows * cols * 3
        let rgb = Plane(rows: rows, cols: cols, channels: 3,
                        values: try loadFixture("rgb2lab_input", count: n))
        let expected = Plane(rows: rows, cols: cols, channels: 3,
                             values: try loadFixture("rgb2lab_expected", count: n))

        let got = Preprocess.rgb2lab(rgb)
        let d = Compare.divergence(got, expected)

        // L spans [0, 100] and a/b roughly [-86, 95], so a 1e-6 *absolute*
        // bound is under one ulp of float32 at that magnitude and cannot be
        // met by any implementation. The meaningful bar is ~1e-5 relative,
        // which is 1e-3 absolute here.
        XCTAssertLessThan(d.maxAbsErr, 1e-3,
                          "max abs err \(d.maxAbsErr) (mean \(d.meanAbsErr))")
        XCTAssertGreaterThan(d.correlation, 0.999999999)
    }

    /// The lightness channel is what stage 1 actually forwards, and it is
    /// normalised to [0, 1] — so here the plan's 1e-6 bound is the right one.
    func testLightnessMatchesAtPipelineScale() throws {
        let rows = 64, cols = 64, n = rows * cols * 3
        let rgb = Plane(rows: rows, cols: cols, channels: 3,
                        values: try loadFixture("rgb2lab_input", count: n))
        let expected = Plane(rows: rows, cols: cols, channels: 3,
                             values: try loadFixture("rgb2lab_expected", count: n))

        let got = Preprocess.lightness(fromLab: Preprocess.rgb2lab(rgb))
        var ref = [Float](repeating: 0, count: rows * cols)
        for i in 0..<(rows * cols) {
            ref[i] = Swift.min(Swift.max(expected.values[i * 3] / 100.0, 0), 1)
        }
        let d = Compare.divergence(got, Plane(rows: rows, cols: cols, values: ref))

        XCTAssertTrue(Compare.passes(d, .exact(maxAbsErr: 1e-6)),
                      "max abs err \(d.maxAbsErr)")
    }
}

/// The whole strategy in the plan rests on being able to *call* OpenCV's
/// implementations rather than reimplement them. If this fails, that premise is
/// false and it should surface here rather than three stages later.
final class OpenCVLinkTests: XCTestCase {
    func testVendoredOpenCVRunsTheFunctionsThePipelineNeeds() {
        let result = relief_opencv_selftest()
        switch result {
        case 0: break
        case 1: XCTFail("cv::CLAHE on 16-bit failed")
        case 2: XCTFail("cv::ximgproc::guidedFilter failed — contrib missing?")
        case 3: XCTFail("cv::distanceTransform(DIST_L2, 5) failed")
        default: XCTFail("unknown selftest failure \(result)")
        }
    }
}
