import XCTest
@testable import ReliefCore

/// The checkpoint is what a project *is* between the conversion and the export,
/// so these hold it to the two things that matters: the region map and the
/// foreground mask come back byte-exact, and the four Z_* layers come back
/// within the quantiser's own resolution.
final class CheckpointTests: XCTestCase {

    /// Deterministic, so a rerun is comparable to a rerun.
    private struct Noise {
        private var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> Float {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Float(state % 100_000) / 100_000
        }
    }

    /// A 16-bit index over the plane's own range: worst case half a step, plus
    /// the float32 rounding of the two scale factors either side of it, which
    /// the measured round trip puts at 0.504.
    private let tolerance: Float = 0.51 / 65535

    private func fixture(rows: Int = 97, cols: Int = 131,
                         regionCount: Int = 412) -> ReliefCheckpoint {
        var noise = Noise()
        let n = rows * cols
        func plane(scale: Float, offset: Float) -> Plane {
            Plane(rows: rows, cols: cols,
                  values: (0..<n).map { _ in noise.next() * scale + offset })
        }

        // Not all four in [0, 1]: the SFS layer is unbounded before the blend
        // normalises it, and a codec that only ever saw unit fields would not
        // be tested on the one that matters.
        return ReliefCheckpoint(
            labels: Plane(rows: rows, cols: cols,
                          values: (0..<n).map { Float($0 % regionCount) }),
            regionCount: regionCount,
            mask: (0..<n).map { UInt8($0 % 3 == 0 ? 0 : 1) },
            zAi: plane(scale: 1, offset: 0),
            zRough: plane(scale: 250, offset: -120),
            zMain: plane(scale: 1, offset: 0),
            zDetail: plane(scale: 1, offset: 0),
            routeMode: Routing.illustration,
            depthBackend: "dav2-large-f16")
    }

    private func assertClose(_ expected: Plane, _ actual: Plane,
                             _ label: String, file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(expected.rows, actual.rows, "\(label) rows", file: file, line: line)
        XCTAssertEqual(expected.cols, actual.cols, "\(label) cols", file: file, line: line)

        var low = Float.greatestFiniteMagnitude, high = -Float.greatestFiniteMagnitude
        for value in expected.values where value.isFinite {
            low = min(low, value)
            high = max(high, value)
        }
        let span = max(high - low, 1e-6)

        var worst: Float = 0
        for i in 0..<expected.count where expected.values[i].isFinite {
            worst = max(worst, abs(expected.values[i] - actual.values[i]) / span)
        }
        XCTAssertLessThanOrEqual(worst, tolerance,
                                 "\(label) drifted \(worst / (1 / 65535)) quantisation steps",
                                 file: file, line: line)
    }

    func testRoundTripPreservesEverythingTheBlendReads() throws {
        let original = fixture()
        let restored = try XCTUnwrap(ReliefCheckpoint.decode(original.encoded()))

        XCTAssertEqual(restored.rows, original.rows)
        XCTAssertEqual(restored.cols, original.cols)
        XCTAssertEqual(restored.regionCount, original.regionCount)
        XCTAssertEqual(restored.routeMode, original.routeMode)
        XCTAssertEqual(restored.depthBackend, original.depthBackend)

        // Both are read as indices, not as numbers, so neither may be
        // approximated: a label that rounds into its neighbour merges two
        // regions in `enforceOrdering`, and a bent mask moves the silhouette.
        XCTAssertEqual(restored.labels.values, original.labels.values)
        XCTAssertEqual(restored.mask, original.mask)

        assertClose(original.zAi, restored.zAi, "zAi")
        assertClose(original.zRough, restored.zRough, "zRough")
        assertClose(original.zMain, restored.zMain, "zMain")
        assertClose(original.zDetail, restored.zDetail, "zDetail")
    }

    /// `Volume.shapeFromShading` can leave debris in an unconverged cell. It
    /// must not come back as a NaN, which spreads across the whole plane the
    /// first time `normalize01` takes a min over it.
    func testNonFiniteSamplesComeBackFinite() throws {
        let base = fixture(rows: 8, cols: 8, regionCount: 4)
        var values = base.zDetail.values
        values[3] = .nan
        values[4] = .infinity
        values[5] = -.infinity
        let checkpoint = ReliefCheckpoint(
            labels: base.labels, regionCount: base.regionCount, mask: base.mask,
            zAi: base.zAi, zRough: base.zRough, zMain: base.zMain,
            zDetail: Plane(rows: 8, cols: 8, values: values),
            routeMode: base.routeMode, depthBackend: base.depthBackend)

        let restored = try XCTUnwrap(ReliefCheckpoint.decode(checkpoint.encoded()))
        XCTAssertTrue(restored.zDetail.values.allSatisfy { $0.isFinite })
    }

    /// A flat layer is what a disabled solver produces, and it is the case the
    /// quantiser's span divides by.
    func testConstantPlaneSurvivesExactly() throws {
        let n = 64
        let flat = Plane(rows: 8, cols: 8, values: [Float](repeating: 0.375, count: n))
        let checkpoint = ReliefCheckpoint(
            labels: Plane(rows: 8, cols: 8, values: [Float](repeating: 0, count: n)),
            regionCount: 1, mask: [UInt8](repeating: 1, count: n),
            zAi: flat, zRough: flat, zMain: flat, zDetail: flat,
            routeMode: Routing.realistic, depthBackend: "layers-classical")

        let restored = try XCTUnwrap(ReliefCheckpoint.decode(checkpoint.encoded()))
        XCTAssertTrue(restored.zMain.values.allSatisfy { $0 == 0.375 })
    }

    /// Past 65535 regions the labels switch to 32 bits. Nothing the segmenter
    /// produces is near that, but the format branches on it and a branch the
    /// tests never take is a branch that is not there.
    func testWideLabelsStayExact() throws {
        let n = 16
        let regionCount = 70_000
        let labels = Plane(rows: 4, cols: 4,
                           values: (0..<n).map { Float(regionCount - 1 - $0) })
        let plane = Plane(rows: 4, cols: 4, values: (0..<n).map { Float($0) / Float(n) })
        let checkpoint = ReliefCheckpoint(
            labels: labels, regionCount: regionCount,
            mask: [UInt8](repeating: 1, count: n),
            zAi: plane, zRough: plane, zMain: plane, zDetail: plane,
            routeMode: Routing.realistic, depthBackend: "layers-classical")

        let restored = try XCTUnwrap(ReliefCheckpoint.decode(checkpoint.encoded()))
        XCTAssertEqual(restored.labels.values, labels.values)
        XCTAssertEqual(restored.regionCount, regionCount)
    }

    /// A checkpoint is a file, and a file can be half-written or from another
    /// build. Every one of these has to answer `nil` rather than crash, because
    /// `nil` is what sends the workspace back to converting from the import.
    func testRefusesDamagedInput() {
        let good = fixture(rows: 8, cols: 8, regionCount: 4).encoded()

        XCTAssertNil(ReliefCheckpoint.decode(Data()))
        XCTAssertNil(ReliefCheckpoint.decode(Data([0, 1, 2, 3, 4, 5, 6, 7, 8])))
        XCTAssertNil(ReliefCheckpoint.decode(good.prefix(good.count / 2)))
        XCTAssertNil(ReliefCheckpoint.decode(good.dropLast(8)))

        var wrongMagic = good
        wrongMagic[wrongMagic.startIndex] ^= 0xFF
        XCTAssertNil(ReliefCheckpoint.decode(wrongMagic))
    }
}
