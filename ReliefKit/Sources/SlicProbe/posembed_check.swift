import Foundation
import ReliefCore

/// The app has to reproduce `reference_pos_embed` exactly, so it is checked
/// against tensors dumped straight out of PyTorch.
func checkPositionEmbedding(fixtures: URL) {
    print("\n--- position embeddings vs PyTorch ---")
    guard let pe = PositionEmbedding(
        contentsOf: fixtures.appendingPathComponent("base_1x1370x1024.f32")) else {
        print("  base grid not found at \(fixtures.path)"); return
    }

    for (name, hw) in [("518x518", (518, 518)), ("518x784", (518, 784)),
                       ("742x518", (742, 518)), ("518x1008", (518, 1008))] {
        let url = fixtures.appendingPathComponent("pos_embed_\(name).f32")
        guard let data = try? Data(contentsOf: url) else { continue }
        let expected: [Float] = data.withUnsafeBytes {
            Array(UnsafeBufferPointer(
                start: $0.baseAddress!.assumingMemoryBound(to: Float.self),
                count: data.count / 4))
        }
        let got = pe.embedding(height: hw.0, width: hw.1)
        guard got.count == expected.count else {
            print("  \(name)  FAIL  \(got.count) values vs \(expected.count)")
            continue
        }
        var maxErr = 0.0, sum = 0.0
        for i in 0..<got.count {
            let d = abs(Double(got[i]) - Double(expected[i]))
            maxErr = Swift.max(maxErr, d); sum += d
        }
        let mean = sum / Double(got.count)
        print(String(format: "  %-9s %@  %d values  maxErr %.3e  mean %.3e",
                     (name as NSString).utf8String!,
                     maxErr < 1e-5 ? "ok  " : "FAIL", got.count, maxErr, mean))
    }
}
