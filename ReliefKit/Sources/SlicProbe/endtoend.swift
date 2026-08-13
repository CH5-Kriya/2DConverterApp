import Foundation
import ReliefCore

/// Runs the whole engine on a fixture's input image, exactly as the app will:
/// no reference data injected anywhere, classical depth fallback, straight
/// through to an STL.
func runEndToEnd(root: URL) {
    guard let fixtures = try? GoldenFixture.discover(in: root),
          let fixture = fixtures.first(where: { $0.sample == "turntable" })
                     ?? fixtures.first else { return }
    guard let rgb = try? fixture.plane("00_input") else { return }

    print("\n--- end-to-end: \(fixture.sample) (\(rgb.rows)x\(rgb.cols)) ---")

    var config = fixture.manifest.config
    config.mesh.reliefMm = 30   // the good reference export used 30 mm, not 8

    let pipeline = ReliefPipeline(config: config)
    let clock = Date()

    var lastPhase = ""
    guard let analysis = try? pipeline.analyze(rgb: rgb, progress: { phase, done in
        if phase.rawValue != lastPhase {
            lastPhase = phase.rawValue
            print(String(format: "  %3.0f%%  %@", done * 100, phase.label))
        }
    }) else { print("  analyze FAILED"); return }
    let analyzeTime = Date().timeIntervalSince(clock)

    let volume = pipeline.buildVolume(analysis) { phase, done in
        print(String(format: "  %3.0f%%  %@", done * 100, phase.label))
    }
    print(String(format: "  %3.0f%%  %@", 0.70 * 100, PipelinePhase.mesh.label))
    let mesh = Mesh.build(height: volume.height, config: config.mesh)
    print(String(format: "  %3.0f%%  %@", 0.90 * 100, PipelinePhase.export.label))
    let stl = Export.binarySTL(mesh)
    let total = Date().timeIntervalSince(clock)

    print("""
      ---
      route          \(analysis.routing.mode) (\(String(format: "%.3f", analysis.routing.score)))
      regions        \(analysis.regionCount)
      depth backend  \(pipeline.depthBackend.name)
      light          [\(volume.light.map { String(format: "%.3f", $0) }.joined(separator: ", "))]
      plate          \(String(format: "%.1f x %.1f mm", mesh.widthMm, mesh.heightMm))
      relief         \(config.mesh.reliefMm) mm over \(config.mesh.baseMm) mm base
      sampling       \(String(format: "%.3f", mesh.mmPerPixel)) mm/pixel
      mesh           \(mesh.vertexCount) vertices / \(mesh.faceCount) faces
      watertight     \(mesh.isWatertight)
      volume         \(String(format: "%.1f", mesh.volumeMm3)) mm3
      STL            \(stl.count / 1_000_000) MB
      timing         analyze \(String(format: "%.1f", analyzeTime))s, total \(String(format: "%.1f", total))s
      """)
    for w in Export.checkPrintable(mesh, nozzleMm: config.export.nozzleMm) {
        print("      warning: \(w)")
    }

    let out = URL(fileURLWithPath: "/tmp/relief_endtoend.stl")
    try? stl.write(to: out)
    print("      wrote \(out.path)")
}
