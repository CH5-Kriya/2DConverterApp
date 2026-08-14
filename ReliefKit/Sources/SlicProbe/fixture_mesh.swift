import Foundation
import ReliefCore

/// Same pipeline, but fed the Python's own `00_input` instead of decoding the
/// JPEG ourselves. If this comes out as smooth as the reference, the decoder is
/// the entire difference.
func meshFromFixtureInput() {
    let root = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/test_python/tests/golden_1536")
    guard let fixtures = try? GoldenFixture.discover(in: root),
          let f = fixtures.first,
          let rgb = try? f.plane("00_input") else { print("no 1536 fixture"); return }

    var config = f.manifest.config
    config.mesh.reliefMm = 30

    let res = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/ios-app/2DConverterApp/2DConverterApp/Resources")
    var backend: DepthBackend = ClassicalLayersBackend()
    if let pe = PositionEmbedding(contentsOf: res.appendingPathComponent("base_1x1370x1024.f32")) {
        backend = CoreMLDepthBackend(
            modelURL: res.appendingPathComponent("dav2_large_multifunction_f16.mlpackage"),
            positionEmbedding: pe)
    }
    let pipeline = ReliefPipeline(config: config, depthBackend: backend)
    guard let analysis = try? pipeline.analyze(rgb: rgb) else { print("analyze failed"); return }
    let volume = pipeline.buildVolume(analysis)
    let mesh = Mesh.build(height: volume.height, config: config.mesh)
    try? Export.binarySTL(mesh).write(to: URL(fileURLWithPath: "/tmp/swift_from_fixture.stl"))

    // Same height field, decimation off -- isolates the simplifier.
    var raw = config.mesh
    raw.decimate = false
    let undecimated = Mesh.build(height: volume.height, config: raw)
    try? Export.binarySTL(undecimated).write(to: URL(fileURLWithPath: "/tmp/swift_undecimated.stl"))
    print("  undecimated: \(undecimated.faceCount) faces -> /tmp/swift_undecimated.stl")
    print("\n--- mesh from the Python's own input ---")
    print("  regions \(analysis.regionCount) (reference 108)")
    print("  wrote /tmp/swift_from_fixture.stl")
}
