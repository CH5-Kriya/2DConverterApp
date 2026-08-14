import Foundation
import ReliefNumerics

/// Stage 4 — fix what the depth network smoothed away or quantized.
public enum Correct {

    /// Mirrors `s4_correct.correct`.
    ///
    /// `guide` is the preprocessed L* image, used as the edge reference.
    /// `discrete` marks layer-index output, which is treated very differently:
    /// there the steps are the artist's composition, not an artifact.
    public static func correct(depth: Plane, guide: Plane,
                               config: CorrectConfig,
                               discrete: Bool = false,
                               segmentation: Segmentation? = nil,
                               flatArt: Bool = false) -> Plane {
        let rows = depth.rows, cols = depth.cols
        var buf = depth.values

        func run(_ body: (UnsafePointer<Float>, UnsafeMutablePointer<Float>) -> Void) {
            var next = [Float](repeating: 0, count: buf.count)
            buf.withUnsafeBufferPointer { src in
                next.withUnsafeMutableBufferPointer { dst in
                    body(src.baseAddress!, dst.baseAddress!)
                }
            }
            buf = next
        }

        let preserve = config.preserveLayers || discrete

        if wantsQuantize(config: config, discrete: discrete, flatArt: flatArt,
                         segmentation: segmentation), let seg = segmentation {
            let labels = seg.labels.values.map { Int32($0) }
            run { src, dst in
                labels.withUnsafeBufferPointer { lb in
                    relief_quantize_layers(src, lb.baseAddress!, Int32(seg.count),
                                           dst, rows, cols)
                }
            }
        } else if preserve {
            run { src, dst in relief_clean_layers(src, dst, rows, cols) }
        } else {
            if config.despeckle {
                run { src, dst in
                    relief_despeckle(src, dst, rows, cols,
                                     Int32(config.despeckleKernel))
                }
            }
            if config.guidedFilter {
                run { src, dst in
                    guide.values.withUnsafeBufferPointer { g in
                        relief_guided_filter(src, g.baseAddress!, dst, rows, cols,
                                             Int32(config.guidedRadius),
                                             config.guidedEps)
                    }
                }
            }
            if config.deband {
                run { src, dst in
                    _ = relief_deband(src, dst, rows, cols,
                                      config.debandSpikeRatio,
                                      bandingMassThreshold)
                }
            }
        }

        if config.backgroundSuppress {
            run { src, dst in
                relief_suppress_background(src, dst, rows, cols,
                                           config.backgroundPercentile)
            }
        }

        return Plane(rows: rows, cols: cols,
                     values: buf.map { Swift.min(Swift.max($0, 0), 1) })
    }

    /// Fraction of pixels that must sit on isolated histogram levels before the
    /// map counts as banded. Continuous input measures 0%, quantized input 100%.
    public static let bandingMassThreshold = 0.25

    /// `auto` fires only on the one combination that needs it: a *continuous*
    /// depth model run on art the router called flat. That is the single
    /// failure the illustration branch exists to prevent.
    static func wantsQuantize(config: CorrectConfig, discrete: Bool,
                              flatArt: Bool, segmentation: Segmentation?) -> Bool {
        guard segmentation != nil else { return false }
        switch config.layerQuantize {
        case "always": return true
        case "never":  return false
        case "auto":   return flatArt && !discrete
        default:       return false
        }
    }
}
