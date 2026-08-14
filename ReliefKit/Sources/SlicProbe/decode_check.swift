import CoreGraphics
import Foundation
import ImageIO
import ReliefCore

/// Decode only, no resize: isolates the JPEG decoder from the resampler.
func checkDecodeOnly() {
    print("\n--- decode only (no resize), vs PIL ---")
    let jpeg = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/assets/samples/nyodog.jpeg")
    guard let data = try? Data(contentsOf: jpeg),
          let plane = ReliefImage.load(data: data, maxEdge: 100_000),  // no downscale
          let ref = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/nyodog_pil_fullres.u8"))
    else { print("  inputs missing"); return }

    guard plane.count == ref.count else {
        print("  size mismatch: \(plane.count) vs \(ref.count)"); return
    }
    var maxErr = 0, sum = 0, diffs = 0
    ref.withUnsafeBytes { raw in
        for i in 0..<plane.count {
            let got = Int((plane.values[i] * 255).rounded())
            let d = abs(got - Int(raw[i]))
            if d != 0 { diffs += 1 }
            maxErr = Swift.max(maxErr, d); sum += d
        }
    }
    print(String(format: "  %d of %d samples differ (%.3f%%)  max %d step(s)  mean %.4f steps",
                 diffs, plane.count, Double(diffs)/Double(plane.count)*100,
                 maxErr, Double(sum)/Double(plane.count)))
}
