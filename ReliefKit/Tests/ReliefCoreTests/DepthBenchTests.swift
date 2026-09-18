import Foundation
import XCTest
@testable import ReliefCore

/// Large vs small, on whatever machine the test bundle is running on.
///
/// Both packages are too big to be fixtures, so this runs only when the three
/// env vars point at them. On macOS that is just `swift test`. For a simulator
/// run they have to be set *inside* the booted simulator — xcodebuild's
/// `TEST_RUNNER_` prefix does not reach an SPM test bundle, and the test skips
/// silently if you try it that way:
///
///     xcrun simctl boot 'iPad Pro 13-inch (M5)'
///     xcrun simctl spawn booted launchctl setenv \
///         TACTURA_SMALL_MODEL /path/DepthAnythingV2SmallF16.mlmodelc
///     …same for TACTURA_LARGE_MODEL and TACTURA_POS_EMBED…
///     xcodebuild test -scheme ReliefKit-Package \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///       -only-testing:ReliefCoreTests/DepthBenchTests
///
/// `launchctl setenv` lasts as long as that boot.
///
/// Point them at `.mlmodelc` directories, not `.mlpackage`: an uncompiled
/// package makes the first prediction pay a `MLModel.compileModel` that the
/// shipping app never pays, because Xcode compiles bundled models at build time.
///
/// Caveat that outranks every number this prints: **a simulator has no Neural
/// Engine**, and both backends force `.cpuOnly` there (the Metal path fails
/// validation on these DPT graphs). A simulator run therefore measures the
/// host Mac's CPU, not an iPad's ANE, so treat it as a cost ratio between the
/// two models rather than as a prediction of on-device latency.
final class DepthBenchTests: XCTestCase {

    /// Wall time and peak memory for one backend over `runs` predictions.
    private struct Sample {
        let load: Double        // first predict: model load + inference
        let warm: [Double]      // every predict after that
        let footprintMB: Double // peak process footprint seen during the run

        var median: Double { warm.sorted()[warm.count / 2] }
    }

    /// The app's own resident footprint, which is what an iPad would run out
    /// of — `phys_footprint` is the counter jetsam reads.
    ///
    /// It undercounts these two badly: Core ML maps the weights from the
    /// `.mlmodelc`, and clean file-backed pages are not in the footprint. Read
    /// the printed number as activation/working memory only; for the weights,
    /// the package size on disk is the honest figure.
    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size
                                           / MemoryLayout<natural_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return ok == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private func measure(_ backend: DepthBackend, rgb: Plane, lab: Plane,
                         runs: Int) throws -> Sample {
        var peak = footprintMB()
        let t0 = Date()
        _ = try backend.predict(rgb: rgb, lab: lab)
        let load = Date().timeIntervalSince(t0)
        peak = Swift.max(peak, footprintMB())

        var warm: [Double] = []
        for _ in 0..<runs {
            let t = Date()
            _ = try backend.predict(rgb: rgb, lab: lab)
            warm.append(Date().timeIntervalSince(t))
            peak = Swift.max(peak, footprintMB())
        }
        return Sample(load: load, warm: warm, footprintMB: peak)
    }

    func testLargeVersusSmall() throws {
        let env = ProcessInfo.processInfo.environment
        guard let smallPath = env["TACTURA_SMALL_MODEL"],
              let largePath = env["TACTURA_LARGE_MODEL"],
              let pePath = env["TACTURA_POS_EMBED"] else {
            throw XCTSkip("set TACTURA_SMALL_MODEL / TACTURA_LARGE_MODEL / "
                          + "TACTURA_POS_EMBED to compare the two")
        }
        let runs = Int(env["TACTURA_BENCH_RUNS"] ?? "") ?? 3

        // The same picture the small-model test uses, at the working resolution
        // the app actually converts at, so the resize and the read-back either
        // side of the model are sized the way they are in a real run.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // ReliefCoreTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // ReliefKit
            .deletingLastPathComponent()    // repo root
        let artwork = repo.appending(path:
            "Tactura/Assets.xcassets/HeroArtwork.imageset/hero-artwork.png")
        let workRes = Int(env["TACTURA_WORK_RES"] ?? "") ?? ReliefConfig().preprocess.workRes
        let rgb = try XCTUnwrap(ReliefImage.load(data: try Data(contentsOf: artwork),
                                                 maxEdge: workRes))

        let baseline = footprintMB()
        print("BENCH input \(rgb.rows)x\(rgb.cols)  runs \(runs)  baseline \(Int(baseline)) MB")
        #if targetEnvironment(simulator)
        print("BENCH NOTE simulator: CPU only, no ANE — ratios, not device latency")
        #endif

        let small = AppleDepthBackend(modelURL: URL(fileURLWithPath: smallPath))
        let s = try measure(small, rgb: rgb, lab: rgb, runs: runs)
        small.unload()

        let pe = try XCTUnwrap(PositionEmbedding(contentsOf: URL(fileURLWithPath: pePath)))
        let large = CoreMLDepthBackend(modelURL: URL(fileURLWithPath: largePath),
                                       positionEmbedding: pe)
        let l = try measure(large, rgb: rgb, lab: rgb, runs: runs)
        large.unload()

        for (label, x) in [("dav2-small", s), ("dav2-large", l)] {
            let warm = x.warm.map { String(format: "%.2f", $0) }.joined(separator: " ")
            print(String(format: "BENCH %@  first %.2fs  warm median %.2fs  [%@]  peak %d MB",
                         label, x.load, x.median, warm, Int(x.footprintMB - baseline)))
        }
        print(String(format: "BENCH ratio large/small  warm %.1fx  first %.1fx",
                     l.median / s.median, l.load / s.load))
    }
}
