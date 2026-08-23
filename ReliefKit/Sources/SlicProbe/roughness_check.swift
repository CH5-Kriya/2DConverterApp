import Foundation
import ReliefCore

/// Max-error and correlation are blind to high-frequency noise: a layer can
/// match to 1e-3 everywhere and still be visibly rougher. This measures the
/// thing that actually reaches a fingertip -- mean gradient magnitude.
func checkLayerRoughness() {
    let root = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/tests/golden_1536")
    do {
        let all = try GoldenFixture.discover(in: root)
        print("  discovered \(all.count) fixture(s): \(all.map(\.sample))")
    } catch { print("  discover threw: \(error)") }
    guard let f = (try? GoldenFixture.discover(in: root))?.first else {
        print("  no fixture found at \(root.path)"); return
    }
    guard let rgb = try? f.plane("00_input") else {
        print("  fixture \(f.sample) has no 00_input"); return
    }

    func grad(_ p: Plane) -> Double {
        var acc = 0.0
        for y in 1..<(p.rows-1) {
            for x in 1..<(p.cols-1) {
                let i = y * p.cols + x
                let gx = Double(p.values[i+1] - p.values[i-1]) / 2
                let gy = Double(p.values[i+p.cols] - p.values[i-p.cols]) / 2
                acc += (gx*gx + gy*gy).squareRoot()
            }
        }
        return acc / Double((p.rows-2) * (p.cols-2))
    }

    var config = f.manifest.config
    config.mesh.reliefMm = 30
    let res = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/ios-app/2DConverterApp/Tactura/Resources")
    var backend: DepthBackend = ClassicalLayersBackend()
    if let pe = PositionEmbedding(contentsOf: res.appendingPathComponent("base_1x1370x1024.f32")) {
        backend = CoreMLDepthBackend(
            modelURL: res.appendingPathComponent("dav2_large_multifunction_f16.mlpackage"),
            positionEmbedding: pe)
    }
    let pipeline = ReliefPipeline(config: config, depthBackend: backend)
    guard let a = try? pipeline.analyze(rgb: rgb) else { return }
    let v = pipeline.buildVolume(a)

    print("\n--- mean |gradient| per layer: mine vs reference ---")
    print(String(format: "  %-18s %12s %12s %8s", "layer", "mine", "reference", "ratio"))
    for (name, mine) in [("05_z_ai", v.zAi), ("05_z_rough", v.zRough),
                         ("05_z_main", v.zMain), ("05_z_detail", v.zDetail),
                         ("06_height_final", v.height)] {
        guard let ref = try? f.plane(name) else { continue }
        let m = grad(mine), r = grad(ref)
        print(String(format: "  %-18s %12.6f %12.6f %7.2fx",
                     (name as NSString).utf8String!, m, r, r > 0 ? m/r : 0))
    }
}
