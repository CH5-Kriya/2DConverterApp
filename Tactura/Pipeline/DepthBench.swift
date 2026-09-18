import Foundation
import ReliefCore
import UIKit

/// `--depth-bench`: time dav2-small against dav2-large on this device, print,
/// and quit. Does nothing without the launch argument.
///
///     xcrun devicectl device process launch --device <udid> --console \
///         com.elliezer.kriya.-DConverterApp --depth-bench
///
/// It lives in the app rather than beside `DepthBenchTests` because the package
/// can't carry it onto hardware: tool-hosted XCTest needs a host application,
/// so a device run of that bundle is refused outright. And hardware is the only
/// place worth measuring — both backends force `.cpuOnly` on a simulator, which
/// has no ANE, so a simulator number is a CPU cost ratio and nothing more.
///
/// Needs both packages in the bundle. The large one is excluded from iOS builds
/// by `EXCLUDED_SOURCE_FILE_NAMES[sdk=iphone*]`, so build with that setting
/// emptied on the command line — see the header of `DepthBenchTests`.
enum DepthBench {

    static let argument = "--depth-bench"

    /// Off the main thread deliberately: a bench that holds up the first frame
    /// for ten seconds is a launch-watchdog kill, not a measurement.
    static func runIfRequested() {
        guard CommandLine.arguments.contains(argument) else { return }
        Task.detached(priority: .userInitiated) {
            run(runs: 3)
            exit(0)
        }
    }

    /// Working memory, not weights: Core ML maps those from the `.mlmodelc` and
    /// clean file-backed pages stay out of `phys_footprint`. The package size on
    /// disk is the honest figure for what the weights cost.
    nonisolated private static func footprintMB() -> Double {
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

    nonisolated private static func measure(_ backend: DepthBackend, rgb: Plane,
                                            runs: Int) -> (first: Double, warm: [Double],
                                                           peak: Double)? {
        do {
            var peak = footprintMB()
            let t0 = Date()
            _ = try backend.predict(rgb: rgb, lab: rgb)
            let first = Date().timeIntervalSince(t0)
            peak = max(peak, footprintMB())

            var warm: [Double] = []
            for _ in 0..<runs {
                let t = Date()
                _ = try backend.predict(rgb: rgb, lab: rgb)
                warm.append(Date().timeIntervalSince(t))
                peak = max(peak, footprintMB())
            }
            return (first, warm, peak)
        } catch {
            print("BENCH \(backend.name) FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated private static func run(runs: Int) {
        // The same picture as the XCTest bench, capped to the same 700 px so the
        // two sets of numbers describe the same work.
        guard let art = UIImage(named: "HeroArtwork"),
              let png = art.pngData(),
              let rgb = ReliefImage.load(data: png, maxEdge: 700) else {
            print("BENCH FAILED: no hero artwork")
            return
        }

        let baseline = footprintMB()
        print("BENCH device \(UIDevice.current.model) \(UIDevice.current.systemVersion)"
              + "  input \(rgb.rows)x\(rgb.cols)  runs \(runs)"
              + "  baseline \(Int(baseline)) MB")

        var samples: [(String, (first: Double, warm: [Double], peak: Double))] = []

        if let small = AppleDepthBackend.bundled() {
            if let s = measure(small, rgb: rgb, runs: runs) { samples.append(("dav2-small", s)) }
            small.unload()
        } else {
            print("BENCH dav2-small MISSING from the bundle")
        }

        if let large = CoreMLDepthBackend.bundled() {
            if let l = measure(large, rgb: rgb, runs: runs) { samples.append(("dav2-large", l)) }
            large.unload()
        } else {
            print("BENCH dav2-large MISSING from the bundle"
                  + " — build with EXCLUDED_SOURCE_FILE_NAMES[sdk=iphone*] emptied")
        }

        for (label, x) in samples {
            let warm = x.warm.map { String(format: "%.3f", $0) }.joined(separator: " ")
            let median = x.warm.sorted()[x.warm.count / 2]
            print(String(format: "BENCH %@  first %.3fs  warm median %.3fs  [%@]  peak %d MB",
                         label, x.first, median, warm, Int(x.peak - baseline)))
        }
        if samples.count == 2 {
            let s = samples[0].1, l = samples[1].1
            print(String(format: "BENCH ratio large/small  warm %.1fx  first %.1fx",
                         l.warm.sorted()[l.warm.count / 2] / s.warm.sorted()[s.warm.count / 2],
                         l.first / s.first))
        }
    }
}
