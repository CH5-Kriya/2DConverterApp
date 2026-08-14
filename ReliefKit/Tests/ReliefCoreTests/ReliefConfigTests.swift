import XCTest
@testable import ReliefCore

/// The Python `config.py` is the specification; these assert the Swift mirror
/// has not drifted from it.
final class ReliefConfigTests: XCTestCase {

    /// Defaults are copies of `config.py`, not independent choices. A change
    /// here is either a deliberate port decision or a bug, and both should be
    /// visible in a diff.
    func testDefaultsMatchPython() {
        let cfg = ReliefConfig()

        XCTAssertEqual(cfg.preprocess.workRes, 1536)
        XCTAssertEqual(cfg.preprocess.albedoFloor, 0.15)
        XCTAssertEqual(cfg.preprocess.claheClipLimit, 2.0)

        XCTAssertEqual(cfg.segment.nSegments, 900)
        XCTAssertEqual(cfg.segment.mergeThreshold, 8.0)
        XCTAssertEqual(cfg.segment.minSegmentPx, 200)

        XCTAssertEqual(cfg.route.flatnessThreshold, 0.55)

        XCTAssertEqual(cfg.correct.guidedRadius, 8)
        XCTAssertEqual(cfg.correct.guidedEps, 1e-4)
        XCTAssertEqual(cfg.correct.layerQuantize, "auto")

        // Eq. (8) weights.
        XCTAssertEqual(cfg.volume.lambdaAi, 1.0)
        XCTAssertEqual(cfg.volume.lambdaRough, 0.35)
        XCTAssertEqual(cfg.volume.lambdaMain, 0.45)
        XCTAssertEqual(cfg.volume.lambdaDetail, 0.04)

        XCTAssertEqual(cfg.volume.sfsIters, 300)
        XCTAssertEqual(cfg.volume.sfsScale, 512)
        XCTAssertEqual(cfg.volume.sfsSorOmega, 1.6)
        XCTAssertEqual(cfg.volume.sfsProjectEvery, 20)
        XCTAssertEqual(cfg.volume.sfsMbcPercentile, 98.0)
        XCTAssertEqual(cfg.volume.roughSmoothIters, 60)

        XCTAssertEqual(cfg.mesh.plateWidthMm, 200.0)
        XCTAssertEqual(cfg.mesh.reliefMm, 8.0)
        XCTAssertEqual(cfg.mesh.baseMm, 3.0)
        XCTAssertEqual(cfg.mesh.maxGrid, 900)
        XCTAssertEqual(cfg.mesh.targetFaces, 400_000)
    }

    /// Python emits snake_case and carries keys this port deliberately dropped
    /// (`lotus_*`, `illustrators_depth_*`, `export.blend`). Decoding has to
    /// ignore those *and* fall back to defaults for anything absent, or every
    /// fixture manifest fails to load.
    func testDecodesPythonConfigIgnoringDroppedKeys() throws {
        let json = """
        {
          "preprocess": {"work_res": 768, "albedo_floor": 0.15},
          "segment": {"n_segments": 900, "merge_threshold": 8.0},
          "route": {"mode": "auto", "flatness_threshold": 0.55},
          "depth": {
            "backend": "auto",
            "dav2_model": "depth-anything/Depth-Anything-V2-Large-hf",
            "lotus_env": "lotus",
            "illustrators_depth_ckpt": "checkpoints/id_model.ckpt",
            "da3_force_cpu": true
          },
          "correct": {"guided_radius": 8, "layer_quantize": "auto"},
          "light": {"auto_estimate": true, "vector": [0.3, 0.4, 0.85]},
          "volume": {"lambda_main": 0.9, "sfs_iters": 300},
          "mesh": {"relief_mm": 30, "plate_height_mm": null},
          "export": {"stl": true, "blend": true, "glb": true, "obj": false},
          "seed": 0,
          "cache_dir": ".relief_cache"
        }
        """.data(using: .utf8)!

        let cfg = try ReliefConfig.decode(from: json)

        XCTAssertEqual(cfg.preprocess.workRes, 768)
        XCTAssertEqual(cfg.mesh.reliefMm, 30)
        XCTAssertNil(cfg.mesh.plateHeightMm)
        XCTAssertEqual(cfg.volume.lambdaMain, 0.9)

        // Absent from the JSON, so the default must survive decoding.
        XCTAssertEqual(cfg.volume.lambdaDetail, 0.04)
        XCTAssertEqual(cfg.segment.compactness, 12.0)
        XCTAssertEqual(cfg.correct.guidedEps, 1e-4)
    }

    func testRoundTrip() throws {
        var cfg = ReliefConfig()
        cfg.mesh.reliefMm = 30
        cfg.volume.lambdaDetail = 0.02

        let data = try ReliefConfig.makeEncoder().encode(cfg)
        let back = try ReliefConfig.decode(from: data)
        XCTAssertEqual(cfg, back)

        // Encoded keys must be snake_case so a Swift-written config is loadable
        // by the Python reference.
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("relief_mm"))
        XCTAssertTrue(text.contains("lambda_detail"))
        XCTAssertFalse(text.contains("reliefMm"))
    }
}

final class ComparisonTests: XCTestCase {

    func testIdenticalPlanes() {
        let p = Plane(rows: 2, cols: 2, values: [0.1, 0.2, 0.3, 0.4])
        let d = Compare.divergence(p, p)
        XCTAssertEqual(d.maxAbsErr, 0.0)
        XCTAssertEqual(d.agreementFraction, 1.0)
        XCTAssertEqual(d.correlation, 1.0, accuracy: 1e-12)
    }

    /// The failure mode the plan exists to catch: a shifted plane correlates
    /// perfectly while being uniformly wrong. Correlation alone would pass it.
    func testOffsetPlaneIsCaughtByMaxErrorNotCorrelation() {
        let a = Plane(rows: 1, cols: 4, values: [0.1, 0.2, 0.3, 0.4])
        let b = Plane(rows: 1, cols: 4, values: [0.3, 0.4, 0.5, 0.6])
        let d = Compare.divergence(a, b)

        XCTAssertEqual(d.correlation, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.maxAbsErr, 0.2, accuracy: 1e-6)

        XCTAssertFalse(Compare.passes(d, .iterative(minCorrelation: 0.9999,
                                                    maxAbsErr: 2e-3)))
    }

    func testDiscreteAgreement() {
        let a = Plane(rows: 1, cols: 1000, values: (0..<1000).map { Float($0 % 7) })
        var vals = a.values
        vals[0] += 1  // one disagreeing label out of 1000
        let b = Plane(rows: 1, cols: 1000, values: vals)

        let d = Compare.divergence(a, b)
        XCTAssertEqual(d.agreementFraction, 0.999, accuracy: 1e-9)
        XCTAssertTrue(Compare.passes(d, .discrete(minAgreement: 0.999)))
        XCTAssertFalse(Compare.passes(d, .discrete(minAgreement: 0.9995)))
    }
}
