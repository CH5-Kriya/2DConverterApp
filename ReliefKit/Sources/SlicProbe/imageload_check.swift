import Foundation
import ReliefCore

/// The one thing the stage fixtures never covered: image *loading*.
///
/// Every stage comparison feeds `00_input`, the already-resized array, so a
/// difference in how the JPEG is decoded and downscaled would pass every test
/// and still change the relief. The reference uses PIL's LANCZOS; the app uses
/// CGImageSource's thumbnail path, chosen so the full-resolution bitmap is
/// never resident.
func checkImageLoad() {
    print("\n--- image load: CGImageSource vs PIL LANCZOS ---")
    let jpeg = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/assets/samples/nyodog.jpeg")
    guard let data = try? Data(contentsOf: jpeg),
          let mine = ReliefImage.load(data: data, maxEdge: 1536),
          let refData = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/nyodog_pil_1536.f32"))
    else { print("  inputs missing"); return }

    let expected: [Float] = refData.withUnsafeBytes {
        Array(UnsafeBufferPointer(
            start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
            count: refData.count / 4))
    }
    print("  mine \(mine.rows)x\(mine.cols)x3 = \(mine.count) values")
    print("  PIL  \(expected.count) values")
    guard mine.count == expected.count else {
        print("  DIFFERENT SIZE — the decoders disagree on output dimensions")
        return
    }
    var maxErr = 0.0, sum = 0.0
    for i in 0..<mine.count {
        let d = abs(Double(mine.values[i]) - Double(expected[i]))
        maxErr = Swift.max(maxErr, d); sum += d
    }
    print(String(format: "  maxErr %.4f   mean %.5f   (values are 0-1)",
                 maxErr, sum / Double(mine.count)))
}
