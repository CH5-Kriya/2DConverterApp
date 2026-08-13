import Foundation
import ReliefNumerics

/// Stage 2 — routing. Three scalars decide whether the artwork is treated as a
/// flat illustration or a realistic painting.
public struct Routing: Equatable, Sendable {
    public let mode: String
    public let score: Double
    public let flatAreaFrac: Double
    public let paletteConcentration: Double
    public let edgeStepRatio: Double
    public let forced: Bool

    public static let realistic = "realistic"
    public static let illustration = "illustration"
}

public enum Route {
    /// Mirrors `s2_route.route`. `lab` is the full CIELAB plane from stage 1
    /// (before CLAHE — the router reads `pre.lab`, not `pre.lightness`).
    public static func route(lab: Plane, config: RouteConfig) -> Routing {
        precondition(lab.channels == 3, "routing needs a 3-channel Lab plane")

        var metrics = [Float](repeating: 0, count: 3)
        lab.values.withUnsafeBufferPointer { src in
            metrics.withUnsafeMutableBufferPointer { dst in
                relief_route_metrics(src.baseAddress!, lab.rows, lab.cols,
                                     Int32(config.quantizeColors),
                                     dst.baseAddress!)
            }
        }

        // Equal weighting: each metric is independently informative and none has
        // earned a bigger vote on the evidence available.
        let score = (Double(metrics[0]) + Double(metrics[1]) + Double(metrics[2])) / 3.0

        let forced = config.mode == Routing.realistic
            || config.mode == Routing.illustration
        let mode: String
        if forced {
            mode = config.mode
        } else {
            mode = score >= config.flatnessThreshold
                ? Routing.illustration : Routing.realistic
        }

        return Routing(mode: mode, score: score,
                       flatAreaFrac: Double(metrics[0]),
                       paletteConcentration: Double(metrics[1]),
                       edgeStepRatio: Double(metrics[2]),
                       forced: forced)
    }
}
