import Foundation
import ReliefCore

/// The one path the fixtures never covered end to end: image -> Core ML ->
/// upsample -> normalize, against the reference's own `03_depth_raw`.
/// Every stage test feeds the recorded depth, so a fault here passes them all.
func checkCoreMLDepth() {
    let root = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/tests/golden_1536")
    guard let f = (try? GoldenFixture.discover(in: root))?.first,
          let rgb = try? f.plane("00_input"),
          let ref = try? f.plane("03_depth_raw") else { print("no fixture"); return }

    let res = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/ios-app/2DConverterApp/Tactura/Resources")
    guard let pe = PositionEmbedding(contentsOf: res.appendingPathComponent("base_1x1370x1024.f32"))
    else { print("no position grid"); return }
    let backend = CoreMLDepthBackend(
        modelURL: res.appendingPathComponent("dav2_large_multifunction_f16.mlpackage"),
        positionEmbedding: pe)

    let lab = Preprocess.rgb2lab(rgb)
    do {
        let got = try backend.predict(rgb: rgb, lab: lab)
        let d = Compare.divergence(got.depth, ref)
        print("\n--- Core ML depth vs reference 03_depth_raw ---")
        print("  \(got.notes)")
        print(String(format: "  maxErr %.4f   mean %.4f   corr %.6f   roughness %.2fx",
                     d.maxAbsErr, d.meanAbsErr, d.correlation, d.roughnessRatio))
    } catch {
        print("  depth failed: \(error)")
    }
}
