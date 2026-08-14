import Foundation
import ReliefNumerics

/// Isolates the resize from the normalisation: compares the resampled uint8
/// directly against PIL's, so a difference cannot be blamed on the ImageNet
/// scaling that follows it.
func checkResizeAgainstPIL() {
    print("\n--- resize only, vs PIL ---")
    guard let inData = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/pil_input.u8")),
          let refData = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/pil_resized.u8"))
    else { print("  fixtures missing"); return }

    let (srcH, srcW) = (512, 768)
    let (dstH, dstW) = (518, 784)

    var rgb = [Float](repeating: 0, count: srcH * srcW * 3)
    inData.withUnsafeBytes { raw in
        for i in 0..<(srcH * srcW * 3) {
            rgb[i] = Float(raw[i]) / 255.0
        }
    }

    // Run the real preprocessing, then invert the ImageNet normalisation to get
    // back to the resampled 8-bit values PIL produced.
    var chw = [Float](repeating: 0, count: dstH * dstW * 3)
    rgb.withUnsafeBufferPointer { s in
        chw.withUnsafeMutableBufferPointer { d in
            relief_dpt_preprocess(s.baseAddress!, srcH, srcW,
                                  Int32(dstH), Int32(dstW), d.baseAddress!)
        }
    }
    let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
    let plane = dstH * dstW
    var diffs = 0, maxDiff = 0
    refData.withUnsafeBytes { raw in
        for i in 0..<plane {
            for c in 0..<3 {
                let v = chw[c * plane + i] * std[c] + mean[c]
                let got = Int((v * 255).rounded())
                let want = Int(raw[i * 3 + c])
                let d = abs(got - want)
                if d != 0 { diffs += 1; maxDiff = Swift.max(maxDiff, d) }
            }
        }
    }
    let total = plane * 3
    print(String(format: "  %d of %d values differ (%.4f%%), max %d step(s)",
                 diffs, total, Double(diffs) / Double(total) * 100, maxDiff))
}
