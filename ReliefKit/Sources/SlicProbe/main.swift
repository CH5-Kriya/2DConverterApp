import Foundation
import ReliefCore
import ReliefNumerics

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1]
               : "/Users/elliezer/Documents/Projects/Challenge 5/test_python/tests/golden",
               isDirectory: true)

for fixture in try GoldenFixture.discover(in: root) {
    for variant in ["02_slic_nocc", "02_slic_raw"] {
    let rawURL = fixture.directory.appendingPathComponent("\(variant).i32")
    guard let data = try? Data(contentsOf: rawURL) else { continue }

    let input = try fixture.plane("00_input")
    let n = input.rows * input.cols
    let expected: [Int32] = data.withUnsafeBytes {
        Array(UnsafeBufferPointer(
            start: $0.baseAddress!.assumingMemoryBound(to: Int32.self), count: n))
    }

    var got = [Int32](repeating: 0, count: n)
    let cfg = fixture.manifest.config.segment
    let regions = input.values.withUnsafeBufferPointer { src in
        got.withUnsafeMutableBufferPointer { dst in
            relief_slic(src.baseAddress!, input.rows, input.cols,
                        Int32(cfg.nSegments), cfg.compactness, cfg.sigma,
                        variant == "02_slic_raw" ? 1 : 0,
                        dst.baseAddress!)
        }
    }

    let expectedN = Int(expected.max() ?? 0) + 1
    var same = 0
    for i in 0..<n where got[i] == expected[i] { same += 1 }
    let agree = Double(same) / Double(n)

    if variant == "02_slic_raw" {
        // Full segmentation: SLIC -> merge -> absorb -> pack, against the
        // pipeline's own 02_labels and 02_albedo.
        let labFixture = try fixture.plane("01_lab")
        var merged = [Int32](repeating: 0, count: n)
        var albedo = [Float](repeating: 0, count: 4096)
        let regions2 = labFixture.values.withUnsafeBufferPointer { lb in
            got.withUnsafeBufferPointer { src in
                merged.withUnsafeMutableBufferPointer { dst in
                    albedo.withUnsafeMutableBufferPointer { alb in
                        relief_merge_regions(lb.baseAddress!, src.baseAddress!,
                                             labFixture.rows, labFixture.cols,
                                             cfg.mergeThreshold,
                                             Int32(cfg.minSegmentPx),
                                             dst.baseAddress!, alb.baseAddress!,
                                             4096)
                    }
                }
            }
        }
        let refLabels = try fixture.plane("02_labels")
        let refAlbedo = try fixture.plane("02_albedo")
        var sameL = 0
        for i in 0..<n where Int32(refLabels.values[i]) == merged[i] { sameL += 1 }
        var maxAlbedoErr = 0.0
        if Int(regions2) == refAlbedo.count {
            for i in 0..<Int(regions2) {
                maxAlbedoErr = Swift.max(maxAlbedoErr,
                    abs(Double(albedo[i]) - Double(refAlbedo.values[i])))
            }
        }
        print(String(format: "%-24s FULL SEG       regions %4d vs %4d   agreement %.4f%%   albedo maxErr %.3e",
                     (fixture.sample as NSString).utf8String!, Int(regions2),
                     refAlbedo.count, Double(sameL)/Double(n)*100, maxAlbedoErr))
    }

    print(String(format: "%-24s %-14s regions %4d vs %4d   agreement %.4f%%",
                 (fixture.sample as NSString).utf8String!,
                 (variant as NSString).utf8String!, Int(regions),
                 expectedN, agree * 100))
    }
}

meshFromFixtureInput()
runFullOnJPEG()
