import Foundation
import ReliefNumerics

/// Stage 1 — image conditioning, wrapping the C++ core in Swift types.
public enum Preprocess {

    /// sRGB → CIELAB, matching `skimage.color.rgb2lab`.
    /// Input must be a 3-channel plane in [0, 1]; output is 3-channel Lab.
    public static func rgb2lab(_ rgb: Plane) -> Plane {
        precondition(rgb.channels == 3, "rgb2lab needs a 3-channel plane")
        var out = [Float](repeating: 0, count: rgb.rows * rgb.cols * 3)
        rgb.values.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                relief_rgb2lab(src.baseAddress!, dst.baseAddress!,
                               rgb.rows, rgb.cols)
            }
        }
        return Plane(rows: rgb.rows, cols: rgb.cols, channels: 3, values: out)
    }

    /// `clip(lab[..., 0] / 100, 0, 1)` — the pipeline's `Y_L` before CLAHE.
    public static func lightness(fromLab lab: Plane) -> Plane {
        precondition(lab.channels == 3, "lightness needs a 3-channel Lab plane")
        var out = [Float](repeating: 0, count: lab.rows * lab.cols)
        lab.values.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                relief_lightness_from_lab(src.baseAddress!, dst.baseAddress!,
                                          lab.rows, lab.cols)
            }
        }
        return Plane(rows: lab.rows, cols: lab.cols, values: out)
    }

    /// CLAHE on a [0, 1] plane, matching `s1_preprocess._clahe`.
    public static func clahe(_ gray: Plane, clipLimit: Double = 2.0,
                             tileGrid: Int = 8) -> Plane {
        precondition(gray.channels == 1, "clahe needs a single-channel plane")
        var out = [Float](repeating: 0, count: gray.rows * gray.cols)
        gray.values.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                relief_clahe(src.baseAddress!, dst.baseAddress!,
                             gray.rows, gray.cols, clipLimit, Int32(tileGrid))
            }
        }
        return Plane(rows: gray.rows, cols: gray.cols, values: out)
    }

    /// Paper Eq. (1) — divide each region's lightness by its own albedo.
    ///
    /// Takes the segmentation as input rather than computing it, mirroring the
    /// reference: `albedo_normalize` needs stage 2's regions, which is why the
    /// pipeline calls it after segmentation rather than inside `preprocess`.
    public static func albedoNormalize(lightness: Plane, labels: Plane,
                                       albedo: [Float],
                                       floor: Float = 0.15) -> Plane {
        precondition(lightness.count == labels.count,
                     "lightness and labels must be the same size")
        let intLabels = labels.values.map { Int32($0) }
        var out = [Float](repeating: 0, count: lightness.count)
        lightness.values.withUnsafeBufferPointer { l in
            intLabels.withUnsafeBufferPointer { lab in
                albedo.withUnsafeBufferPointer { a in
                    out.withUnsafeMutableBufferPointer { dst in
                        relief_albedo_normalize(l.baseAddress!, lab.baseAddress!,
                                                a.baseAddress!, albedo.count,
                                                floor, dst.baseAddress!,
                                                lightness.rows, lightness.cols)
                    }
                }
            }
        }
        return Plane(rows: lightness.rows, cols: lightness.cols, values: out)
    }
}
