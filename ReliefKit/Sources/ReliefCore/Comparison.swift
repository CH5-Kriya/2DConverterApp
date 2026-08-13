import Foundation

/// How a ported stage is judged against its golden fixture.
///
/// Two rules are deliberate and worth not relaxing later.
///
/// **Correlation is never the sole gate.** It is blind to a constant offset or
/// a scale factor, which is exactly what a DCT-normalization bug produces — and
/// what a fixed-square depth conversion produced: correlation 0.985–0.9996 while
/// max absolute error reached 0.60, up to 17 mm of misplaced depth on a 30 mm
/// relief. Every iterative stage is gated on correlation *and* max error.
///
/// **Deterministic stages are held near machine epsilon.** Most of them run the
/// same C++ the Python calls through `cv2`, so that is a realistic bar rather
/// than an aspirational one. If stage 1 is off by 1e-3 something is wrong, and
/// loosening the number only hides it until stage 7.

public struct Divergence: Sendable {
    public let maxAbsErr: Double
    public let meanAbsErr: Double
    public let correlation: Double
    /// Share of elements that differ at all. Meaningful for label images, where
    /// a float tolerance is not the right question.
    public let disagreementFraction: Double
    public let count: Int

    public var agreementFraction: Double { 1.0 - disagreementFraction }
}

public enum Tolerance: Sendable {
    /// Pointwise deterministic: a single absolute bound.
    case exact(maxAbsErr: Double)
    /// Iterative: both bounds must hold.
    case iterative(minCorrelation: Double, maxAbsErr: Double)
    /// Discrete labels: a minimum share of elements that must match exactly.
    case discrete(minAgreement: Double)

    public var describe: String {
        switch self {
        case .exact(let e):
            return "max abs err <= \(e)"
        case .iterative(let c, let e):
            return "corr >= \(c) and max abs err <= \(e)"
        case .discrete(let a):
            return "agreement >= \(a)"
        }
    }
}

/// The tolerances from the plan, keyed by fixture array name.
///
/// A stage that cannot meet one of these is a written finding and an explicit
/// sign-off — never a quiet edit to the number.
public enum StageTolerances {
    public static let table: [String: Tolerance] = [
        // Fed in, not computed, so this is 0 by construction. Keeping it in the
        // table documents that the Swift side must be given the *same* input
        // rather than reproduce PIL's LANCZOS resize -- otherwise a decode
        // difference masquerades as a stage-1 bug.
        "00_input":           .exact(maxAbsErr: 0.0),

        // Raw CIELAB, before CLAHE. L* spans [0, 100] and a*/b* roughly
        // [-128, 127], so a 1e-6 *absolute* bound is under one ulp of float32
        // at that magnitude and is unmeetable by any implementation. 1e-3
        // absolute here is ~1e-5 relative, the same strictness the normalized
        // planes get at 1e-6.
        "01_lab":             .exact(maxAbsErr: 1e-3),

        "01_lightness":       .exact(maxAbsErr: 1e-6),
        "01_brightness_Y":    .exact(maxAbsErr: 1e-6),
        "02_labels":          .discrete(minAgreement: 0.999),
        "02_albedo":          .exact(maxAbsErr: 1e-6),
        "04_depth_corrected": .exact(maxAbsErr: 1e-6),
        "05_z_ai":            .exact(maxAbsErr: 1e-6),
        "05_z_rough":         .exact(maxAbsErr: 1e-6),
        "05_z_detail":        .exact(maxAbsErr: 1e-6),
        "05_z_main":          .iterative(minCorrelation: 0.9995, maxAbsErr: 5e-3),
        "06_height_final":    .iterative(minCorrelation: 0.9999, maxAbsErr: 2e-3),
        // 03_depth_raw is judged by the separate Core ML harness, not here:
        // conversion error must never be able to hide inside a pipeline diff.
    ]

    public static func forArray(_ name: String) -> Tolerance? { table[name] }
}

public enum Compare {
    public static func divergence(_ got: Plane, _ expected: Plane) -> Divergence {
        precondition(got.count == expected.count,
                     "cannot compare \(got.shapeDescription) with \(expected.shapeDescription)")

        let n = got.count
        var maxAbs = 0.0
        var sumAbs = 0.0
        var differing = 0
        var sumA = 0.0, sumB = 0.0

        for i in 0..<n {
            let a = Double(got.values[i]), b = Double(expected.values[i])
            let d = abs(a - b)
            if d > maxAbs { maxAbs = d }
            sumAbs += d
            if d != 0 { differing += 1 }
            sumA += a
            sumB += b
        }

        let meanA = sumA / Double(n), meanB = sumB / Double(n)
        var cov = 0.0, varA = 0.0, varB = 0.0
        for i in 0..<n {
            let da = Double(got.values[i]) - meanA
            let db = Double(expected.values[i]) - meanB
            cov += da * db
            varA += da * da
            varB += db * db
        }
        // A constant plane has no correlation to speak of; report 1.0 when both
        // sides are constant and 0.0 when only one is, rather than NaN.
        let denom = (varA * varB).squareRoot()
        let corr = denom > 1e-30 ? cov / denom : (varA == varB ? 1.0 : 0.0)

        return Divergence(maxAbsErr: maxAbs,
                          meanAbsErr: sumAbs / Double(n),
                          correlation: corr,
                          disagreementFraction: Double(differing) / Double(n),
                          count: n)
    }

    public static func passes(_ d: Divergence, _ tolerance: Tolerance) -> Bool {
        switch tolerance {
        case .exact(let maxErr):
            return d.maxAbsErr <= maxErr
        case .iterative(let minCorr, let maxErr):
            return d.correlation >= minCorr && d.maxAbsErr <= maxErr
        case .discrete(let minAgreement):
            return d.agreementFraction >= minAgreement
        }
    }
}
