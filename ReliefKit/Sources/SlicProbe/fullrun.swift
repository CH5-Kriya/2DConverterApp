import Foundation
import ReliefCore

/// The whole app path on a real JPEG: load → analyze → volume → mesh → STL,
/// with the same config the Python reference used for `out/nyodog`.
func runFullOnJPEG() {
    let jpeg = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/assets/samples/nyodog.jpeg")
    guard let data = try? Data(contentsOf: jpeg) else { return }

    var config = ReliefConfig()
    config.mesh.reliefMm = 30          // matches out/nyodog
    guard let rgb = ReliefImage.load(data: data, maxEdge: config.preprocess.workRes)
    else { print("load failed"); return }

    print("\n--- full run on nyodog.jpeg (\(rgb.rows)x\(rgb.cols)) ---")

    // The real Core ML backend, pointed at the bundled artefacts directly, so
    // this reproduces exactly what the app does rather than the fallback.
    let res = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/ios-app/2DConverterApp/Tactura/Resources")
    var backend: DepthBackend = ClassicalLayersBackend()
    if let pe = PositionEmbedding(contentsOf: res.appendingPathComponent("base_1x1370x1024.f32")) {
        backend = CoreMLDepthBackend(
            modelURL: res.appendingPathComponent("dav2_large_multifunction_f16.mlpackage"),
            positionEmbedding: pe)
    }
    let pipeline = ReliefPipeline(config: config, depthBackend: backend)
    print("  depth backend: \(pipeline.depthBackend.name)")
    let analysis: Analysis
    do { analysis = try pipeline.analyze(rgb: rgb) }
    catch { print("  analyze FAILED: \(error)"); return }
    let volume = pipeline.buildVolume(analysis)
    let mesh = Mesh.build(height: volume.height, config: config.mesh)
    let stl = Export.binarySTL(mesh)
    try? stl.write(to: URL(fileURLWithPath: "/tmp/swift_nyodog.stl"))

    print("  route \(analysis.routing.mode)  regions \(analysis.regionCount)")
    print("  plate \(String(format: "%.1f x %.1f", mesh.widthMm, mesh.heightMm)) mm")
    print("  faces \(mesh.faceCount)  watertight \(mesh.isWatertight)")
    print("  wrote /tmp/swift_nyodog.stl")
}
