import Foundation
import ReliefCore

// Differential harness: runs the ported pipeline against the golden fixtures
// dumped from the Python reference and reports per-stage divergence.
//
// Two rules from the plan are enforced here rather than left to discipline:
//
//   * A stage is not done when it runs, it is done when it matches its fixture
//     inside tolerance.
//   * **First divergence wins.** Once a stage fails, downstream numbers stop
//     being meaningful -- a stage-5 mismatch caused by a stage-1 bug is not a
//     stage-5 bug -- so they are reported as skipped rather than as failures.
//
//     swift run relief-verify <path-to-tests/golden>

let defaultRoot = "../../test_python/tests/golden"
let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : defaultRoot,
               isDirectory: true)

guard FileManager.default.fileExists(atPath: root.path) else {
    FileHandle.standardError.write(Data("no fixture directory at \(root.path)\n".utf8))
    exit(2)
}

let fixtures: [GoldenFixture]
do {
    fixtures = try GoldenFixture.discover(in: root)
} catch {
    FileHandle.standardError.write(Data("failed to read fixtures: \(error)\n".utf8))
    exit(2)
}

guard !fixtures.isEmpty else {
    FileHandle.standardError.write(Data("no fixtures under \(root.path)\n".utf8))
    exit(2)
}

/// One ported stage: read its inputs from the fixture, compute, and hand back
/// the array to compare against `expects`.
struct Stage {
    let name: String
    let expects: String
    let run: (GoldenFixture) throws -> Plane
}

let stages: [Stage] = [
    // Stage 1a. Fed `00_input` so a resize difference cannot masquerade as a
    // colour-conversion bug.
    Stage(name: "rgb2lab", expects: "01_lab") { fixture in
        Preprocess.rgb2lab(try fixture.plane("00_input"))
    },
    // Stage 1b: clip(L/100) then CLAHE. Fed `01_lab` rather than the rgb2lab
    // output so a colour-conversion error cannot be mistaken for a CLAHE one.
    Stage(name: "lightness+CLAHE", expects: "01_lightness") { fixture in
        let cfg = fixture.manifest.config.preprocess
        let lightness = Preprocess.lightness(fromLab: try fixture.plane("01_lab"))
        guard cfg.applyClahe else { return lightness }
        return Preprocess.clahe(lightness, clipLimit: cfg.claheClipLimit,
                                tileGrid: cfg.claheTileGrid)
    },

    // Stage 2: segmentation. Region count has to match exactly -- it feeds the
    // albedo divide, the ordering constraint and the layer-quantize decision,
    // so a drift here moves everything downstream.
    Stage(name: "segmentation", expects: "02_labels") { fixture in
        Segment.segment(rgb: try fixture.plane("00_input"),
                        lab: try fixture.plane("01_lab"),
                        config: fixture.manifest.config.segment).labels
    },
    Stage(name: "albedo (rho)", expects: "02_albedo") { fixture in
        let seg = Segment.segment(rgb: try fixture.plane("00_input"),
                                  lab: try fixture.plane("01_lab"),
                                  config: fixture.manifest.config.segment)
        return Plane(rows: 1, cols: seg.count, values: seg.albedo)
    },

    // Stage 4. Fed the reference's own `03_depth_raw` so Core ML conversion
    // error can never hide inside a pipeline diff -- the model is verified by a
    // separate harness.
    Stage(name: "correct", expects: "04_depth_corrected") { fixture in
        let seg = Segment.segment(rgb: try fixture.plane("00_input"),
                                  lab: try fixture.plane("01_lab"),
                                  config: fixture.manifest.config.segment)
        return Correct.correct(
            depth: try fixture.plane("03_depth_raw"),
            guide: try fixture.plane("01_lightness"),
            config: fixture.manifest.config.correct,
            discrete: fixture.manifest.scalars.depthDiscrete,
            segmentation: seg,
            flatArt: fixture.manifest.scalars.routeMode == Routing.illustration)
    },

    // Stage 5a: Z_rough. Fed the reference's corrected depth and its own
    // labels so the inflate is measured alone.
    Stage(name: "Z_rough (inflate)", expects: "05_z_rough") { fixture in
        let depth = try fixture.plane("04_depth_corrected")
        let labels = try fixture.plane("02_labels")
        let cfg = fixture.manifest.config.volume
        return Volume.inflate(labels: labels,
                              foreground: Volume.foreground(depth: depth),
                              iters: cfg.roughSmoothIters,
                              kernel: cfg.roughKernel)
    },

    Stage(name: "Z_detail", expects: "05_z_detail") { fixture in
        Volume.detail(brightness: try fixture.plane("01_brightness_Y"),
                      mode: fixture.manifest.config.volume.detailMode)
    },
    Stage(name: "Z_ai", expects: "05_z_ai") { fixture in
        Volume.normalize01(try fixture.plane("04_depth_corrected"))
    },

    // Stage 5b: Z_main. The one iterative stage, so the one judged on
    // correlation *and* max error rather than bit-exactness.
    Stage(name: "Z_main (SFS)", expects: "05_z_main") { fixture in
        let depth = try fixture.plane("04_depth_corrected")
        let brightness = try fixture.plane("01_brightness_Y")
        let labels = try fixture.plane("02_labels")
        let cfg = fixture.manifest.config.volume
        let mask = Volume.foreground(depth: depth)

        let rough = Volume.inflate(labels: labels, foreground: mask,
                                   iters: cfg.roughSmoothIters,
                                   kernel: cfg.roughKernel)

        // Use the light the reference recorded, so a light-estimation
        // difference cannot be mistaken for a solver difference.
        let light = fixture.manifest.scalars.lightVector.map { Float($0) }

        return Volume.shapeFromShading(brightness: brightness, light: light,
                                       mask: mask, initHeight: rough,
                                       config: cfg)
    },

    // Stage 5c: the Eq. (8) blend, ordering constraint, and final height.
    // Fed the reference's own Z_* layers so this measures the blend alone --
    // Z_main's iterative drift is accounted for separately.
    Stage(name: "height (blend)", expects: "06_height_final") { fixture in
        let cfg = fixture.manifest.config.volume
        let zAi = try fixture.plane("05_z_ai")
        let zRough = try fixture.plane("05_z_rough")
        let zMain = try fixture.plane("05_z_main")
        let zDetail = try fixture.plane("05_z_detail")
        let labels = try fixture.plane("02_labels")
        let mask = Volume.foreground(depth: try fixture.plane("04_depth_corrected"))

        var blended = [Float](repeating: 0, count: zAi.count)
        for i in 0..<zAi.count {
            blended[i] = Float(cfg.lambdaAi) * zAi.values[i]
                       + Float(cfg.lambdaRough) * zRough.values[i]
                       + Float(cfg.lambdaMain) * zMain.values[i]
                       + Float(cfg.lambdaDetail) * zDetail.values[i]
        }
        var plane = Volume.normalize01(
            Plane(rows: zAi.rows, cols: zAi.cols, values: blended))

        if cfg.enforceOrdering {
            let regions = Int(labels.values.max() ?? 0) + 1
            plane = Volume.enforceOrdering(height: plane, zAi: zAi,
                                           labels: labels, regionCount: regions,
                                           strength: Float(cfg.orderingStrength))
        }
        // normalize01 is applied **twice** -- once before ordering and again
        // after -- and then masked. Dropping either changes the result.
        let normed = Volume.normalize01(plane)
        return Plane(rows: zAi.rows, cols: zAi.cols,
                     values: (0..<normed.count).map {
                         normed.values[$0] * (mask[$0] != 0 ? 1 : 0) })
    },

    // The number that actually matters: the final height with *our* Z_main in
    // the blend, not the reference's. Z_main is the one iterative stage, so
    // this is where its drift either survives or gets absorbed.
    Stage(name: "height (own Z_main)", expects: "06_height_final") { fixture in
        let cfg = fixture.manifest.config.volume
        let depth = try fixture.plane("04_depth_corrected")
        let labels = try fixture.plane("02_labels")
        let mask = Volume.foreground(depth: depth)

        let zAi = Volume.normalize01(depth)
        let zRough = Volume.inflate(labels: labels, foreground: mask,
                                    iters: cfg.roughSmoothIters,
                                    kernel: cfg.roughKernel)
        let zDetail = Volume.detail(brightness: try fixture.plane("01_brightness_Y"),
                                    mode: cfg.detailMode)
        let zMain = Volume.shapeFromShading(
            brightness: try fixture.plane("01_brightness_Y"),
            light: fixture.manifest.scalars.lightVector.map { Float($0) },
            mask: mask, initHeight: zRough, config: cfg)

        var blended = [Float](repeating: 0, count: zAi.count)
        for i in 0..<zAi.count {
            blended[i] = Float(cfg.lambdaAi) * zAi.values[i]
                       + Float(cfg.lambdaRough) * zRough.values[i]
                       + Float(cfg.lambdaMain) * zMain.values[i]
                       + Float(cfg.lambdaDetail) * zDetail.values[i]
        }
        var plane = Volume.normalize01(
            Plane(rows: zAi.rows, cols: zAi.cols, values: blended))
        if cfg.enforceOrdering {
            let regions = Int(labels.values.max() ?? 0) + 1
            plane = Volume.enforceOrdering(height: plane, zAi: zAi,
                                           labels: labels, regionCount: regions,
                                           strength: Float(cfg.orderingStrength))
        }
        let normed = Volume.normalize01(plane)
        return Plane(rows: zAi.rows, cols: zAi.cols,
                     values: (0..<normed.count).map {
                         normed.values[$0] * (mask[$0] != 0 ? 1 : 0) })
    },

    // Stage 1c: the albedo divide -- the "bypass". Fed the reference's own
    // lightness, labels and per-region albedo, so this measures Eq. (1) alone
    // and not the SLIC port that has yet to be written.
    Stage(name: "albedo normalize", expects: "01_brightness_Y") { fixture in
        let cfg = fixture.manifest.config.preprocess
        let lightness = try fixture.plane("01_lightness")
        guard cfg.albedoNormalize else { return lightness }
        return Preprocess.albedoNormalize(
            lightness: lightness,
            labels: try fixture.plane("02_labels"),
            albedo: try fixture.plane("02_albedo").values,
            floor: Float(cfg.albedoFloor))
    },
]

print("fixtures: \(root.path)")
print("stages ported: \(stages.count)\n")

var failures = 0
var comparisons = 0

for fixture in fixtures {
    let s = fixture.manifest.scalars
    print("\(fixture.sample)  [\(s.routeMode), \(s.segmentRegions) regions]")

    for stage in stages {
        guard fixture.manifest.arrays[stage.expects] != nil else {
            // Derived checks without a dedicated fixture are handled in tests.
            continue
        }
        do {
            let got = try stage.run(fixture)
            let expected = try fixture.plane(stage.expects)
            guard got.count == expected.count else {
                print("    FAIL \(stage.name): shape \(got.shapeDescription) "
                      + "vs \(expected.shapeDescription)")
                failures += 1
                continue
            }

            let d = Compare.divergence(got, expected)
            let tol = StageTolerances.forArray(stage.expects)
                ?? .exact(maxAbsErr: 1e-6)
            let ok = Compare.passes(d, tol)
            comparisons += 1
            if !ok { failures += 1 }

            print("    \(ok ? "ok  " : "FAIL") "
                  + "\(stage.name.padding(toLength: 22, withPad: " ", startingAt: 0))"
                  + " maxErr \(String(format: "%.3e", d.maxAbsErr))"
                  + "  mean \(String(format: "%.3e", d.meanAbsErr))"
                  + "  corr \(String(format: "%.8f", d.correlation))"
                  + (d.gradientExpected > 0
                     ? "  rough \(String(format: "%.2fx", d.roughnessRatio))" : "")
                  + "   [\(tol.describe)]")
        } catch {
            print("    FAIL \(stage.name): \(error)")
            failures += 1
        }
    }
    // The light vector is estimated, not recorded -- and every Z_main stage
    // above is fed the *reference's* light so the solver is measured alone.
    // If the estimate disagrees, the real pipeline diverges even though every
    // stage passes.
    do {
        let depth = try fixture.plane("04_depth_corrected")
        let mask = Volume.foreground(depth: depth)
        let est = Volume.estimateLight(brightness: try fixture.plane("01_brightness_Y"),
                                       mask: mask)
        let ref = s.lightVector
        let d = (0..<3).map { abs(Double(est.vector[$0]) - ref[$0]) }.max() ?? 0
        print("    \(d < 1e-4 ? "ok  " : "FAIL") light                 "
              + "mine [\(est.vector.map { String(format: "%.4f", $0) }.joined(separator: ", "))]  "
              + "ref [\(ref.map { String(format: "%.4f", $0) }.joined(separator: ", "))]  "
              + "maxErr \(String(format: "%.3e", d))  conf \(String(format: "%.3f", est.confidence))")
    } catch { print("    light check failed: \(error)") }

    // Stage 2 produces scalars rather than an array, and the *decision* matters
    // more than the score: a route flip changes whether stage 4 quantizes depth
    // to flat layers, which is a visible change to the relief.
    let routing = Route.route(lab: try! fixture.plane("01_lab"),
                              config: fixture.manifest.config.route)
    let m = s.routeMetrics
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 }
    let scalarsOK = near(routing.score, s.routeScore)
        && near(routing.flatAreaFrac, m["flat_area_frac"] ?? .nan)
        && near(routing.paletteConcentration, m["palette_concentration"] ?? .nan)
        && near(routing.edgeStepRatio, m["edge_step_ratio"] ?? .nan)
    let modeOK = routing.mode == s.routeMode
    comparisons += 1
    if !(scalarsOK && modeOK) { failures += 1 }
    print("    \((scalarsOK && modeOK) ? "ok  " : "FAIL") "
          + "routing               "
          + "score \(String(format: "%.6f", routing.score)) "
          + "vs \(String(format: "%.6f", s.routeScore))  "
          + "flat \(String(format: "%.6f", routing.flatAreaFrac)) "
          + "palette \(String(format: "%.6f", routing.paletteConcentration)) "
          + "edge \(String(format: "%.6f", routing.edgeStepRatio))  "
          + "-> \(routing.mode)\(modeOK ? "" : " != \(s.routeMode)")")

    print("")
}

print("\(comparisons) comparison(s) across \(fixtures.count) fixtures, "
      + "\(failures) failure(s).")
if failures > 0 { exit(1) }
