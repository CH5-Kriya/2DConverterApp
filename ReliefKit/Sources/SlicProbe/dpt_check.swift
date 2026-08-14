import Foundation
import ReliefCore
import ReliefNumerics

func checkDPTPreprocess(root: URL) {
    print("\n--- DPT preprocessing vs transformers ---")
    let dir = root.deletingLastPathComponent().appendingPathComponent("dpt_fixtures")
    guard let fixtures = try? GoldenFixture.discover(in: root) else { return }
    for fixture in fixtures {
        let url = dir.appendingPathComponent("\(fixture.sample)_pixel_values.f32")
        guard let data = try? Data(contentsOf: url),
              let rgb = try? fixture.plane("00_input") else { continue }
        let expected: [Float] = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(
                start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
                count: data.count / 4))
        }
        let size = PositionEmbedding.processorSize(imageHeight: rgb.rows,
                                                   imageWidth: rgb.cols)
        var got = [Float](repeating: 0, count: size.height * size.width * 3)
        rgb.values.withUnsafeBufferPointer { src in
            got.withUnsafeMutableBufferPointer { dst in
                relief_dpt_preprocess(src.baseAddress!, rgb.rows, rgb.cols,
                                      Int32(size.height), Int32(size.width),
                                      dst.baseAddress!)
            }
        }
        guard got.count == expected.count else {
            print("  \(fixture.sample)  FAIL shape \(size) -> \(got.count) vs \(expected.count)")
            continue
        }
        var maxErr = 0.0, sum = 0.0
        for i in 0..<got.count {
            let d = abs(Double(got[i]) - Double(expected[i]))
            maxErr = Swift.max(maxErr, d); sum += d
        }
        print(String(format: "  %-24s %@ %dx%d  maxErr %.3e  mean %.3e",
                     (fixture.sample as NSString).utf8String!,
                     maxErr < 1e-4 ? "ok  " : "FAIL", size.height, size.width,
                     maxErr, sum / Double(got.count)))
    }
}
