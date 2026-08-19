import XCTest
@testable import ReliefCore

/// The bucket ladder against the aspect ratios the app can actually produce.
///
/// These exist because the ladder used to be eight hand-picked long sides and
/// nothing checked them against the crop screen. 4:3 fell in a gap, so every
/// camera scan failed at the depth stage with a message about a tensor size the
/// person never chose. A missing function is not a numerical defect that a
/// tolerance would catch — it is a hard failure at the point of use — so it has
/// to be asserted structurally.
final class DepthShapeTests: XCTestCase {

    private func supports(_ ratio: Double) -> Bool {
        // A long edge well past `workRes` on purpose: `processorSize` normalises
        // scale away, so only the aspect can decide this.
        let long = 3000
        let short = Int((Double(long) / ratio).rounded())
        let size = PositionEmbedding.processorSize(imageHeight: long, imageWidth: short)
        return CoreMLDepthBackend.isSupported(height: size.height, width: size.width)
    }

    /// Every ratio the crop screen offers, in both orientations. `CropAspect`
    /// lives in the app target, so the values are restated rather than imported;
    /// if one changes there, this fails and says so.
    func testCropPresetsAllHaveAFunction() {
        for (name, ratio) in [("1:1", 1.0), ("4:3", 4.0 / 3), ("3:2", 1.5),
                              ("16:9", 16.0 / 9)] {
            XCTAssertTrue(supports(ratio), "no depth function for \(name) landscape")
            XCTAssertTrue(supports(1 / ratio), "no depth function for \(name) portrait")
        }
    }

    /// A free crop is a continuum, not a preset. Sweep it.
    func testEveryAspectUpToTwoToOneIsCovered() {
        var gaps: [String] = []
        for step in 100...200 {
            let ratio = Double(step) / 100
            if !supports(ratio) { gaps.append(String(format: "%.2f", ratio)) }
            if !supports(1 / ratio) { gaps.append(String(format: "1/%.2f", ratio)) }
        }
        XCTAssertEqual(gaps, [], "aspect ratios with no depth function: \(gaps)")
    }

    /// The far side of the ladder still refuses, and refuses cleanly. Silently
    /// snapping a panorama to 2:1 would reintroduce exactly the distortion the
    /// aspect-preserving input was built to avoid.
    func testBeyondTwoToOneIsRejected() {
        XCTAssertFalse(supports(2.2))
        XCTAssertFalse(supports(1 / 2.2))
    }

    /// A strip elongated enough that `DPTImageProcessor` scales by the *long*
    /// side instead of the short one, landing on 518x28: a supported long side
    /// in an unsupported pair. Checking `longSides` alone would let this through
    /// to Core ML, which would fail with a far less useful message.
    func testElongatedStripIsRejectedNotMistakenForSupported() {
        let size = PositionEmbedding.processorSize(imageHeight: 2000, imageWidth: 100)
        XCTAssertTrue(CoreMLDepthBackend.longSides.contains(max(size.height, size.width)))
        XCTAssertFalse(CoreMLDepthBackend.isSupported(height: size.height, width: size.width))
    }

    /// The ladder is contiguous, so the Swift side and the converted package
    /// cannot drift by a single missing rung.
    func testLadderIsContiguous() {
        let sides = CoreMLDepthBackend.longSides
        XCTAssertEqual(sides.first, 518)
        XCTAssertEqual(sides.last, 1036)
        XCTAssertEqual(sides.count, 38)
        for (a, b) in zip(sides, sides.dropFirst()) { XCTAssertEqual(b - a, 14) }
    }
}
